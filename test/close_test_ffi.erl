-module(close_test_ffi).
-export([close_dets_externally/1, force_cleanup/2]).

%% Close the DETS table by looking up its name from the shelf registry
%% using the normalized path. This simulates an external DETS failure.
close_dets_externally(Path) ->
    Resolved = filename:absname(binary_to_list(Path)),
    Normalized = list_to_binary(shelf_ffi:normalize_path(Resolved)),
    case ets:whereis(shelf_dets_registry) of
        undefined -> nil;
        _ ->
            case ets:lookup(shelf_dets_registry, Normalized) of
                [{Normalized, Name}] -> dets:close(Name);
                [] -> ok
            end
    end,
    nil.

%% Force cleanup of ETS + DETS + file after a test that left things open.
force_cleanup(Path, Name) ->
    close_dets_externally(Path),
    catch ets:delete(binary_to_atom(Name, utf8)),
    file:delete(Path),
    nil.
