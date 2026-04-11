-module(reload_atomicity_test_ffi).
-export([write_raw_dets_entry/3]).

%% Write a raw entry directly into an open DETS table, bypassing shelf.
%% Used to inject invalid entries for testing strict decode failures.
write_raw_dets_entry(Path, Key, Value) ->
    Resolved = filename:absname(binary_to_list(Path)),
    Normalized = list_to_binary(shelf_ffi:normalize_path(Resolved)),
    case ets:whereis(shelf_dets_registry) of
        undefined -> ok;
        _ ->
            case ets:lookup(shelf_dets_registry, Normalized) of
                [{Normalized, Name}] ->
                    dets:insert(Name, {Key, Value});
                [] ->
                    case ets:lookup(shelf_dets_registry, Path) of
                        [{Path, Name2}] ->
                            dets:insert(Name2, {Key, Value});
                        [] -> ok
                    end
            end
    end,
    nil.
