%%
%% Taskman
%% Main supervisor

-module(taskman_sup).
-behaviour(supervisor).

%%

-export([start_link/1]).
-export([init/1]).
-export([child_spec/1]).

%%

-spec start_link([{}]) -> {ok, pid()} | {error, any()}.

start_link(Options) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Options).

-spec child_spec([{}]) -> supervisor:child_spec().

child_spec(Options) ->
    {
        taskman_sup,
        {taskman_sup, start_link, [Options]},
        permanent,
        infinity,
        supervisor,
        [taskman_sup]
    }.
%%

-spec init([{}]) -> {ok, {{Strategy, MR, MS}, [ChildSpec]}} when
    Strategy :: supervisor:strategy(),
    MR :: pos_integer(),
    MS :: pos_integer(),
    ChildSpec :: supervisor:child_spec().

init(_Globals) ->
    Strategy = {rest_for_one, 60, 30},
    ChildSpecs = [
        {
            taskman,
            {taskman, start_link, [{local, taskman}]},
            permanent,
            infinity,
            supervisor,
            [taskman]
        },
        {
            taskman_task_killer,
            {taskman_task_killer, start_link, [{local, taskman_task_killer}]},
            permanent,
            infinity,
            supervisor,
            [taskman_task_killer]
        }
    ],
    {ok, {Strategy, ChildSpecs}}.
