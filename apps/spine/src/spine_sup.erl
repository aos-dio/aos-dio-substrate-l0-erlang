%%%-------------------------------------------------------------------
%% @doc spine top-level supervisor
%%
%% one_for_all base supervisor per Q-class 4-tier supervision shape.
%% At Phase A R2, only the ra-cluster-bootstrapper child is started here.
%% R3+ will add Mnesia bridge + state-machine consumer children.
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
    ChildSpecs = [],   %% No supervised children at R2; ra cluster is bootstrapped via API
    {ok, {SupFlags, ChildSpecs}}.
