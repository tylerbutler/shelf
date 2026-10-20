-module(shelf_ffi).
-include_lib("kernel/include/file.hrl").
-export([
    open_no_load/3,
    close/3, cleanup/3,
    insert/3, insert_list/3, insert_new/3,
    lookup_set/2, lookup_bag/2, member/2,
    delete_key/2, delete_object/3, delete_all/1,
    to_list/1, fold/3, size/1,
    save/2, sync_dets/1, sync_dets/2,
    update_counter/3,
    dets_fold_into_ets_strict/3,
    validate_owner/1,
    dets_insert/3, dets_insert_list/3,
    dets_delete_key/3, dets_delete_object/4, dets_delete_all/2,
    reload_atomic/3,
    validate_path/2,
    normalize_path/1
]).

%% ── DETS path reservations ──────────────────────────────────────────────
%% Each canonical path has one lifetime-exclusive reservation. Native DETS
%% accepts arbitrary terms as names: the reference prevents stale cleanup
%% from affecting a replacement, without allocating atoms from paths.
%%
%% The registry ETS table is owned by a dedicated long-lived process
%% (shelf_dets_registry_owner) so it survives the death of any individual
%% caller process.

-define(REGISTRY, shelf_dets_registry).

ensure_registry() ->
    case ets:whereis(?REGISTRY) of
        undefined -> start_registry_owner();
        _ -> ok
    end.

start_registry_owner() ->
    Pid = spawn(fun registry_loop/0),
    try register(shelf_dets_registry_owner, Pid) of
        true ->
            Pid ! {create_registry, self()},
            receive
                {registry_created, Pid} -> ok
            after 5000 ->
                error(registry_timeout)
            end
    catch
        error:badarg ->
            %% Another process won the race to register. Stop the orphan.
            Pid ! stop,
            wait_for_registry(20)
    end.

registry_loop() ->
    receive
        {create_registry, From} ->
            try
                ets:new(?REGISTRY, [set, public, named_table,
                                    {keypos, 1}, {read_concurrency, true}]),
                From ! {registry_created, self()}
            catch
                _:badarg ->
                    %% Table already exists (edge case), still ack.
                    From ! {registry_created, self()}
            end,
            registry_loop();
        stop ->
            ok;
        _ ->
            registry_loop()
    end.

wait_for_registry(0) ->
    error(registry_not_available);
wait_for_registry(N) ->
    case ets:whereis(?REGISTRY) of
        undefined ->
            timer:sleep(50),
            wait_for_registry(N - 1);
        _ ->
            ok
    end.

reserve_path(Path, Name) ->
    case ets:insert_new(?REGISTRY, {Path, Name}) of
        true -> ok;
        false ->
            case ets:lookup(?REGISTRY, Path) of
                [{Path, {shelf_dets, Owner, _, _} = Previous}] ->
                    %% Native DETS closes asynchronously on owner death.
                    %% Do not reclaim while its file server can still write.
                    case not is_process_alive(Owner) of
                        true ->
                            release_dead_reservation(Path, Previous),
                            reserve_path(Path, Name);
                        false -> {error, name_conflict}
                    end;
                [] -> reserve_path(Path, Name)
            end
    end.

%% Delete only the matching lifetime's reservation. Explicit close/cleanup
%% first validate the original ETS handle; owner-death cleanup waits for
%% native DETS close. A failed save can fail to reopen DETS, losing its filename
%% while its name remains reserved in the registry. Recover only a unique
%% mapping: a name-wide match_delete could erase another path's reservation.
unregister_dets_name(undefined, Dets) ->
    ensure_registry(),
    case ets:match_object(?REGISTRY, {'_', Dets}) of
        [{Path, Dets}] -> unregister_dets_name(Path, Dets);
        [] -> ok;
        [_, _ | _] -> ok  %% Ambiguous mapping: do not remove other paths.
    end;
unregister_dets_name(Path, Dets) ->
    ensure_registry(),
    %% Do not erase a replacement mapping with a different DETS name.
    ets:delete_object(?REGISTRY, {Path, Dets}),
    ok.

