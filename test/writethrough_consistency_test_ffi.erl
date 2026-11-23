-module(writethrough_consistency_test_ffi).
-export([close_dets_by_path/1]).

%% Close the DETS table by looking up its name from the shelf registry.
%% Resolve filesystem aliases exactly as shelf does; a missing injection
%% target is a fixture failure, never a successful no-op.
close_dets_by_path(Path) ->
    Name = close_test_ffi:dets_reference_for_path(Path),
    ok = dets:close(Name),
    nil.
