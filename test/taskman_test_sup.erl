%%
%% Taskman
%% A supervisor for testing

-module(taskman_test_sup).
-behaviour(supervisor).

%%

-export([start_link/1]).
-export([init/1]).

%%

-spec start_link([{}]) -> {ok, pid()} | {error, any()}.

start_link(Options) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Options).

%%

-spec init([{}]) -> {ok, {{Strategy, MR, MS}, [ChildSpec]}} when
    Strategy :: supervisor:strategy(),
    MR :: pos_integer(),
    MS :: pos_integer(),
    ChildSpec :: supervisor:child_spec().

init(_Globals) ->
    Strategy = {rest_for_one, 60, 30},
    ChildSpecs = [
        taskman:child_spec(taskman, local),
        taskman_task_killer:child_spec(taskman_task_killer, local)
    ],
    {ok, {Strategy, ChildSpecs}}.
