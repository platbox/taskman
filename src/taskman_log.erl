%%
%% Taskman
%% Simplified error reporting

-module(taskman_log).

%%

-export([report/2]).
-export([report/4]).

%%

-spec report(iodata(), any()) -> ok.

report(Pre, Error) ->
    lager:warning("~s error: ~p", [Pre, Error]).

-spec report(iodata(), throw | error | exit, any(), [erlang:stack_item()]) -> ok.

report(Pre, throw, Error, _Stacktrace) ->
    report(Pre, Error);

report(Pre, Type, Error, Stacktrace) ->
    lager:error("~s unexpected ~p:~p at --> ~p", [Pre, Type, Error, Stacktrace]).
