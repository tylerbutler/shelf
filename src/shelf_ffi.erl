-module(shelf_ffi).
-export([
    open_set/2, open_bag/2, open_duplicate_bag/2,
    open_no_load/3,
    close/2, cleanup/2,
    insert/3, insert_list/3, insert_new/3,
    lookup_set/2, lookup_bag/2, member/2,
    delete_key/2, delete_object/3, delete_all/1,
    to_list/1, fold/3, size/1,
    save/2, load/2, sync_dets/1,
    update_counter/3,
    dets_to_list/1
]).

%% ── Open ────────────────────────────────────────────────────────────────
%% Creates an ETS table + opens a DETS file + loads DETS contents into ETS.
%% Returns {ok, {EtsRef, DetsRef}} or {error, Reason}.

open_set(Name, Path) ->
    do_open(Name, Path, set).

open_bag(Name, Path) ->
    do_open(Name, Path, bag).

open_duplicate_bag(Name, Path) ->
    do_open(Name, Path, duplicate_bag).

do_open(Name, Path, Type) ->
    EtsName = binary_to_atom(Name, utf8),
    %% Use the path as the DETS table name (atom) to avoid collisions
    DetsName = binary_to_atom(Path, utf8),
    try
        %% Open or create the DETS file
        {ok, Dets} = dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {repair, true}
        ]),
        %% Create the ETS table
        Ets = ets:new(EtsName, [Type, public, named_table, {keypos, 1}]),
        %% Load existing DETS data into ETS
        true = ets:from_dets(Ets, Dets),
        {ok, {Ets, Dets}}
    catch
        _:badarg ->
            %% ETS table with this name likely already exists
            case ets:whereis(EtsName) of
                undefined ->
                    {error, {erlang_error, <<"Failed to create table">>}};
                _ ->
                    {error, name_conflict}
            end;
        _:{badmatch, {error, Reason}} ->
            {error, translate_error(Reason)};
        _:Reason ->
            {error, translate_error(Reason)}
    end.

%% ── Open (no load) ──────────────────────────────────────────────────────
%% Creates an ETS table + opens a DETS file but does NOT load DETS into ETS.
%% Used by the validated loading path where Gleam decodes entries before insertion.

open_no_load(Name, Path, TypeBin) ->
    EtsName = binary_to_atom(Name, utf8),
    DetsName = binary_to_atom(Path, utf8),
    Type = binary_to_existing_atom(TypeBin, utf8),
    try
        {ok, Dets} = dets:open_file(DetsName, [
            {file, binary_to_list(Path)},
            {type, Type},
            {repair, true}
        ]),
        Ets = ets:new(EtsName, [Type, public, named_table, {keypos, 1}]),
        {ok, {Ets, Dets}}
    catch
        _:badarg ->
            case ets:whereis(EtsName) of
                undefined ->
                    {error, {erlang_error, <<"Failed to create table">>}};
                _ ->
                    {error, name_conflict}
            end;
        _:{badmatch, {error, Reason}} ->
            {error, translate_error(Reason)};
        _:Reason ->
            {error, translate_error(Reason)}
    end.

%% ── DETS to list ───────────────────────────────────────────────────────
%% Returns all entries from a DETS table as a list of raw Erlang terms.

dets_to_list(Dets) ->
    try
        Result = dets:foldl(fun(Entry, Acc) -> [Entry | Acc] end, [], Dets),
        {ok, Result}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Cleanup ─────────────────────────────────────────────────────────────
%% Delete ETS table and close DETS without saving. Used on validation failure.

cleanup(Ets, Dets) ->
    try
        _ = dets:close(Dets),
        _ = ets:delete(Ets),
        {ok, nil}
    catch
        _:_ -> {ok, nil}
    end.

%% ── Close ───────────────────────────────────────────────────────────────
%% Save ETS→DETS, close DETS, delete ETS.

close(Ets, Dets) ->
    try
        %% Final save
        _ = ets:to_dets(Ets, Dets),
        %% Close DETS file
        ok = dets:close(Dets),
        %% Delete ETS table
        true = ets:delete(Ets),
        {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
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
    try {ok, ets:info(Ets, size)}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% ── Persistence ─────────────────────────────────────────────────────────

%% Snapshot: replace all DETS contents with current ETS state.
save(Ets, Dets) ->
    try ets:to_dets(Ets, Dets) of
        Dets -> {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
    end.

%% Reload: clear ETS, then load from DETS.
load(Ets, Dets) ->
    try
        true = ets:delete_all_objects(Ets),
        true = ets:from_dets(Ets, Dets),
        {ok, nil}
    catch
        _:Reason -> {error, translate_error(Reason)}
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

%% ── Error translation ──────────────────────────────────────────────────

translate_error(not_found) -> not_found;
translate_error(key_already_present) -> key_already_present;
translate_error(name_conflict) -> name_conflict;
translate_error(type_mismatch) -> type_mismatch;
translate_error(badarg) -> table_closed;
translate_error({file_error, _, enoent}) -> {file_error, <<"File not found">>};
translate_error({file_error, _, eacces}) -> {file_error, <<"Permission denied">>};
translate_error({file_error, _, Reason}) ->
    {file_error, list_to_binary(io_lib:format("~p", [Reason]))};
translate_error({error, Reason}) -> translate_error(Reason);
translate_error(Reason) ->
    {erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.
