%%%-------------------------------------------------------------------
%% @doc spine_ra_machine — Spine replicated state machine module
%%
%% Implements the `ra_machine` behaviour. The state structure is the
%% Spine URN↔PID routing table (forward-cached per Meta §1).
%%
%% Per EA Ruling 3 (forum-review 1432 R): module name canonical is
%% `spine_ra_machine` — names the responsibility (Spine module implementing
%% the ra_machine behaviour); framing-neutral (doesn't depend on
%% DIO/Coretex semantic correction); convention-extensible.
%%
%% State shape: #{routing_table => #{URN => PID, ...}}.
%% Commands: {put, URN, PID} / {get, URN} / {delete, URN}.
%% URN is forward-cached as binary; post-Graphheight uGraph_concept swap
%% deferred to W2+ per relay §3 deliverable 3 framing.
%%%-------------------------------------------------------------------
-module(spine_ra_machine).
-behaviour(ra_machine).

-export([
    init/1,
    apply/3
]).

-type state() :: #{routing_table => #{binary() => pid()}}.

-type command() ::
    {put, URN :: binary(), PID :: pid()}
    | {get, URN :: binary()}
    | {delete, URN :: binary()}.

%%%-------------------------------------------------------------------
%% @doc ra_machine init callback
%%
%% Returns the initial state — empty routing table.
%% @end
%%%-------------------------------------------------------------------
-spec init(map()) -> state().
init(_Config) ->
    #{routing_table => #{}}.

%%%-------------------------------------------------------------------
%% @doc ra_machine apply callback
%%
%% Applies a command to the state machine + returns new state + reply.
%% Called on every node after quorum agreement; MUST be deterministic.
%% @end
%%%-------------------------------------------------------------------
-spec apply(map(), command(), state()) -> {state(), Reply :: term()}.
apply(_Meta, {put, URN, PID}, State = #{routing_table := RT}) ->
    NewRT = maps:put(URN, PID, RT),
    {State#{routing_table => NewRT}, ok};
apply(_Meta, {get, URN}, State = #{routing_table := RT}) ->
    Result = maps:get(URN, RT, not_found),
    {State, Result};
apply(_Meta, {delete, URN}, State = #{routing_table := RT}) ->
    NewRT = maps:remove(URN, RT),
    {State#{routing_table => NewRT}, ok};
apply(_Meta, _UnknownCmd, State) ->
    {State, {error, unknown_command}}.