%% ── Open (no load) ──────────────────────────────────────────────────────
%% Creates an ETS table + opens a DETS file but does NOT load DETS into ETS.
%% Used by the validated loading path where Gleam decodes entries before insertion.

open_no_load(_Name, Path, Type) ->
    ensure_registry(),
    Owner = self(),
    Lifetime = make_ref(),
    %% Reserve inside the guardian, after monitoring the owner. There is
    %% then no owner-death gap between reservation and guardian creation.
    {Guardian, Monitor} = spawn_monitor(fun() ->
        Name = {shelf_dets, Owner, Lifetime, self()},
        OwnerMonitor = monitor(process, Owner),
        case reserve_path(Path, Name) of
            ok ->
                Owner ! {Name, reserved},
                guard_reservation(Owner, OwnerMonitor, Path, Name, none);
            {error, _} = Error -> Owner ! {Name, Error}
        end
    end),
    Name = {shelf_dets, Owner, Lifetime, Guardian},
    receive
        {Name, reserved} ->
            demonitor(Monitor, [flush]),
            open_reserved(Path, Type, Name, Guardian);
        {Name, {error, _} = Error} ->
            demonitor(Monitor, [flush]),
            Error;
        {'DOWN', Monitor, process, Guardian, Reason} ->
            exit({shelf_guardian_failed, Reason})
    end.

open_reserved(Path, Type, Name, Guardian) ->
    %% OTP 27 DETS requires a charlist filename (file:* accepts binaries).
    case dets:open_file(Name, [
        {file, unicode:characters_to_list(Path)}, {type, Type}, {repair, true}
    ]) of
        {ok, Dets} ->
            %% An unexpected ETS creation failure remains a process failure;
            %% the guardian and native DETS still handle owner death.
            Ets = ets:new(shelf_ets, [Type, protected, {keypos, 1}, {read_concurrency, true}]),
            {ok, {Ets, Dets, Guardian}};
        {error, Reason} ->
            unregister_dets_name(Path, Name),
            stop_guardian(Guardian),
            {error, translate_error(Reason)}
    end.

guard_reservation(Owner, Monitor, Path, Name, Snapshot) ->
    receive
        {acquire_snapshot, Owner, Request} when Snapshot =:= none ->
            %% The guardian acquires the directory itself: owner death at
            %% any point (even before the reply) cannot leave it untracked.
            case make_save_directory(Path, 100) of
                {ok, Directory} ->
                    Temporary = {shelf_tmp, make_ref()},
                    Acquired = {Directory, Temporary},
                    Owner ! {Request, {ok, Acquired}},
                    guard_reservation(Owner, Monitor, Path, Name, Acquired);
                {error, _} = Error ->
                    Owner ! {Request, Error},
                    guard_reservation(Owner, Monitor, Path, Name, none)
            end;
        {{finish_snapshot, Temporary}, Owner, Request}
            when Snapshot =/= none, element(2, Snapshot) =:= Temporary ->
            %% The caller's after block runs after closing temporary DETS.
            %% Cleanup and forgetting happen in this one process, avoiding
            %% a second deletion by a delayed owner-DOWN handler.
            cleanup_snapshot_directory(Snapshot),
            Owner ! {Request, ok},
            guard_reservation(Owner, Monitor, Path, Name, none);
        {'DOWN', Monitor, process, Owner, _} ->
            cleanup_dead_snapshot(Snapshot),
            %% This close also serializes behind any pending native open.
            %% The guardian is not a DETS opening user: close alone cannot
            %% release the dead owner's handle. Wait for its file server.
            release_dead_reservation(Path, Name);
        stop ->
            demonitor(Monitor, [flush]),
            ok
    end.

release_dead_reservation(Path, Name) ->
    await_dead_dets_close(Name),
    unregister_dets_name(Path, Name).

await_dead_dets_close(Name) ->
    %% Capture the PID before close: DETS removes its registry entry before
    %% its asynchronous file close completes. close/1 serializes behind
    %% pending opens/closes even when info/2 already returns undefined.
    ServerBefore = dets:info(Name, owner),
    _ = dets:close(Name),
    %% A pending open may only have published its server during the close
    %% barrier. Conversely, an owner-exit close may already have removed it.
    Server = case ServerBefore of
        undefined -> dets:info(Name, owner);
        _ -> ServerBefore
    end,
    case Server of
        undefined -> ok;
        Pid ->
            Monitor = monitor(process, Pid),
            receive
                {'DOWN', Monitor, process, Pid, _} -> ok
            end
    end,
    %% Cover a native close that removed its registry entry between the
    %% lookups above: the file may still be flushing in a pending request.
    _ = dets:close(Name),
    ok.

