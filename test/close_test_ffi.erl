-module(close_test_ffi).
-export([close_dets_externally/1, force_cleanup/2]).

%% Close the DETS table by looking up its name from the shelf registry
%% using the normalized path. This simulates an external DETS failure.
close_dets_externally(Path) ->
    %% Normalize path the same way shelf does during open
    Resolved = filename:absname(binary_to_list(Path)),
    Normalized = list_to_binary(normalize_path(Resolved)),
    case ets:whereis(shelf_dets_registry) of
        undefined -> nil;
        _ ->
            case ets:lookup(shelf_dets_registry, Normalized) of
                [{Normalized, Name}] -> dets:close(Name);
                [] ->
                    %% Try the raw path too
                    case ets:lookup(shelf_dets_registry, Path) of
                        [{Path, Name2}] -> dets:close(Name2);
                        [] -> ok
                    end
            end
    end,
    nil.

normalize_path(Path) ->
    Parts = filename:split(Path),
    NormalizedParts = normalize_parts(Parts, []),
    filename:join(NormalizedParts).

normalize_parts([], Acc) -> lists:reverse(Acc);
normalize_parts(["." | Rest], Acc) -> normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], [_ | Acc]) -> normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], []) -> normalize_parts(Rest, []);
normalize_parts([Part | Rest], Acc) -> normalize_parts(Rest, [Part | Acc]).

%% Force cleanup of ETS + file after a test that left things open.
force_cleanup(Path, _Name) ->
    close_dets_externally(Path),
    file:delete(Path),
    nil.
