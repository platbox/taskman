%%%

-module(taskman_tests).

-include_lib("eunit/include/eunit.hrl").

-export([task_init/1]).
-export([task_perform/2]).
-export([task_finish/2]).

%%

taskman_test_() ->
    {setup,
        spawn,
        fun() ->
            _ = process_flag(trap_exit, true),
            Apps = start_application(gproc) ++ start_application(lager),
            _ = taskman_sup:start_link(options()), %%Don't it to exit this process, will die after the test
            Apps
        end,
        fun(Apps) ->
            application_stop(Apps)
        end,
        fun(_) ->
            [
                {"sync init + result" , ?_test(sync_init())      },
                {"init with same id"  , ?_test(same_id_init())   },
                {"exclusiveness"      , ?_test(exclusive_init()) },
                {"hard time limit"    , ?_test(hard_time_limit())},
                {"unexpected exit"    , ?_test(unexpected_exit())}
            ]
        end
    }.

%%

-define(TIMEOUT, 1).

sync_init() ->
    T0 = ts(),
    {ok, Pid, InitResult} = taskman:invoke(?MODULE, {sync_init, 42, self()}),
    T1 = ts(),
    TaskResult = receive {result, R} -> R end,
    _ = sleep(100),
    ?assertEqual(42, InitResult),
    ?assertEqual({ok, 42}, TaskResult),
    ?assertEqual(false, is_process_alive(Pid)),
    ?assert(T1 - T0 > 500).

same_id_init() ->
    ID = {same_id, 42, 0},
    {ok, _Pid, InitResult} = taskman:invoke(?MODULE, ID),
    ?assertEqual(ok, InitResult).

exclusive_init() ->
    {ok, _Pid1, _Result} = taskman:invoke(?MODULE, {exclusive_init, 31337, 0}),
    {error, running} = taskman:invoke(?MODULE, {exclusive_init, 31337, 0}),
    _ = sleep(500),
    ok.

hard_time_limit() ->
    {ok, Pid, _Result} = taskman:invoke(?MODULE, {hard_time_limit, 42, self()}),
    T0 = ts(),
    TaskResult = receive {result, R} -> R end,
    T1 = ts(),
    ?assertEqual({error, hard_time_limit_exceeded}, TaskResult),
    ?assertEqual(false, is_process_alive(Pid)),
    ?assert(T1 - T0 < ?TIMEOUT * 2 * 1000).

unexpected_exit() ->
    {ok, Pid, _Result} = taskman:invoke(?MODULE, {unexpected_exit, 42, self()}),
    _ = exit(Pid, kill),
    TaskResult = receive {result, R} -> R end,
    ?assertMatch({error, {unexpected_exit, _}}, TaskResult),
    ?assertEqual(false, is_process_alive(Pid)).

%%

task_init(ID = {sync_init, _, _}) ->
    {ok, ID, 42, begin sleep(500), 42 end};

task_init(ID = {hard_time_limit, _, _}) ->
    {ok, ID, ok, undefined, ?TIMEOUT};

task_init(ID) ->
    {ok, ID, ok, undefined}.

task_perform({exclusive_init, _, _}, State) ->
    _ = sleep(800),
    {ok, State};

task_perform({hard_time_limit, _, _}, State) ->
    _ = sleep(?TIMEOUT * 2 * 1000),
    {ok, State};

task_perform({unexpected_exit, _, _}, State) ->
    _ = sleep(1000),
    {ok, State};

task_perform(_ID, State) ->
    {ok, State}.

task_finish({_Case, _ID, Pid}, Result) when is_pid(Pid) ->
    Pid ! {result, Result};

task_finish(_ID, Result) ->
    Result.

%%

sleep(Ms) ->
    timer:sleep(Ms).

ts() ->
    ticks() div 1000.

options() ->
    [].

start_application(AppName) ->
    case application:start(AppName) of
        ok ->
            [AppName];
        {error, {already_started, AppName}} ->
            [];
        {error, {not_started, DepName}} ->
            start_application(DepName) ++ start_application(AppName);
        {error, Reason} ->
            exit(Reason)
    end.

-spec application_stop([Application :: atom()]) -> ok.

application_stop(Apps) ->
    _ = [application:stop(App) || App <- lists:reverse(Apps)],
    ok.

-spec ticks() -> pos_integer().

ticks() ->
    {Ms, S, Mcs} = os:timestamp(),
    (Ms * 1000000 + S) * 1000000 + Mcs.
