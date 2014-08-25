%%%
%%% Taskman
%%% Taskman utils

-module(taskman_utils).

-export([format_task_id/1]).

-spec format_task_id(any()) -> binary().

format_task_id(TaskID) ->
    try
        try_format_task_id(TaskID)
    catch
        _:_ ->
            iolist_to_binary(io_lib:format("~p", [TaskID]))
    end.

try_format_task_id(TaskID) when is_tuple(TaskID) ->
    try_format_task_id(tuple_to_list(TaskID));

try_format_task_id(TaskID) when is_list(TaskID) ->
    <<$:, Result/binary>> = << <<$:, (to_binary(E))/binary>> || E <- TaskID>>,
    Result;

try_format_task_id(TaskID) ->
    to_binary(TaskID).

-spec to_binary(iodata() | atom() | number()) -> binary().

to_binary(V) when is_binary(V)  -> V;
to_binary(V) when is_list(V)    -> iolist_to_binary(V);
to_binary(V) when is_atom(V)    -> atom_to_binary(V, utf8);
to_binary(V) when is_integer(V) -> integer_to_binary(V);
to_binary(V) when is_float(V)   -> float_to_binary(V).