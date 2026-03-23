-module(shelf_ffi).
-export([
    open_no_load/3,
    close/2, cleanup/2,
    insert/3, insert_list/3, insert_new/3,
    lookup_set/2, lookup_bag/2, member/2,
    delete_key/2, delete_object/3, delete_all/1,
    to_list/1, fold/3, size/1,
    save/2, sync_dets/1,
    update_counter/3,
    dets_to_list/1,
    dets_fold_into_ets_strict/3, dets_fold_into_ets_lenient/3,
    dets_insert/2, dets_insert_list/2,
    dets_delete_key/2, dets_delete_object/3, dets_delete_all/1,
    validate_path/2
]).

%% ── DETS atom registry ──────────────────────────────────────────────────
%% DETS requires atom names. To avoid unbounded atom creation from
%% user-provided paths, we maintain a registry ETS table that maps
%% path binaries to deterministic atoms from a bounded pool.

-define(REGISTRY, shelf_dets_registry).
-define(POOL_SIZE, 65536).

ensure_registry() ->
    case ets:whereis(?REGISTRY) of
        undefined ->
            try
                ets:new(?REGISTRY, [set, public, named_table, {keypos, 1}]),
                ok
            catch
                _:badarg ->
                    %% Another process created it between our check and create
                    ok
            end;
        _ ->
            ok
    end.

%% Map a path binary to a bounded atom. Uses erlang:phash2 to hash
%% the path into a fixed pool of atoms (shelf_dets_0 .. shelf_dets_N).
%% Collisions are handled by appending a counter suffix.
path_to_dets_name(Path) ->
    ensure_registry(),
    case ets:lookup(?REGISTRY, Path) of
        [{Path, Name}] ->
            Name;
        [] ->
            Hash = erlang:phash2(Path, ?POOL_SIZE),
            Name = find_available_name(Path, Hash, 0),
            %% Use insert_new to handle races — if another process
            %% registered this path first, use their name.
            case ets:insert_new(?REGISTRY, {Path, Name}) of
                true -> Name;
                false ->
                    [{Path, ExistingName}] = ets:lookup(?REGISTRY, Path),
                    ExistingName
            end
    end.

find_available_name(Path, Hash, Attempt) ->
    Candidate = list_to_atom("shelf_dets_" ++ integer_to_list(Hash) ++ "_" ++ integer_to_list(Attempt)),
    %% Check if this atom is already used by a different path
    case ets:match_object(?REGISTRY, {'_', Candidate}) of
        [] -> Candidate;
        [{Path, Candidate}] -> Candidate;  %% Same path, reuse
        _ -> find_available_name(Path, Hash, Attempt + 1)  %% Collision, try next
    end.

%% Remove a path from the registry (called on close).
unregister_dets_name(Path) ->
    ensure_registry(),
    ets:delete(?REGISTRY, Path),
    ok.

%% ── Open (no load) ──────────────────────────────────────────────────────
%% Creates an ETS table + opens a DETS file but does NOT load DETS into ETS.
%% Used by the validated loading path where Gleam decodes entries before insertion.

open_no_load(Name, Path, TypeBin) ->
    Type = binary_to_atom(TypeBin, utf8),
    DetsName = path_to_dets_name(Path),
    try
        {ok, Dets} = dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {repair, true}
        ]),
        try
            Ets = ets:new(binary_to_atom(Name, utf8), [Type, protected, {keypos, 1}]),
            {ok, {Ets, Dets}}
        catch
            _:badarg ->
                _ = dets:close(Dets),
                unregister_dets_name(Path),
                {error, {erlang_error, <<"Failed to create table">>}}
        end
    catch
        _:{badmatch, {error, Reason}} ->
            unregister_dets_name(Path),
            {error, translate_error(Reason)};
        _:Reason ->
            unregister_dets_name(Path),
            {error, translate_error(Reason)}
    end.

%% ── DETS to list ───────────────────────────────────────────────────────
%% Returns all entries from a DETS table as a list of raw Erlang terms.

dets_to_list(Dets) ->
    try
        Result = dets:foldl(fun(Entry, Acc) -> [Entry | Acc] end, [], Dets),
        case Result of
            {error, Reason} -> {error, translate_error(Reason)};
            _ when is_list(Result) -> {ok, Result}
        end
    catch
        _:CatchReason -> {error, translate_error(CatchReason)}
    end.

%% ── Streaming DETS → ETS loaders ────────────────────────────────────────
%% Validate and insert entries one at a time using dets:foldl, avoiding
%% materializing the entire DETS contents into a Gleam list.

%% Strict mode: abort on first decode failure.
%% DecoderFun takes a raw entry and returns {ok, Pair} or {error, Errors}.
dets_fold_into_ets_strict(Dets, Ets, DecoderFun) ->
    try
        Result = dets:foldl(
            fun(Entry, Acc) ->
                case Acc of
                    {error, _} -> Acc;
                    ok ->
                        case DecoderFun(Entry) of
                            {ok, Pair} ->
                                ets:insert(Ets, Pair),
                                ok;
                            {error, Errors} ->
                                {error, {type_mismatch, Errors}}
                        end
                end
            end,
            ok,
            Dets
        ),
        case Result of
            ok -> {ok, nil};
            {error, {type_mismatch, Errors}} -> {error, {type_mismatch, Errors}};
            {error, Reason} -> {error, translate_error(Reason)}
        end
    catch
        _:CatchReason -> {error, translate_error(CatchReason)}
    end.

