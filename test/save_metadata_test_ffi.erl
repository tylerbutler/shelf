-module(save_metadata_test_ffi).
-include_lib("kernel/include/file.hrl").
-export([with_handle/2, metadata/1, prepare_metadata/2, with_missing_original/2,
         prepare_group_failure/2, assert_closed/1]).

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
