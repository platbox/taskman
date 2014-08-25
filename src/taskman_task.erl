%%%
%%% Taskman
%%% Task behaviour declarations

-module(taskman_task).

%%

-type task_id() :: term().

-type task_state() :: term().

-type task_result() ::
    ok |
    {ok, term()} |
    {ok, term(), term()} |
    {error, Reason :: hard_time_limit_exceeded | {unexpected_exit, any()} | any()}.

-export_type([task_id/0]).
-export_type([task_state/0]).
-export_type([task_result/0]).

%%

-callback task_init(Options :: term()) ->
    {ok, task_id(), Result :: term(), task_state()} |
    {ok, task_id(), Result :: term(), task_state(), timeout()}.

-callback task_perform(task_id(), task_state()) -> task_result().

-callback task_finish(task_id(), task_result()) -> any().