cleanup_dead_snapshot(none) -> ok;
cleanup_dead_snapshot({_Directory, Temporary} = Snapshot) ->
    %% Native DETS, not the guardian, owns the dead caller's open count.
    %% Wait for pending temp opens/closes and the file server before unlink.
    await_dead_dets_close(Temporary),
    cleanup_snapshot_directory(Snapshot).

cleanup_snapshot_directory({Directory, _Temporary}) ->
    _ = file:delete(filename:join(Directory, <<"snapshot.dets">>)),
    _ = file:del_dir(Directory),
    ok.

snapshot_request(Guardian, Operation) ->
    Request = monitor(process, Guardian),
    Guardian ! {Operation, self(), Request},
    %% Like native DETS I/O, acquisition is synchronous: do not time out
    %% and abandon a directory while the guardian is still acquiring it.
    receive
        {Request, Reply} ->
            demonitor(Request, [flush]),
            Reply;
        {'DOWN', Request, process, Guardian, Reason} ->
            exit({shelf_guardian_failed, Reason})
    end.

%% ── Streaming DETS → ETS loaders ────────────────────────────────────────
%% Validate and insert entries one at a time using dets:foldl, avoiding
%% materializing the entire DETS contents into a Gleam list.
%% To avoid row-by-row ETS boundary crossing, we batch entries.

-define(LOAD_BATCH_SIZE, 5000).

flush_batch(_Ets, []) -> ok;
%% Reverse restores DETS traversal order before bulk insert.
%% ETS bag tables preserve insertion order, so this matters for
%% callers that expect values under a key to stay in DETS order.
flush_batch(Ets, Batch) -> ets:insert(Ets, lists:reverse(Batch)).

%% Abort on first decode failure using throw.
%% DecoderFun takes a raw entry and returns {ok, Pair} or {error, Errors}.
dets_fold_into_ets_strict(Dets, Ets, DecoderFun) ->
    try
        Result = dets:foldl(
            fun(Entry, {Count, Batch}) ->
                case DecoderFun(Entry) of
                    {ok, Pair} ->
                        NewBatch = [Pair | Batch],
                        case Count + 1 of
                            ?LOAD_BATCH_SIZE ->
                                flush_batch(Ets, NewBatch),
                                {0, []};
                            NewCount ->
                                {NewCount, NewBatch}
                        end;
                    {error, Errors} ->
                        throw({type_mismatch, Errors})
                end
            end,
            {0, []},
            Dets
        ),
        case Result of
            {error, Reason} -> {error, translate_error(Reason)};
            {_, FinalBatch} ->
                flush_batch(Ets, FinalBatch),
                {ok, nil}
        end
    catch
        throw:{type_mismatch, Errors} -> {error, {type_mismatch, Errors}};
        _:CatchReason -> {error, translate_error(CatchReason)}
    end.

%% ── Validated reload ────────────────────────────────────────────────────
%% Load DETS entries into a scratch ETS table first.  Only replace the
%% live table contents after the full validation succeeds; validation failure
%% leaves the live ETS untouched. Replacement is clear-then-fill, not a
%% transaction: concurrent readers can see an empty or partially filled table.

reload_atomic(Ets, Dets, DecoderFun) ->
    case check_owner(Ets) of
        {error, _} = Err -> Err;
        ok -> reload_atomic_validated(Ets, Dets, DecoderFun)
    end.

reload_atomic_validated(Ets, Dets, DecoderFun) ->
    Type = ets:info(Ets, type),
    Scratch = ets:new(shelf_reload_scratch, [Type, protected]),
    try
        case dets_fold_into_ets_strict(Dets, Scratch, DecoderFun) of
            {ok, nil} ->
                ets:delete_all_objects(Ets),
                copy_reload_table(Ets, Scratch, Type),
                ets:delete(Scratch),
                {ok, nil};
            {error, _} = Err ->
                ets:delete(Scratch),
                Err
        end
    catch
        _:Reason ->
            (catch ets:delete(Scratch)),
            {error, translate_error(Reason)}
    end.

