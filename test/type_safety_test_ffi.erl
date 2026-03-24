-module(type_safety_test_ffi).
-export([write_raw_dets/3]).

%% Write raw entries to a DETS file, bypassing Gleam's type system.
%% Used by type safety tests to simulate data from a previous session
%% with different types.
write_raw_dets(Path, TypeBin, Entries) ->
    DetsName = binary_to_atom(Path, utf8),
    Type = binary_to_existing_atom(TypeBin, utf8),
    try
        {ok, Dets} = dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {repair, true}
        ]),
        lists:foreach(fun(Entry) -> dets:insert(Dets, Entry) end, Entries),
        ok = dets:close(Dets),
        {ok, nil}
    catch
        _:Reason ->
            {error, Reason}
    end.
