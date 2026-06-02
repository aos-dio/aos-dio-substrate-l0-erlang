%%%-------------------------------------------------------------------
%% @doc spine — Public Spine routing API
%%
%% 4-function public API per ea-m1-r4 §3 deliverable 1:
%%   register/2 / lookup/1 / lookup_urn/1 / deregister/1
%%
%% Backing state machine: `spine_ra_machine` (ra-replicated; R2 anchor).
%% URN type: binary (builder-era convention per Meta §1 + R4 §7 — post-Graphheight
%%           uGraph_concept swap explicitly forward-cached to W2+).
%%
%% Liveness handling (§3 deliverable 3 + §4 verification 3):
%% Per-node monitoring via `spine_pid_monitor` gen_server. spine:register/2
%% submits the ra command (replicates) AND tells the local spine_pid_monitor to
%% erlang:monitor/2 the PID. On DOWN, the monitor issues
%% {deregister_pid, PID} into the ra cluster — invariant: no stale URN↔dead-PID
%% bindings persist beyond ~monitor-delivery-latency (~ms bound; documented).
%%%-------------------------------------------------------------------
-module(spine).

-export([
    register/2,
    lookup/1,
    lookup_urn/1,
    deregister/1,
    cluster_name/0
]).

-type urn() :: binary().

%% Canonical ra cluster name (matches spine_app.erl env)
cluster_name() -> spine_ra_cluster.

%% Local ServerId — matches the ra:start_cluster bootstrap (R2)
local_server_id() ->
    {spine_ra_machine, node()}.

%%%-------------------------------------------------------------------
%% @doc Register a URN↔PID binding.
%% Replicates via ra quorum. Also subscribes the local liveness monitor
%% so the binding auto-deregisters on PID death.
%%%-------------------------------------------------------------------
-spec register(urn(), pid()) -> ok | {error, term()}.
register(URN, PID) when is_binary(URN), is_pid(PID) ->
    case ra:process_command(local_server_id(), {register, URN, PID}) of
        {ok, ok, _Leader} ->
            spine_pid_monitor:track(PID),
            ok;
        {error, Reason} ->
            {error, Reason};
        Other ->
            {error, Other}
    end.

%%%-------------------------------------------------------------------
%% @doc Lookup URN → PID (consistent quorum read).
%% Returns {ok, PID} or {error, not_found}.
%%%-------------------------------------------------------------------
-spec lookup(urn()) -> {ok, pid()} | {error, not_found | term()}.
lookup(URN) when is_binary(URN) ->
    case ra:local_query(local_server_id(),
                         fun(State) ->
                             maps:get(URN, maps:get(forward, State, #{}), not_found)
                         end) of
        {ok, {_RaIdx, not_found}, _Leader} -> {error, not_found};
        {ok, {_RaIdx, PID}, _Leader} when is_pid(PID) -> {ok, PID};
        {error, Reason} -> {error, Reason};
        Other -> {error, Other}
    end.

%%%-------------------------------------------------------------------
%% @doc Reverse lookup PID → URN.
%%%-------------------------------------------------------------------
-spec lookup_urn(pid()) -> {ok, urn()} | {error, not_found | term()}.
lookup_urn(PID) when is_pid(PID) ->
    case ra:local_query(local_server_id(),
                         fun(State) ->
                             maps:get(PID, maps:get(reverse, State, #{}), not_found)
                         end) of
        {ok, {_RaIdx, not_found}, _Leader} -> {error, not_found};
        {ok, {_RaIdx, URN}, _Leader} when is_binary(URN) -> {ok, URN};
        {error, Reason} -> {error, Reason};
        Other -> {error, Other}
    end.

%%%-------------------------------------------------------------------
%% @doc Deregister a URN binding.
%%%-------------------------------------------------------------------
-spec deregister(urn()) -> ok | {error, term()}.
deregister(URN) when is_binary(URN) ->
    case ra:process_command(local_server_id(), {deregister, URN}) of
        {ok, ok, _Leader} -> ok;
        {error, Reason} -> {error, Reason};
        Other -> {error, Other}
    end.
