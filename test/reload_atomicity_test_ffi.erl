-module(reload_atomicity_test_ffi).
-export([write_raw_dets_entry/3]).

%% Write a raw entry directly into an open DETS table, bypassing shelf.
%% Used to inject invalid entries for testing strict decode failures.
write_raw_dets_entry(Path, Key, Value) ->
    Name = close_test_ffi:dets_reference_for_path(Path),
    ok = dets:insert(Name, {Key, Value}),
    nil.
