-module(guardian_test_ffi).
-export([extract_guardian/1, is_process_alive/1]).

%% Extract the guardian PID from a table handle.
%% Gleam compiles PersistentSet(ets, dets, guardian, write_mode, entry_decoder) to:
%%   {persistent_set, Ets, Dets, Guardian, WriteMode, EntryDecoder}
extract_guardian({persistent_set, _Ets, _Dets, Guardian, _WriteMode, _EntryDecoder}) -> Guardian;
extract_guardian({persistent_bag, _Ets, _Dets, Guardian, _WriteMode, _EntryDecoder}) -> Guardian;
extract_guardian({persistent_duplicate_bag, _Ets, _Dets, Guardian, _WriteMode, _EntryDecoder}) -> Guardian.

is_process_alive(Pid) -> erlang:is_process_alive(Pid).
