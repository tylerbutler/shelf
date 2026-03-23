-module(shelf_rescue_ffi).
-export([rescue/1]).

rescue(Fun) ->
    try
        {ok, Fun()}
    catch
        Class:Reason ->
            {error, unicode:characters_to_binary(io_lib:format("~p:~p", [Class, Reason]))}
    end.