%% Lenient mode: skip entries that fail to decode.
dets_fold_into_ets_lenient(Dets, Ets, DecoderFun) ->
    try
        Result = dets:foldl(
            fun(Entry, ok) ->
                case DecoderFun(Entry) of
                    {ok, Pair} ->
                        ets:insert(Ets, Pair),
                        ok;
                    {error, _} ->
                        ok
                end
            end,
            ok,
            Dets
        ),
        case Result of
            ok -> {ok, nil};
            {error, Reason} -> {error, translate_error(Reason)}
        end
    catch
        _:CatchReason -> {error, translate_error(CatchReason)}
    end.

%% ── Cleanup ─────────────────────────────────────────────────────────────
%% Delete ETS table and close DETS without saving. Used on validation failure.

cleanup(Ets, Dets) ->
    try
        Path = dets_to_path(Dets),
        _ = dets:close(Dets),
        _ = ets:delete(Ets),
        unregister_dets_name(Path),
        {ok, nil}
    catch
        _:_ -> {ok, nil}
    end.

%% ── Close ───────────────────────────────────────────────────────────────
%% Atomic save ETS→DETS via temp file, close DETS, delete ETS.

close(Ets, Dets) ->
    Path = try dets_to_path(Dets) catch _:_ -> undefined end,
    %% Use the atomic save, then close and clean up
    SaveResult = case Path of
        undefined -> ok;
        _ ->
            case (catch save(Ets, Dets)) of
                {ok, nil} -> ok;
                {error, Reason} -> {error, Reason};
                {'EXIT', Reason} -> {error, Reason}
            end
    end,
    _ = (catch dets:close(Dets)),
    _ = (catch ets:delete(Ets)),
    case Path of
        undefined -> ok;
        _ -> unregister_dets_name(Path)
    end,
    case SaveResult of
        ok -> {ok, nil};
        {error, Reason2} -> {error, translate_error(Reason2)};
        _ -> {ok, nil}
    end.

%% Get the file path from a DETS reference as a binary.
dets_to_path(Dets) ->
    case dets:info(Dets, filename) of
        undefined -> undefined;
        Filename -> list_to_binary(Filename)
    end.

%% ── Insert ──────────────────────────────────────────────────────────────

insert(Ets, _Dets, Object) ->
    try ets:insert(Ets, Object) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

insert_list(Ets, _Dets, Objects) ->
    try ets:insert(Ets, Objects) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

insert_new(Ets, _Dets, Object) ->
    %% _Dets is unused here — ETS insert_new only checks ETS.
    %% The Gleam caller handles DETS persistence for WriteThrough mode.
    try ets:insert_new(Ets, Object) of
        true -> {ok, nil};
        false -> {error, key_already_present}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Lookup ──────────────────────────────────────────────────────────────
%% Always reads from ETS (fast path).

lookup_set(Ets, Key) ->
    try ets:lookup(Ets, Key) of
        [] -> {error, not_found};
        [{_, Value} | _] -> {ok, Value}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

lookup_bag(Ets, Key) ->
    try ets:lookup(Ets, Key) of
        Results when is_list(Results) ->
            Values = [V || {_, V} <- Results],
            case Values of
                [] -> {error, not_found};
                _ -> {ok, Values}
            end
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

