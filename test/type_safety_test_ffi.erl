-module(type_safety_test_ffi).
-export([write_raw_dets/3, read_raw_dets/2, insert_raw_dets/2]).

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

%% Read a closed fixture without decoding or truncating any stored term.
%% Read-only access must not create or repair the fixture.
read_raw_dets(Path, Type) ->
    DetsName = {shelf_raw_fixture, make_ref()},
    case dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {access, read},
            {repair, false}
        ]) of
        {ok, Dets} ->
            try
                case dets:foldl(fun(Entry, Acc) -> [Entry | Acc] end, [], Dets) of
                    {error, _} = Error ->
                        normalize_result(Error);
                    Entries ->
                        case normalize_result(dets:close(Dets)) of
                            {ok, nil} -> {ok, Entries};
                            {error, _} = Error -> Error
                        end
                end
            after
                dets:close(Dets)
            end;
        {error, _} = Error ->
            normalize_result(Error)
    end.

%% Corrupt only native DETS, leaving live ETS unchanged for reload tests.
%% Use the actual opaque handle's DETS identity, not a path registry lookup.
insert_raw_dets({Kind, _Ets, Dets, _Guardian, _WriteMode, _Decoder}, Entry)
        when Kind =:= persistent_set;
             Kind =:= persistent_bag;
             Kind =:= persistent_duplicate_bag ->
    ok = dets:insert(Dets, Entry),
    nil.

normalize_result(ok) -> {ok, nil};
normalize_result({error, Reason}) ->
    {error, {raw_dets_error,
        unicode:characters_to_binary(io_lib:format("~p", [Reason]))}}.
