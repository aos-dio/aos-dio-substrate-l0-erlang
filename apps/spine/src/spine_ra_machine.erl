%%%-------------------------------------------------------------------
%% @doc spine_ra_machine — Spine replicated state machine module
%%
%% Implements the `ra_machine` behaviour. The state structure is the
%% Spine URN↔PID **bidirectional** routing table (extended at R4).
%%
%% Per EA Ruling 3 (forum-review 1432 R): module name canonical is
%% `spine_ra_machine` — framing-neutral; names the responsibility.
%%
%% State shape (R4): #{forward => #{URN => PID}, reverse => #{PID => URN}}.
%% Commands (R4 canonical set):
%%   {register, URN, PID}      — adds bidirectional binding
%%   {deregister, URN}         — removes by URN
%%   {deregister_pid, PID}     — removes by PID (for liveness auto-deregister)
%%   {lookup, URN}             — returns {ok, PID} | {error, not_found}
%%   {lookup_urn, PID}         — returns {ok, URN} | {error, not_found}
%%
%% Legacy commands (R2 backwards-compat; preserved for forward log replay):
%%   {put, URN, PID}           — mapped to register
%%   {get, URN}                — mapped to lookup (legacy reply shape: PID | not_found)
%%   {delete, URN}             — mapped to deregister
%%
%% URN is forward-cached as binary; post-Graphheight uGraph_concept swap
%% deferred to W2+ per relay §3 deliverable 3 framing (Meta §1 + §6 R4).
%%%-------------------------------------------------------------------
-module(spine_ra_machine).
-behaviour(ra_machine).
-compile({no_auto_import, [apply/3]}).

-export([init/1, apply/3]).

-type state() :: #{forward => #{binary() => pid()},
                   reverse => #{pid() => binary()}}.

-type command() ::
    {register, URN :: binary(), PID :: pid()}
    | {deregister, URN :: binary()}
    | {deregister_pid, PID :: pid()}
    | {lookup, URN :: binary()}
    | {lookup_urn, PID :: pid()}
    %% Legacy R2 commands (backwards-compat):
    | {put, URN :: binary(), PID :: pid()}
    | {get, URN :: binary()}
    | {delete, URN :: binary()}.

%%%-------------------------------------------------------------------
%% @doc ra_machine init — empty bidirectional state
%%%-------------------------------------------------------------------
-spec init(map()) -> state().
init(_Config) ->
    #{forward => #{}, reverse => #{}}.

%%%-------------------------------------------------------------------
%% @doc ra_machine apply — deterministic command application
%%%-------------------------------------------------------------------
-spec apply(map(), command(), state()) -> {state(), Reply :: term()}.
%% R4 register: bidirectional add. If URN was previously bound to another PID,
%% remove the stale reverse entry. If PID was previously bound to another URN,
%% remove the stale forward entry. Then add the new binding.
apply(_Meta, {register, URN, PID}, State = #{forward := F, reverse := R}) ->
    F1 = case maps:find(PID, R) of
        {ok, OldURN} -> maps:remove(OldURN, F);
        error -> F
    end,
    R1 = case maps:find(URN, F) of
        {ok, OldPID} -> maps:remove(OldPID, R);
        error -> R
    end,
    F2 = maps:put(URN, PID, F1),
    R2 = maps:put(PID, URN, R1),
    {State#{forward => F2, reverse => R2}, ok};

%% R4 deregister by URN
apply(_Meta, {deregister, URN}, State = #{forward := F, reverse := R}) ->
    case maps:find(URN, F) of
        {ok, PID} ->
            F1 = maps:remove(URN, F),
            R1 = maps:remove(PID, R),
            {State#{forward => F1, reverse => R1}, ok};
        error ->
            {State, ok}
    end;

%% R4 deregister by PID (liveness auto-deregister)
apply(_Meta, {deregister_pid, PID}, State = #{forward := F, reverse := R}) ->
    case maps:find(PID, R) of
        {ok, URN} ->
            F1 = maps:remove(URN, F),
            R1 = maps:remove(PID, R),
            {State#{forward => F1, reverse => R1}, ok};
        error ->
            {State, ok}
    end;

%% R4 lookup URN → PID
apply(_Meta, {lookup, URN}, State = #{forward := F}) ->
    Reply = case maps:find(URN, F) of
        {ok, PID} -> {ok, PID};
        error -> {error, not_found}
    end,
    {State, Reply};

%% R4 lookup PID → URN (reverse)
apply(_Meta, {lookup_urn, PID}, State = #{reverse := R}) ->
    Reply = case maps:find(PID, R) of
        {ok, URN} -> {ok, URN};
        error -> {error, not_found}
    end,
    {State, Reply};

%% R2 legacy put → register
apply(Meta, {put, URN, PID}, State) ->
    apply(Meta, {register, URN, PID}, State);

%% R2 legacy get → lookup (legacy reply shape: PID | not_found)
apply(_Meta, {get, URN}, State = #{forward := F}) ->
    Reply = maps:get(URN, F, not_found),
    {State, Reply};

%% R2 legacy delete → deregister
apply(Meta, {delete, URN}, State) ->
    apply(Meta, {deregister, URN}, State);

%% Unknown command
apply(_Meta, _UnknownCmd, State) ->
    {State, {error, unknown_command}}.
