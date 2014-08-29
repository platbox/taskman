%%%
%%% Taskman
%%% A killer process for tasks who know too much^W^W^W live for too damn long.

-module(taskman_task_killer).
-behaviour(gen_server).

%%
-export([start_link/1]).
-export([finish_after/4]).
-export([finish_after/5]).
-export([cancel/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%

-type server_ref() :: pid() | atom() | {global, term()}.

-spec start_link({local, atom()} | {global, term()}) -> {ok, pid()} | {error, any()}.

start_link(Name) ->
    gen_server:start_link(Name, ?MODULE, [], []).

-spec finish_after(server_ref(), taskman_task:task_id(), module(), timeout()) -> reference() | undefined.

finish_after(Ref, TaskID, Module, Timeout) ->
    finish_after(Ref, self(), TaskID, Module, Timeout).

-spec finish_after(server_ref(), pid(), taskman_task:task_id(), module(), timeout()) -> reference() | undefined.

finish_after(Ref, Pid, TaskID, Module, Timeout) when is_pid(Pid), Timeout =:= infinity orelse is_integer(Timeout), Timeout > 0 ->
    gen_server:call(Ref, {Pid, TaskID, Module, Timeout}).

-spec cancel(server_ref(), reference() | undefined) -> ok.

cancel(_Ref, undefined) ->
    ok;

cancel(_Ref, TimerRef) ->
    _ = erlang:cancel_timer(TimerRef),
    ok.

%%

init(_) ->
    {ok, []}.

handle_call({Pid, TaskID, Module, Timeout}, _From, State) ->
    TimerRef = schedule(TaskID, Module, Timeout),
    {reply, TimerRef, watch(Pid, TaskID, Module, State)};

handle_call(Call, _From, State) ->
    lager:error("bad call: ~p", [Call]),
    {noreply, State}.

handle_cast(Cast, State) ->
    lager:error("bad cast: ~p", [Cast]),
    {noreply, State}.

handle_info({kill_finish, TaskID, Module}, State) ->
    _ = kill_finish(TaskID, Module, hard_time_limit_exceeded),
    {noreply, stop_watch(TaskID, State)};

handle_info({'DOWN', MRef, process, _Pid, {shutdown, _}}, State) ->
    {noreply, stop_watch_monitor(MRef, State)};

handle_info({'DOWN', MRef, process, _Pid, Unexpected}, State) ->
    _ = finish(MRef, {unexpected_exit, Unexpected}, State),
    {noreply, stop_watch_monitor(MRef, State)};

handle_info(Info, State) ->
    lager:error("bad info: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, _Tx) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%

schedule(_TaskID, _Handler, infinity) ->
    undefined;

schedule(TaskID, Module, Timeout) ->
    erlang:send_after(Timeout * 1000, self(), {kill_finish, TaskID, Module}).

kill_finish(TaskID, Module, Reason) ->
    kill_finish_task(TaskID, Module, {error, Reason}).

finish(MRef, Reason, WatchList) ->
    with_watchlist(MRef, 1, WatchList, fun ({_, TaskID, Module}, _) ->
        finish_task(TaskID, Module, {error, Reason})
    end).

watch(Pid, TaskID, Module, WatchList) ->
    MRef = erlang:monitor(process, Pid),
    [{MRef, TaskID, Module} | WatchList].

stop_watch(TaskID, WatchList) ->
    with_watchlist(TaskID, 2, WatchList, fun ({MRef, _, _}, WL) -> stop_watch_monitor(MRef, WL) end).

stop_watch_monitor(MRef, WatchList) ->
    _ = erlang:demonitor(MRef, [flush]),
    lists:keydelete(MRef, 1, WatchList).

with_watchlist(Key, N, WatchList, Fun) ->
    case lists:keyfind(Key, N, WatchList) of
        Record when is_tuple(Record) ->
            Fun(Record, WatchList);
        _ ->
            WatchList
    end.

kill_finish_task(TaskID, Module, Result) ->
    case taskman:kill(TaskID) of
        ok ->
            lager:warning("killed forcefully task [~s]", [format_id(TaskID)]),
            finish_task(TaskID, Module, Result);
        Error ->
            lager:error("failed to kill task [~s]: ~p", [format_id(TaskID), Error])
    end.

finish_task(TaskID, Module, Result) ->
    case taskman:finish(TaskID, Module, Result) of
        {ok, _Pid, _Result} ->
            lager:warning("finished forcefully task [~s]", [format_id(TaskID)]);
        Error ->
            lager:error("failed to finish task [~s]: ~p", [format_id(TaskID), Error])
    end.

format_id(TaskID) ->
    taskman_utils:format_task_id(TaskID).