%% Scratch is owned by this process and is not modified during traversal,
%% so neither selection continuations nor key traversal need safe_fixtable.
copy_reload_table(Ets, Scratch, set) ->
    copy_reload_set(Ets, ets:select(Scratch, [{'_', [], ['$_']}], ?LOAD_BATCH_SIZE));
copy_reload_table(Ets, Scratch, Type) when Type =:= bag; Type =:= duplicate_bag ->
    copy_reload_bag(Ets, Scratch, ets:first(Scratch)).

copy_reload_set(_Ets, '$end_of_table') ->
    ok;
copy_reload_set(Ets, {Batch, Continuation}) ->
    ets:insert(Ets, Batch),
    copy_reload_set(Ets, ets:select(Continuation)).

%% Chunked select does not preserve bag lookup order across chunk boundaries.
%% Copy each key's objects in lookup order instead, retaining duplicate_bag
%% multiplicity. Peak transfer memory depends on the largest key group, which
%% can be the entire table; bags do not have a fixed LOAD_BATCH_SIZE bound.
copy_reload_bag(Ets, Scratch, '$end_of_table') ->
    %% first/next use this atom as a sentinel, but the old tab2list transfer
    %% also handled it as a stored key. Since live ETS starts empty, membership
    %% there distinguishes an unvisited key from the actual end of traversal.
    case ets:member(Scratch, '$end_of_table') andalso
         not ets:member(Ets, '$end_of_table') of
        true -> copy_reload_bag_key(Ets, Scratch, '$end_of_table');
        false -> ok
    end;
copy_reload_bag(Ets, Scratch, Key) ->
    copy_reload_bag_key(Ets, Scratch, Key).

copy_reload_bag_key(Ets, Scratch, Key) ->
    ets:insert(Ets, ets:lookup(Scratch, Key)),
    copy_reload_bag(Ets, Scratch, ets:next(Scratch, Key)).

%% ── Guardian ────────────────────────────────────────────────────────────

stop_guardian(Guardian) ->
    Guardian ! stop,
    ok.

%% ── Cleanup ─────────────────────────────────────────────────────────────
%% Delete ETS table and close DETS without saving. Used on validation failure
%% and when a with_table scope cannot retain a retryable close failure.

cleanup(Ets, Dets, Guardian) ->
    %% The ETS reference identifies this handle's lifetime. Never
    %% look up its path or close it after the original ETS handle is gone.
    case check_owner(Ets) of
        {error, _} = Error -> Error;
        ok -> finalize_close(Ets, Dets, Guardian, dets_to_path(Dets))
    end.

%% ── Close ───────────────────────────────────────────────────────────────
%% Atomic save ETS→DETS via temp file, close DETS, delete ETS.
%% On save failure, everything is left intact so the caller can retry.

close(Ets, Dets, Guardian) ->
    case check_owner(Ets) of
        {error, _} = Err -> Err;
        ok ->
            Path = dets_to_path(Dets),
            case attempt_close_save(Ets, Dets) of
                ok ->
                    finalize_close(Ets, Dets, Guardian, Path);
                {error, Reason} = Err ->
                    case preserve_table_after_close_error(Path, Reason) of
                        true ->
                            Err;
                        false ->
                            teardown_resources(Ets, Dets, Guardian, Path),
                            Err
                    end
            end
    end.

attempt_close_save(Ets, Dets) ->
    try save(Ets, Dets) of
        {ok, nil} -> ok;
        {error, Reason} -> {error, Reason}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

preserve_table_after_close_error(_Path, table_closed) -> false;
preserve_table_after_close_error(undefined, _Reason) -> false;
preserve_table_after_close_error(_Path, _Reason) -> true.

finalize_close(Ets, Dets, Guardian, Path) ->
    CloseResult = close_dets_handle(Dets),
    _ = (catch ets:delete(Ets)),
    unregister_dets_name(Path, Dets),
    stop_guardian(Guardian),
    case CloseResult of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

