-module(guardian_test_ffi).
-export([extract_guardian/1, is_process_alive/1]).

%% Extract the guardian PID from a table handle.
%% Gleam compiles PSet(ets, dets, guardian, ..., skipped) to:
%%   {p_set, Ets, Dets, Guardian, WriteMode, EntryDecoder, DecodePolicy, Skipped}
extract_guardian({p_set, _Ets, _Dets, Guardian, _WM, _ED, _DP, _S}) -> Guardian;
extract_guardian({p_bag, _Ets, _Dets, Guardian, _WM, _ED, _DP, _S}) -> Guardian;
extract_guardian({p_duplicate_bag, _Ets, _Dets, Guardian, _WM, _ED, _DP, _S}) -> Guardian.

is_process_alive(Pid) -> erlang:is_process_alive(Pid).
