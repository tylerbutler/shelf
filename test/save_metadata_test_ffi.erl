-module(save_metadata_test_ffi).
-include_lib("kernel/include/file.hrl").
-export([with_handle/2, metadata/1, prepare_metadata/2, with_missing_original/2,
         prepare_group_failure/2, assert_closed/1, is_macos/0, identity/1,
         prepare_extended/1, protections/1, inherit_acl/1, with_flags/2,
         with_unreadable_attributes/2, with_ambiguous_names/2,
         with_missing_tools/1, rejects_incomplete_archive/1,
         with_delete_denial/2, with_large_fork/2, owner_exit_barrier/1,
         rejects_verification_mismatch/2, with_native_identity/2]).

is_macos() ->
    os:type() =:= {unix, darwin}.

with_native_identity({persistent_set, _, Dets, _, _, _}, Fun) ->
    Server = dets:info(Dets, owner),
    true = is_pid(Server),
    try Fun()
    after Server = dets:info(Dets, owner)
    end.

identity(Path) ->
    {ok, #file_info{major_device = Major, minor_device = Minor, inode = Inode}} =
        file:read_file_info(Path),
    {Major, Minor, Inode}.

fixture_tool(Path, Tool, Args, Consumer) ->
    Monitor = monitor(process, self()),
    try
        {ok, Output} = shelf_metadata:run(self(), Monitor, Tool, Args, Consumer,
            unicode:characters_to_list(filename:dirname(Path))),
        Output
    after demonitor(Monitor, [flush])
    end.

prepare_extended(Path) ->
    <<>> = fixture_tool(Path, "/bin/chmod", ["-N", Path], text),
    %% Exercise ordered deny/allow entries, including the regular-file
    %% inheritance bits that ls silently omits.
    <<>> = fixture_tool(Path, "/bin/chmod",
        ["+a#", "0", "group:everyone deny execute", Path], text),
    <<>> = fixture_tool(Path, "/bin/chmod",
        ["+a#", "1",
         "group:everyone allow read,inherited,file_inherit,directory_inherit,limit_inherit,only_inherit",
         Path], text),
    <<>> = fixture_tool(Path, "/usr/bin/xattr",
        ["-wx", "shelf.binary", "00FF0A0080FE", Path], text),
    <<>> = fixture_tool(Path, "/usr/bin/xattr",
        ["-wx", "shelf.second", "010203", Path], text),
    <<>> = fixture_tool(Path, "/usr/bin/xattr",
        ["-wx", "--", "-shelf spaced attribute", "FF000A", Path], text),
    protections(Path).

protections(Path) ->
    {ok, #file_info{size = Size}} = file:read_file_info(Path),
    Base = filename:basename(Path),
    Name = <<"./", Base/binary>>,
    Sidecar = fixture_tool(Path, "/usr/bin/bsdtar",
        ["-c", "--format=pax", "--mac-metadata", "--no-acls",
         "--no-xattrs", "--no-fflags", "--no-recursion", "-f", "-",
         "-C", filename:dirname(Path), Name],
        {archive, Size, Name, regular}),
    Flags = fixture_tool(Path, "/usr/bin/stat", ["-f", "%f", Path], text),
    %% A BitArray at the Gleam boundary, not an unsafe String conversion.
    term_to_binary({Sidecar, Flags}).

inherit_acl(Directory) ->
    <<>> = fixture_tool(Directory, "/bin/chmod",
        ["+a", "group:everyone allow read,execute,file_inherit,directory_inherit,only_inherit",
         Directory], text),
    nil.

with_flags(Path, Fun) ->
    <<>> = fixture_tool(Path, "/usr/bin/chflags", ["nodump", Path], text),
    try
        Result = Fun(),
        <<"1\n">> = fixture_tool(Path, "/usr/bin/stat", ["-f", "%f", Path], text),
        Result
    after
        <<>> = fixture_tool(Path, "/usr/bin/chflags", ["0", Path], text)
    end.

with_unreadable_attributes(Path, Fun) ->
    <<>> = fixture_tool(Path, "/bin/chmod",
        ["+a#", "0", "group:everyone deny readextattr", Path], text),
    try Fun()
    after
        <<>> = fixture_tool(Path, "/bin/chmod", ["-a#", "0", Path], text)
    end.

with_ambiguous_names(Path, Fun) ->
    Names = [<<"shelf.fragment.one">>, <<"shelf.fragment.two">>,
             <<"shelf.fragment.one\nshelf.fragment.two">>],
    lists:foreach(fun(Name) ->
        <<>> = fixture_tool(Path, "/usr/bin/xattr",
            ["-wx", Name, "73656372657476616C7565", Path], text)
    end, Names),
    try Fun()
    after
        lists:foreach(fun(Name) ->
            <<>> = fixture_tool(Path, "/usr/bin/xattr", ["-d", Name, Path], text)
        end, Names)
    end.

with_delete_denial(Path, Fun) ->
    <<>> = fixture_tool(Path, "/bin/chmod",
        ["+a#", "0", "group:everyone deny delete,only_inherit", Path], text),
    try Fun()
    after
        <<>> = fixture_tool(Path, "/bin/chmod", ["-a#", "0", Path], text)
    end.

with_large_fork(Path, Fun) ->
    Fork = <<Path/binary, "/..namedfork/rsrc">>,
    ok = file:write_file(Fork, binary:copy(<<0>>, 65537)),
    try Fun()
    after
        <<>> = fixture_tool(Path, "/usr/bin/xattr",
            ["-d", "com.apple.ResourceFork", Path], text)
    end.

with_missing_tools(Fun) ->
    Original = os:getenv("PATH"),
    true = os:putenv("PATH", ""),
    try Fun()
    after
        case Original of
            false -> true = os:unsetenv("PATH");
            _ -> true = os:putenv("PATH", Original)
        end
    end.

rejects_incomplete_archive(Directory) ->
    Path = filename:join(Directory, <<"incomplete.tar">>),
    ok = file:write_file(Path, <<0:4096>>),
    Monitor = monitor(process, self()),
    try
        shelf_metadata:run(self(), Monitor, "/bin/cat", [Path],
            {archive, 0, <<"./entry">>, regular},
            unicode:characters_to_list(Directory))
            =:= {error, incomplete_archive}
    after
        demonitor(Monitor, [flush]),
        ok = file:delete(Path)
    end.

owner_exit_barrier(Directory) ->
    Owner = spawn(fun() -> receive stop -> ok end end),
    Monitor = monitor(process, Owner),
    Timer = erlang:send_after(20, Owner, stop),
    Start = erlang:monotonic_time(millisecond),
    try
        Result = shelf_metadata:run(Owner, Monitor, "/bin/sleep", ["0.15"],
            text, unicode:characters_to_list(Directory)),
        Elapsed = erlang:monotonic_time(millisecond) - Start,
        Result =:= {error, owner_exited} andalso Elapsed >= 100
    after
        _ = erlang:cancel_timer(Timer),
        exit(Owner, kill),
        demonitor(Monitor, [flush])
    end.

%% Exercise the same complete-set verifier used by save without relying on
%% a timing-sensitive concurrent chmod/xattr race or production test hooks.
rejects_verification_mismatch(
        {persistent_set, _, _, Guardian, _, _}, Path) ->
    Ref = monitor(process, Guardian),
    Guardian ! {acquire_snapshot, self(), Ref},
    try
        receive
            {Ref, {ok, {Directory, Temporary}}} ->
                try
                    ok = shelf_metadata:prepare_directory(Guardian, Directory),
                    {Acl, Attributes} =
                        shelf_metadata:read(Guardian, fixture, Path, Directory),
                    Expected = {Acl,
                        [{<<"shelf.absent">>, <<"73656372657476616C7565">>}
                         | Attributes]},
                    try shelf_metadata:verify(Guardian, verify_snapshot,
                            Path, Directory, Expected) of
                        ok -> false
                    catch
                        error:{file_error, Path,
                                {native_metadata, verify_snapshot, mismatch}} -> true
                    end
                after
                    Guardian ! {{finish_snapshot, Temporary}, self(), Ref},
                    receive {Ref, ok} -> ok end
                end;
            {'DOWN', Ref, process, Guardian, Reason} ->
                exit({fixture_guardian_failed, Reason})
        end
    after demonitor(Ref, [flush])
    end.

%% Never save during assertion-failure cleanup, which could hide evidence.
with_handle({persistent_set, Ets, Dets, Guardian, _, _}, Fun) ->
    GuardianMonitor = monitor(process, Guardian),
    try Fun()
    after
        %% Save can replace the native server, so capture the current one
        %% immediately before cleanup, not before entering the callback.
        NativeMonitor = case dets:info(Dets, owner) of
            undefined -> none;
            Server -> monitor(process, Server)
        end,
        try
            case shelf_ffi:cleanup(Ets, Dets, Guardian) of
                {ok, nil} -> ok;
                {error, table_closed} -> ok
            end
        after
            try await_shutdown(NativeMonitor)
            after await_shutdown(GuardianMonitor)
            end
        end
    end.

await_shutdown(none) -> ok;
await_shutdown(Monitor) ->
    receive
        {'DOWN', Monitor, process, _, _} -> ok
    after 5000 ->
        demonitor(Monitor, [flush]),
        error(fixture_shutdown_timeout)
    end.

assert_closed({persistent_set, Ets, Dets, Guardian, _, _}) ->
    undefined = ets:info(Ets),
    undefined = dets:info(Dets),
    false = is_process_alive(Guardian),
    nil.

metadata(Path) ->
    {ok, #file_info{mode = Mode, uid = Uid, gid = Gid}} =
        file:read_file_info(Path),
    {Mode band 8#7777, Uid, Gid}.

prepare_metadata(Path, Mode) ->
    {_, Uid, OriginalGid} = metadata(Path),
    %% Use a real supplementary group different from the new-file default
    %% where the host permits it. Otherwise still verify exact uid/gid.
    Groups = supplementary_groups(),
    set_nondefault_group(Path, OriginalGid, Groups),
    ok = file:change_mode(Path, Mode),
    {Mode, Uid, _} = Metadata = metadata(Path),
    Metadata.

set_nondefault_group(_Path, _Original, []) -> ok;
set_nondefault_group(Path, Original, [Original | Rest]) ->
    set_nondefault_group(Path, Original, Rest);
set_nondefault_group(Path, Original, [Group | Rest]) ->
    case file:change_group(Path, Group) of
        ok -> ok;
        {error, eperm} -> set_nondefault_group(Path, Original, Rest);
        {error, enotsup} -> set_nondefault_group(Path, Original, Rest)
    end.

supplementary_groups() ->
    case os:find_executable("id") of
        false -> [];
        Executable ->
            Port = open_port({spawn_executable, Executable},
                [binary, exit_status, use_stdio, {args, ["-G"]}]),
            try collect_groups(Port, <<>>)
            after
                try port_close(Port) catch error:badarg -> ok end
            end
    end.

collect_groups(Port, Output) ->
    receive
        {Port, {data, Data}} when byte_size(Output) + byte_size(Data) < 4096 ->
            collect_groups(Port, <<Output/binary, Data/binary>>);
        {Port, {exit_status, 0}} ->
            [binary_to_integer(Group) ||
                Group <- re:split(Output, <<"\\s+">>, [trim]),
                Group =/= <<>>];
        {Port, {exit_status, _}} -> []
    after 5000 -> error(group_lookup_timeout)
    end.

%% Some systems inherit a directory's group even when the owner is not a
%% member (e.g. wheel-owned /tmp on macOS). Change only our private directory
%% to a supplementary group, and probe the exact native ownership write.
prepare_group_failure(Directory, Path) ->
    {_, Uid, Gid} = metadata(Path),
    Groups = supplementary_groups(),
    case {lists:member(Gid, Groups), Groups} of
        {false, [Group | _]} ->
            ok = file:change_group(Directory, Group),
            Probe = filename:join(Directory, <<"group-probe">>),
            ok = file:write_file(Probe, <<>>),
            try
                file:write_file_info(Probe, #file_info{uid = Uid, gid = Gid})
                    =:= {error, eperm}
            after ok = file:delete(Probe)
            end;
        _ -> false
    end.

with_missing_original(Path, Fun) ->
    Backup = <<Path/binary, ".original">>,
    ok = file:rename(Path, Backup),
    try Fun()
    after
        %% On the unfixed implementation, save has wrongly created Path.
        case file:delete(Path) of
            ok -> ok;
            {error, enoent} -> ok
        end,
        ok = file:rename(Backup, Path)
    end.
