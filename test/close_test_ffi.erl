-module(close_test_ffi).
-export([
    simulate_external_dets_close/1,
    cleanup_after_failed_close/2,
    create_directory/1,
    make_directory_read_only/1,
    make_directory_writable/1,
    delete_directory/1
]).

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

create_directory(Dir) ->
    DirList = binary_to_list(Dir),
    case file:make_dir(DirList) of
        ok -> ok;
        {error, eexist} -> ok
    end,
    ok = file:change_mode(DirList, 8#700),
    nil.

make_directory_read_only(Dir) ->
    ok = file:change_mode(binary_to_list(Dir), 8#500),
    nil.

make_directory_writable(Dir) ->
    case file:change_mode(binary_to_list(Dir), 8#700) of
        ok -> ok;
        {error, enoent} -> ok
    end,
    nil.

delete_directory(Dir) ->
    case file:del_dir(binary_to_list(Dir)) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, eexist} -> ok;
        {error, enotempty} -> ok
    end,
    nil.