teardown_resources(Ets, Dets, Guardian, Path) ->
    _ = close_dets_handle(Dets),
    _ = (catch ets:delete(Ets)),
    unregister_dets_name(Path, Dets),
    stop_guardian(Guardian),
    ok.

close_dets_handle(Dets) ->
    try dets:close(Dets) of
        ok -> ok;
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% Get the file path from a DETS reference as a binary.
dets_to_path(Dets) ->
    case dets:info(Dets, filename) of
        undefined -> undefined;
        Filename -> unicode:characters_to_binary(Filename)
    end.

%% ── Insert ──────────────────────────────────────────────────────────────

insert(Ets, _Dets, Object) ->
    try ets:insert(Ets, Object) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
    end.

insert_list(Ets, _Dets, Objects) ->
    try ets:insert(Ets, Objects) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
    end.

insert_new(Ets, _Dets, Object) ->
    %% _Dets is unused here — ETS insert_new only checks ETS.
    %% The Gleam caller handles DETS persistence for WriteThrough mode.
    try ets:insert_new(Ets, Object) of
        true -> {ok, nil};
        false -> {error, key_already_present}
    catch
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
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
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
    end.

delete_object(Ets, Key, Value) ->
    try ets:delete_object(Ets, {Key, Value}) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
    end.

delete_all(Ets) ->
    try ets:delete_all_objects(Ets) of
        true -> {ok, nil}
    catch
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
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

%% Check that the caller is the ETS table owner.
%% Returns ok | {error, not_owner | table_closed}.
check_owner(Ets) ->
    case ets:info(Ets, owner) of
        undefined -> {error, table_closed};
        Pid when Pid =:= self() -> ok;
        _ -> {error, not_owner}
    end.

validate_owner(Ets) ->
    case check_owner(Ets) of
        ok -> {ok, nil};
        {error, _} = Error -> Error
    end.

%% Atomic save: snapshot ETS to a temp DETS file, then rename over the original.
%% This prevents data loss if the process is killed mid-save.
save(Ets, {shelf_dets, _Owner, _Lifetime, Guardian} = Dets) ->
    case check_owner(Ets) of
        {error, _} = Err -> Err;
        ok ->
            try
                OrigPath = dets_to_path(Dets),
                case OrigPath of
                    undefined ->
                        {error, table_closed};
                    _ ->
                        Type = dets:info(Dets, type),
                        case snapshot_request(Guardian, acquire_snapshot) of
                            {ok, {Directory, Temporary}} ->
                                TmpPath = filename:join(Directory, <<"snapshot.dets">>),
                                try safe_save_impl(Ets, Dets, OrigPath, TmpPath, Type, Temporary)
                                after
                                    snapshot_request(Guardian, {finish_snapshot, Temporary})
                                end;
                            {error, TempReason} ->
                                %% Keep the save error's native failure detail,
                                %% as for a failed snapshot/open/rename below.
                                {error, translate_error({badmatch, {error, TempReason}})}
                        end
                end
            catch
                _:Reason -> {error, translate_error(Reason)}
            end
    end.

make_save_directory(_Path, 0) ->
    {error, {file_error, temp_directory, eexist}};
