%%%
%%% Taskman
%%% Persisted tasks manager

-module(taskman).
-behaviour(supervisor).

%%

-export([start_link/1]).
-export([child_spec/2]).

-export([invoke/2]).
-export([complete/2]).
-export([complete/3]).
-export([lookup/1]).
-export([kill/1]).
-export([finish/3]).

%% Private API

-export([claim_id/1]).

%% Internals

-export([init/1]).
-export([start_task/3]).
-export([init_task/3]).
-export([start_task/4]).
-export([init_finish_task/4]).

%%

-type task_id() :: taskman_task:task_id().
-type task_result() :: taskman_task:task_result().

%%

-spec start_link({local, atom()} | {global, term()}) -> {ok, pid()} | {error, any()}.

start_link(Name) ->
    supervisor:start_link(Name, ?MODULE, []).

%%

child_spec(Name, Registry) ->
    {
        Name,
        {taskman, start_link, [{Registry, taskman}]},
        permanent,
        infinity,
        supervisor,
        [taskman]
    }.

-spec invoke(module(), term()) -> {ok, pid(), Result :: any()} | {error, any()}.

invoke(Module, Options) ->
    supervisor:start_child(?MODULE, [invoke, Module, Options]).

-spec complete(module(), term()) -> task_result().

complete(Module, Options) ->
    complete(Module, Options, infinity).

-spec complete(module(), term(), timeout()) -> task_result().

complete(Module, Options, Timeout) ->
    case invoke(Module, Options) of
        {ok, Pid, _Result} ->
            MRef = monitor(process, Pid),
            receive
                {'DOWN', MRef, process, Pid, {shutdown, Result}} ->
                    Result;
                {'DOWN', MRef, process, Pid, Reason} ->
                    {error, {unexpected, Reason}}
            after Timeout ->
                {error, timeout}
            end;
        Error ->
            Error
    end.

-spec lookup(task_id()) -> pid() | undefined.

lookup(TaskID) ->
    gproc:lookup_local_name(TaskID).

-spec kill(task_id()) -> ok | {error, noproc}.

kill(TaskID) ->
    case lookup(TaskID) of
        undefined ->
            {error, noproc};
        Pid ->
            true = exit(Pid, kill),
            ok
    end.

-spec finish(task_id(), module(), Result :: any()) -> {ok, pid(), Result :: any()} | {error, any()}.

finish(TaskID, Module, Result) ->
    supervisor:start_child(?MODULE, [finish, TaskID, Module, Result]).

%%

-spec claim_id(task_id()) -> ok | {error, running}.

claim_id(undefined) ->
    ok;

claim_id(TaskID) ->
    try gproc:add_local_name(TaskID), ok catch
        error:badarg ->
            case lookup(TaskID) of
                Self when Self =:= self() ->
                    ok;
                _Pid ->
                    {error, running}
            end
    end.

%%

init([]) ->
    {ok, {
        {simple_one_for_one, 600, 30}, [
            {task, {?MODULE, start_task, []}, temporary, 5000, worker, []}
        ]
    }}.

%%

-define (is_ok(T), (T =:= ok orelse element(1, T) =:= ok)).
-define (is_error(T), (element(1, T) =:= error)).

start_task(invoke, Module, Options) ->
    proc_lib:start_link(?MODULE, init_task, [self(), Module, Options]).

start_task(finish, TaskID, Module, Result) ->
    proc_lib:start_link(?MODULE, init_finish_task, [self(), TaskID, Module, Result]).

init_task(Parent, Module, Options) ->
    io:format(user, "~nGOT HERE ~p~n", [{Parent, Module, Options}]),
    lager:info("task started up"),
    try Module:task_init(Options) of
        Ok when ?is_ok(Ok) ->
            finish_init_task(Ok, Parent, Module);
        Error when ?is_error(Error) ->
            lager:warning("task init failed: ~p", [Error]),
            init_done(Parent, Error)
    catch
        T:Reason ->
            _ = taskman_log:report("task init", T, Reason, erlang:get_stacktrace()),
            init_done(Parent, {error, Reason})
    end.

init_finish_task(Parent, TaskID, Module, Result) ->
    ok = claim_task_id(TaskID, Parent),
    lager:info("task restarted just to finish"),
    _ = init_done(Parent, {ok, self(), Result}),
    finish_task(TaskID, Result, Module).

claim_task_id(UniqueID, Parent) ->
    lager:info("claiming another id: ~s", [taskman_utils:format_task_id(UniqueID)]),
    case claim_id(UniqueID) of
        ok ->
            ok;
        {error, running} ->
            lager:warning("task seems to be already running"),
            init_done(Parent, {error, running}),
            exit(shutdown)
    end.

init_done(Parent, Result) ->
    proc_lib:init_ack(Parent, Result).

finish_init_task({ok, TaskID, Result, State}, Parent, Module) ->
    finish_init_task(TaskID, Result, State, infinity, Parent, Module);

finish_init_task({ok, TaskID, Result, State, Timeout}, Parent, Module) ->
    finish_init_task(TaskID, Result, State, Timeout, Parent, Module).

finish_init_task(TaskID, Result, State, Timeout, Parent, Module) ->
    _ = claim_task_id(TaskID, Parent),
    TimerRef = finish_after(TaskID, Module, Timeout),
    _ = init_done(Parent, {ok, self(), Result}),
    perform_task(TaskID, State, TimerRef, Module).

perform_task(TaskID, State, TimerRef, Module) ->
    Result = try case Module:task_perform(TaskID, State) of
        R when ?is_ok(R) orelse ?is_error(R) ->
            R
    end catch
        Type:Reason ->
            _ = taskman_log:report("task", Type, Reason, erlang:get_stacktrace()),
            {error, Reason}
    end,
    before_finish_task(TaskID, Result, TimerRef, Module).

before_finish_task(TaskID, Result, TimerRef, Module) ->
    ok = cancel_finish(TimerRef),
    _ = finish_task(TaskID, Result, Module),
    exit_task(Result).

finish_task(TaskID, Result, Module) ->
    ok = log_task_result(Result),
    try Module:task_finish(TaskID, Result) catch
        Type:Reason ->
            taskman_log:report("task result handler", Type, Reason, erlang:get_stacktrace())
    end.

log_task_result(Ok) when ?is_ok(Ok) ->
    lager:info("task successfully finished: ~p", [Ok]);

log_task_result(Error) ->
    taskman_log:report("task finished with", Error).

exit_task(Result) ->
    exit({shutdown, Result}).

%%

finish_after(TaskID, Module, Timeout) ->
    %% Timeout in seconds (!)
    taskman_task_killer:finish_after(taskman_task_killer, TaskID, Module, yield_delay(Timeout)).

cancel_finish(TimerRef) ->
    taskman_task_killer:cancel(taskman_task_killer, TimerRef).

yield_delay(Timeout) ->
    %% TODO
    %% I'm almost sure that hard ttl must be a bit longer that soft one
    %% Ha! It's the other way around, soft timeout a bit shorter than hard one
    Timeout.
