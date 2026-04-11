-module(guardian_test_ffi).
-export([extract_guardian/1, is_process_alive/1]).

%% Extract the guardian PID from a table handle.
%% Gleam compiles PSet(ets, dets, guardian, write_mode, entry_decoder) to:
%%   {p_set, Ets, Dets, Guardian, WriteMode, EntryDecoder}
extract_guardian({p_set, _Ets, _Dets, Guardian, _WM, _ED}) -> Guardian;
extract_guardian({p_bag, _Ets, _Dets, Guardian, _WM, _ED}) -> Guardian;
extract_guardian({p_duplicate_bag, _Ets, _Dets, Guardian, _WM, _ED}) -> Guardian.

is_process_alive(Pid) -> erlang:is_process_alive(Pid).