make_save_directory(Path, Attempts) ->
    Suffix = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Pid = list_to_binary(os:getpid()),
    Directory = filename:join(filename:dirname(Path),
        <<".shelf-save-", Pid/binary, "-", Suffix/binary>>),
    case file:make_dir(Directory) of
        ok ->
            case file:change_mode(Directory, 8#700) of
                ok -> {ok, Directory};
                {error, Reason} ->
                    _ = file:del_dir(Directory),
                    {error, {file_error, Directory, Reason}}
            end;
        {error, eexist} -> make_save_directory(Path, Attempts - 1);
        {error, Reason} -> {error, {file_error, Directory, Reason}}
    end.

safe_save_impl(Ets, Dets, OrigPath, TmpPath, Type, TmpName) ->
    try
        %% 1. Open temp DETS
        {ok, TmpDets} = dets:open_file(TmpName, [
            {file, unicode:characters_to_list(TmpPath)},
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
        ok = file:rename(TmpPath, OrigPath),
        %% 6. Reopen DETS using the same lifetime reservation
        DetsName = Dets,
        {ok, _} = dets:open_file(DetsName, [
            {file, unicode:characters_to_list(OrigPath)},
            {type, Type},
            {repair, true}
        ]),
        {ok, nil}
    catch
        _:Error ->
            %% Clean up temp file on failure
            _ = (catch dets:close(TmpName)),
            %% Try to reopen original if it was closed
            %% Opening an already-open DETS table again increments this
            %% caller's open count. A later cleanup would then leave DETS
            %% open, and a reopened table could read stale disk contents.
            case dets:info(Dets) of
                undefined ->
                    _ = (catch dets:open_file(Dets, [
                        {file, unicode:characters_to_list(OrigPath)},
                        {type, Type},
                        {repair, true}
                    ]));
                _ -> ok
            end,
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

%% Owner-guarded sync: only the ETS owner may flush DETS.
sync_dets(Ets, Dets) ->
    case check_owner(Ets) of
        {error, _} = Err -> Err;
        ok -> sync_dets(Dets)
    end.

%% ── Counters ────────────────────────────────────────────────────────────

update_counter(Ets, Key, Increment) ->
    try {ok, ets:update_counter(Ets, Key, Increment)}
    catch
        error:badarg ->
            case ets:info(Ets, owner) of
                undefined ->
                    {error, table_closed};
                OwnerPid when OwnerPid =:= self() ->
                    %% Owner, so badarg is a data problem
                    case ets:lookup(Ets, Key) of
                        [] -> {error, not_found};
                        _ -> {error, {erlang_error, <<"update_counter failed: value is not an integer">>}}
                    end;
                _OtherPid ->
                    {error, not_owner}
            end;
        _:Reason -> {error, classify_ets_error(Ets, Reason)}
    end.

%% ── Targeted DETS operations (for WriteThrough mode) ────────────────────

dets_insert(Ets, Dets, Object) ->
    case check_owner(Ets) of
        ok -> dets_insert_validated(Dets, Object);
        {error, _} = Error -> Error
    end.

dets_insert_validated(Dets, Object) ->
    try dets:insert(Dets, Object) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_insert_list(Ets, Dets, Objects) ->
    dets_insert(Ets, Dets, Objects).

dets_delete_key(Ets, Dets, Key) ->
    case check_owner(Ets) of
        ok -> dets_delete_key_validated(Dets, Key);
        {error, _} = Error -> Error
    end.

dets_delete_key_validated(Dets, Key) ->
    try dets:delete(Dets, Key) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_delete_object(Ets, Dets, Key, Value) ->
    case check_owner(Ets) of
        ok -> dets_delete_object_validated(Dets, Key, Value);
        {error, _} = Error -> Error
    end.

dets_delete_object_validated(Dets, Key, Value) ->
    try dets:delete_object(Dets, {Key, Value}) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

dets_delete_all(Ets, Dets) ->
    case check_owner(Ets) of
        ok -> dets_delete_all_validated(Dets);
        {error, _} = Error -> Error
    end.

dets_delete_all_validated(Dets) ->
    try dets:delete_all_objects(Dets) of
        ok -> {ok, nil};
        {error, Reason} -> {error, translate_error(Reason)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Error translation ──────────────────────────────────────────────────

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error(name_conflict) -> name_conflict;
translate_error(not_owner) -> not_owner;
translate_error(type_mismatch) -> type_mismatch;
translate_error({type_mismatch, Errors}) -> {type_mismatch, Errors};
translate_error({invalid_path, Msg}) -> {invalid_path, Msg};
translate_error(table_closed) -> table_closed;
translate_error(badarg) -> table_closed;
translate_error({file_error, _, enoent}) -> {file_error, <<"File not found">>};
translate_error({file_error, _, eacces}) -> {file_error, <<"Permission denied">>};
translate_error({file_error, _, enospc}) -> file_size_limit_exceeded;
translate_error({file_error, _, Reason}) ->
    {file_error, list_to_binary(io_lib:format("~p", [Reason]))};
translate_error({error, Reason}) -> translate_error(Reason);
translate_error(Reason) ->
    {erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.

%% Classify an ETS badarg error: is the table closed, or is the caller
%% not the owner?  For `protected` tables, writes from non-owners raise
%% badarg just like a deleted table does.
classify_ets_error(Ets, badarg) ->
    case ets:info(Ets, owner) of
        undefined ->
            %% Table doesn't exist — genuinely closed / deleted
            table_closed;
        OwnerPid when OwnerPid =:= self() ->
            %% We are the owner but still got badarg — bad arguments
            {erlang_error, <<"ETS badarg: invalid arguments">>};
        _OtherPid ->
            %% Table exists but we aren't the owner
            not_owner
    end;
classify_ets_error(_Ets, Reason) ->
    translate_error(Reason).

%% ── Path validation ────────────────────────────────────────────────────

validate_path(Path, BaseDirectory) ->
    case resolve_path(filename:absname(BaseDirectory)) of
        {ok, Base} ->
            case resolve_path(filename:absname(Path, Base)) of
                {ok, Resolved} ->
                    %% Component comparison handles root and sibling names.
                    case lists:prefix(filename:split(Base), filename:split(Resolved)) of
                        true ->
                            case unicode:characters_to_binary(Resolved) of
                                Canonical when is_binary(Canonical) -> {ok, Canonical};
                                _ -> {error, {invalid_path, <<"Path is not valid UTF-8">>}}
                            end;
                        false -> {error, {invalid_path, <<"Path escapes base directory">>}}
                    end;
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%% Resolve links before processing "..", including links at the leaf.
%% Missing components are allowed for paths that will be created later;
%% DETS open still requires existing parent directories. A bounded link
%% count rejects loops. This is not a sandbox against concurrent replacement.
resolve_path(Path) ->
    [Root | Parts] = filename:split(Path),
    resolve_parts(Parts, Root, 40).

resolve_parts([], Current, _LinksLeft) -> {ok, Current};
resolve_parts([<<".">> | Rest], Current, LinksLeft) ->
    resolve_parts(Rest, Current, LinksLeft);
resolve_parts([<<"..">> | Rest], Current, LinksLeft) ->
    resolve_parts(Rest, filename:dirname(Current), LinksLeft);
resolve_parts([Part | Rest], Current, LinksLeft) ->
    Candidate = filename:join(Current, Part),
    case file:read_link_info(Candidate) of
        {ok, #file_info{type = symlink}} when LinksLeft =:= 0 ->
            {error, {invalid_path, <<"Too many symbolic links">>}};
        {ok, #file_info{type = symlink}} ->
            case file:read_link(Candidate) of
                {ok, Target} ->
                    Absolute = filename:absname(Target, Current),
                    [Root | TargetParts] = filename:split(Absolute),
                    resolve_parts(TargetParts ++ Rest, Root, LinksLeft - 1);
                {error, Reason} -> path_resolution_error(Reason)
            end;
        {ok, #file_info{type = directory}} ->
            resolve_parts(Rest, Candidate, LinksLeft);
        {ok, _} when Rest =:= [] -> {ok, Candidate};
        {ok, _} -> path_resolution_error(enotdir);
        {error, enoent} -> resolve_parts(Rest, Candidate, LinksLeft);
        {error, Reason} -> path_resolution_error(Reason)
    end.

path_resolution_error(Reason) ->
    {error, {invalid_path, unicode:characters_to_binary(
        io_lib:format("Cannot resolve path: ~p", [Reason]))}}.

normalize_path(Path) ->
    Parts = filename:split(Path),
    NormalizedParts = normalize_parts(Parts, []),
    filename:join(NormalizedParts).

normalize_parts([], Acc) ->
    lists:reverse(Acc);
normalize_parts(["." | Rest], Acc) ->
    normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], ["/"]) ->
    normalize_parts(Rest, ["/"]);
normalize_parts([".." | Rest], [_ | Acc]) ->
    normalize_parts(Rest, Acc);
normalize_parts([".." | Rest], []) ->
    %% Already at root, ignore
    normalize_parts(Rest, []);
normalize_parts([Part | Rest], Acc) ->
    normalize_parts(Rest, [Part | Acc]).
