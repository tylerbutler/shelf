-module(writethrough_consistency_test_ffi).
-export([close_dets_by_path/1]).

%% Close the DETS table by looking up its name from the shelf registry.
%% Normalizes the path the same way shelf does during open.
close_dets_by_path(Path) ->
    Resolved = filename:absname(binary_to_list(Path)),
    Normalized = list_to_binary(shelf_ffi:normalize_path(Resolved)),
    case ets:whereis(shelf_dets_registry) of
        undefined -> nil;
        _ ->
            case ets:lookup(shelf_dets_registry, Normalized) of
                [{Normalized, Name}] -> dets:close(Name);
                [] ->
                    case ets:lookup(shelf_dets_registry, Path) of
                        [{Path, Name2}] -> dets:close(Name2);
                        [] -> ok
                    end
            end
    end,
    nil.
