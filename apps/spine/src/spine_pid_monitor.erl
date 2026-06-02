%%%-------------------------------------------------------------------
%% @doc spine_pid_monitor — Per-node PID liveness monitor for Spine routing.
%%
%% gen_server registered as {local, spine_pid_monitor} on each substrate-L0
%% node. spine:register/2 calls spine_pid_monitor:track/1 to subscribe.
%%
%% On DOWN: issues {deregister_pid, PID} into the ra cluster via local
%% ServerId. ra quorum replication ensures the binding is removed cluster-wide.
%%
%% Liveness latency bound: 1 erlang:monitor message delivery (~µs–ms local;
%% ~ms over distribution). The monitor is not a hot path; throughput trades
%% off against the simplicity of "exactly one monitor per registered PID".
%%%-------------------------------------------------------------------
-module(spine_pid_monitor).
-behaviour(gen_server).

-export([start_link/0, track/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%-------------------------------------------------------------------
%% @doc Begin monitoring a PID. Called from spine:register/2.
%%%-------------------------------------------------------------------
-spec track(pid()) -> ok.
track(PID) when is_pid(PID) ->
    gen_server:cast(?SERVER, {track, PID}).

init([]) ->
    {ok, #{monitored => sets:new([{version, 2}])}, hibernate}.

handle_call(_Req, _From, State) ->
    {reply, {error, not_implemented}, State, hibernate}.

handle_cast({track, PID}, State = #{monitored := Set}) ->
    case sets:is_element(PID, Set) of
        true -> {noreply, State, hibernate};
        false ->
            erlang:monitor(process, PID),
            {noreply, State#{monitored => sets:add_element(PID, Set)}, hibernate}
    end;
handle_cast(_Msg, State) ->
    {noreply, State, hibernate}.

handle_info({'DOWN', _Ref, process, PID, _Reason}, State = #{monitored := Set}) ->
    %% Replicated deregister via the local ra ServerId
    LocalServerId = {spine_ra_machine, node()},
    _Result = ra:process_command(LocalServerId, {deregister_pid, PID}),
    {noreply, State#{monitored => sets:del_element(PID, Set)}, hibernate};
handle_info(_Msg, State) ->
    {noreply, State, hibernate}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