member(Ets, Key) ->
    try {ok, ets:member(Ets, Key)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Delete ──────────────────────────────────────────────────────────────

delete_key(Ets, Key) ->
    try ets:delete(Ets, Key) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

delete_object(Ets, Key, Value) ->
    try ets:delete_object(Ets, {Key, Value}) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

delete_all(Ets) ->
    try ets:delete_all_objects(Ets) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Query ───────────────────────────────────────────────────────────────

to_list(Ets) ->
    try {ok, ets:tab2list(Ets)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

fold(Ets, Fun, Acc0) ->
    try ets:foldl(Fun, Acc0, Ets) of
        Result -> {ok, Result}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

size(Ets) ->
    try
        case ets:info(Ets, size) of
            undefined -> {error, table_closed};
            Size -> {ok, Size}
        end
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Persistence ─────────────────────────────────────────────────────────

%% Atomic save: snapshot ETS to a temp DETS file, then rename over the original.
%% This prevents data loss if the process is killed mid-save.
save(Ets, Dets) ->
    try
        OrigPath = dets_to_path(Dets),
        case OrigPath of
            undefined ->
                {error, table_closed};
            _ ->
                TmpPath = <<OrigPath/binary, ".tmp">>,
                %% Get the table type from the original DETS
                Type = dets:info(Dets, type),
                safe_save_impl(Ets, Dets, OrigPath, TmpPath, Type)
        end
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

safe_save_impl(Ets, Dets, OrigPath, TmpPath, Type) ->
    TmpPathList = binary_to_list(TmpPath),
    OrigPathList = binary_to_list(OrigPath),
    TmpName = list_to_atom("shelf_tmp_" ++ integer_to_list(erlang:phash2({self(), OrigPath}))),
    try
        %% 1. Open temp DETS
        {ok, TmpDets} = dets:open_file(TmpName, [
            {file, TmpPathList},
            {type, Type},
            {repair, false}
        ]),
        %% 2. Snapshot ETS into temp DETS
        TmpDets = ets:to_dets(Ets, TmpDets),
        %% 3. Close temp (flushes to disk)
        ok = dets:close(TmpDets),
        %% 4. Close original DETS
        ok = dets:close(Dets),
        %% 5. Atomic rename (POSIX guarantees this is atomic)
        ok = file:rename(TmpPathList, OrigPathList),
        %% 6. Reopen DETS at original path with the same atom name
        DetsName = Dets,
        {ok, _} = dets:open_file(DetsName, [
            {file, OrigPathList},
            {type, Type},
            {repair, true}
        ]),
        {ok, nil}
    catch
        _:Error ->
            %% Clean up temp file on failure
            _ = (catch dets:close(TmpName)),
            _ = (catch file:delete(TmpPathList)),
            %% Try to reopen original if it was closed
            _ = (catch dets:open_file(Dets, [
                {file, OrigPathList},
                {type, Type},
                {repair, true}
            ])),
            {error, translate_error(Error)}
    end.

%% Flush DETS write buffer to OS.
sync_dets(Dets) ->
    try dets:sync(Dets) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Counters ────────────────────────────────────────────────────────────

update_counter(Ets, Key, Increment) ->
    try {ok, ets:update_counter(Ets, Key, Increment)}
    catch
        error:badarg ->
            case ets:lookup(Ets, Key) of
                [] -> {error, not_found};
                _ -> {error, {erlang_error, <<"update_counter failed: value is not an integer">>}}
            end;
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Targeted DETS operations (for WriteThrough mode) ────────────────────

dets_insert(Dets, Object) ->
    try dets:insert(Dets, Object) of
        ok -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_insert_list(Dets, Objects) ->
    try dets:insert(Dets, Objects) of
        ok -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_delete_key(Dets, Key) ->
    try dets:delete(Dets, Key) of
        ok -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_delete_object(Dets, Key, Value) ->
    try dets:delete_object(Dets, {Key, Value}) of
        ok -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_delete_all(Dets) ->
    try dets:delete_all_objects(Dets) of
        ok -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Error translation ──────────────────────────────────────────────────

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error(name_conflict) -> name_conflict;
translate_error(type_mismatch) -> type_mismatch;
translate_error({type_mismatch, Errors}) -> {type_mismatch, Errors};
translate_error({invalid_path, Msg}) -> {invalid_path, Msg};
%% NOTE: `badarg` from ETS can mean the table was deleted, the reference is
%% invalid, or the arguments are malformed. We map it to `table_closed` as
%% the most common case, but this may be imprecise for other `badarg` causes
%% (e.g., concurrent access violations, malformed objects).
translate_error(badarg) -> table_closed;
translate_error({file_error, _, enoent}) -> {file_error, <<"File not found">>};
translate_error({file_error, _, eacces}) -> {file_error, <<"Permission denied">>};
translate_error({file_error, _, enospc}) -> file_size_limit_exceeded;
translate_error({file_error, _, Reason}) ->
    {file_error, list_to_binary(io_lib:format("~p", [Reason]))};
translate_error({error, Reason}) -> translate_error(Reason);
translate_error(Reason) ->
    {erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.

%% ── Path validation ────────────────────────────────────────────────────

validate_path(Path, BaseDirectory) ->
    BaseAbs = filename:absname(binary_to_list(BaseDirectory)),
    Resolved = filename:absname(binary_to_list(Path), BaseAbs),
    %% Normalize by splitting and rejoining (resolves . and ..)
    Normalized = normalize_path(Resolved),
    NormalizedBase = normalize_path(BaseAbs),
    %% Ensure the resolved path starts with the base directory
    case lists:prefix(NormalizedBase, Normalized) of
        true ->
            {ok, list_to_binary(Normalized)};
        false ->
            {error, {invalid_path, <<"Path escapes base directory">>}}
    end.

normalize_path(Path) ->
    Parts = filename:split(Path),
    NormalizedParts = normalize_parts(Parts, []),
    filename:join(NormalizedParts).

normalize_parts([], Acc) ->
    lists:reverse(Acc);
normalize_parts(["." | Rest], Acc) ->
    normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], [_ | Acc]) ->
    normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], []) ->
    %% Already at root, ignore
    normalize_parts(Rest, []);
normalize_parts([Part | Rest], Acc) ->
    normalize_parts(Rest, [Part | Acc]).
