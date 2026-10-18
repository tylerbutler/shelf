-module(type_safety_test_ffi).
-export([write_raw_dets/3]).

%% Write raw entries to a DETS file, bypassing Gleam's type system.
%% Used by type safety tests to simulate data from a previous session
%% with different types.
write_raw_dets(Path, Type, Entries) ->
    DetsName = {shelf_raw_fixture, make_ref()},
    case dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {repair, true}
        ]) of
        {ok, Dets} ->
            try
                InsertResult = dets:insert(Dets, Entries),
                CloseResult = dets:close(Dets),
                case InsertResult of
                    ok -> normalize_result(CloseResult);
                    {error, _} -> normalize_result(InsertResult)
                end
            after
                %% Also release the fixture on unexpected process errors.
                dets:close(Dets)
            end;
        {error, _} = Error ->
            normalize_result(Error)
    end.

normalize_result(ok) -> {ok, nil};
normalize_result({error, Reason}) ->
    {error, {raw_dets_error,
        unicode:characters_to_binary(io_lib:format("~p", [Reason]))}}.
