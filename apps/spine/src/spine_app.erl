%%%-------------------------------------------------------------------
%% @doc spine OTP application callback module
%%
%% Bootstraps the `ra` system + spine_sup top-level supervisor.
%% `ra` system + cluster startup is handled by spine_sup at start time.
%%%-------------------------------------------------------------------
-module(spine_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% Start ra system (idempotent — ra:start/0 handles already-started case)
    ok = application:ensure_started(ra),
    spine_sup:start_link().

stop(_State) ->
    ok.
