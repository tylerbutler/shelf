-module(close_test_ffi).
-export([
    simulate_external_dets_close/1,
    cleanup_after_failed_close/2,
    with_close_recovery_fixture/1,
    dets_reference_for_path/1,
    dets_is_closed/1,
    registry_contains_path/1,
    delete_file/1,
    create_directory/1,
    make_directory_read_only/1,
    make_directory_writable/1,
    delete_directory/1
]).

%% Exclusively create a dedicated fixture directory. Never reuse or remove
%% a pre-existing path, even if a previous VM left one with the same name.
with_close_recovery_fixture(Fun) ->
    Directory = filename:join("/tmp", "shelf_close_recovery_" ++ os:getpid()
        ++ "_" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))),
    ok = file:make_dir(Directory),
    Path = filename:join(Directory, "table.dets"),
    try
        Fun(list_to_binary(Path))
    after
        remove_fixture_path(Path),
        remove_fixture_path(Path ++ ".tmp"),
        ok = file:del_dir(Directory)
    end.

remove_fixture_path(Path) ->
    case file:del_dir(Path) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, enotdir} -> ok = file:delete(Path)
    end.

%% Observe the exact registered name before inducing a real save failure.
dets_reference_for_path(Path) ->
    [{Path, Name}] = ets:lookup(shelf_dets_registry, Path),
    Name.

dets_is_closed(Name) ->
    dets:info(Name) =:= undefined.

registry_contains_path(Path) ->
    ets:member(shelf_dets_registry, Path).

%% Close the DETS table behind shelf's back to simulate a terminal
%% external failure.
simulate_external_dets_close(Path) ->
    Resolved = filename:absname(binary_to_list(Path)),
    Normalized = list_to_binary(shelf_ffi:normalize_path(Resolved)),
    [{Normalized, Name}] = ets:lookup(shelf_dets_registry, Normalized),
    ok = dets:close(Name),
    nil.

%% Force cleanup of ETS + DETS + file after a test that left things open.
cleanup_after_failed_close(Path, Name) ->
    _ = (catch simulate_external_dets_close(Path)),
    catch ets:delete(binary_to_atom(Name, utf8)),
    file:delete(Path),
    nil.

%% Normalize Erlang's bare ok and POSIX errors to the Gleam test contract.
delete_file(Path) ->
    case file:delete(Path) of
        ok -> {ok, nil};
        {error, enoent} -> {error, file_not_found};
        {error, Reason} ->
            Detail = unicode:characters_to_binary(io_lib:format(
                "~ts: ~ts (~p)", [Path, file:format_error(Reason), Reason])),
            {error, {file_delete_failed, Detail}}
    end.

create_directory(Directory) ->
    DirectoryList = binary_to_list(Directory),
    case file:make_dir(DirectoryList) of
        ok -> ok;
        {error, eexist} -> ok
    end,
    ok = file:change_mode(DirectoryList, 8#700),
    nil.

make_directory_read_only(Directory) ->
    ok = file:change_mode(binary_to_list(Directory), 8#500),
    nil.

make_directory_writable(Directory) ->
    case file:change_mode(binary_to_list(Directory), 8#700) of
        ok -> ok;
        {error, enoent} -> ok
    end,
    nil.

delete_directory(Directory) ->
    case file:del_dir(binary_to_list(Directory)) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, eexist} -> ok;
        {error, enotempty} -> ok
    end,
    nil.
