%%%-------------------------------------------------------------------
%% @doc spine top-level supervisor
%%
%% one_for_all base supervisor per Q-class 4-tier supervision shape.
%%
%% Children:
%%   - spine_pid_monitor (R4 — PID liveness monitor; registered local server)
%%
%% R3+ may add Mnesia bridge children.
%%%-------------------------------------------------------------------
-module(spine_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 5,
                 period => 60},
    ChildSpecs = [
        #{id => spine_pid_monitor,
          start => {spine_pid_monitor, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker,
          modules => [spine_pid_monitor]}
    ],
    {ok, {SupFlags, ChildSpecs}}.
