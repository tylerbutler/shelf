-module(storage_safety_test_ffi).
-export([with_directory/1, write_file/2, read_file/1, list_directory/1,
         make_directory/1, symlink/2, with_read_only/2, in_other_process/1,
         with_rename_failure/2, with_delayed_guardian/3,
         with_interrupted_open/2, with_paused_save/3, with_killed_save/4]).

%% All fixture files belong to an exclusively acquired directory. Do not
%% follow links during recursive cleanup, or touch a pre-existing fixture.
with_directory(Fun) ->
    Directory = filename:join(<<"/tmp">>, iolist_to_binary([
        "shelf_storage_", os:getpid(), "_",
        integer_to_list(erlang:unique_integer([positive, monotonic]))])),
    ok = file:make_dir(Directory),
    ok = file:change_mode(Directory, 8#700),
    try Fun(Directory)
    after ok = file:del_dir_r(Directory)
    end.

write_file(Path, Contents) ->
    ok = file:write_file(Path, Contents),
    nil.

read_file(Path) ->
    {ok, Contents} = file:read_file(Path),
    Contents.

list_directory(Path) ->
    {ok, Names} = file:list_dir(Path),
    lists:sort([unicode:characters_to_binary(Name) || Name <- Names]).

make_directory(Path) ->
    ok = file:make_dir(Path),
    nil.

symlink(Target, Path) ->
    ok = file:make_symlink(Target, Path),
    nil.

%% Keep the exact public typed handle. Only replace its underlying native
%% DETS access mode, so Gleam exercises returned errors and counter rollback.
with_read_only({persistent_set, _, Dets, _, _, _}, Fun) ->
    Path = dets:info(Dets, filename),
    ok = dets:close(Dets),
    {ok, Dets} = dets:open_file(Dets, [{file, Path}, {access, read}]),
    try Fun()
    after
        %% OTP 27 delete_all_objects on a read-only table returns this
        %% native file error and retains it until close (not access_mode).
        case dets:close(Dets) of
            ok -> ok;
            {error, {{file_error, Path, {error, einval}}, Path}} -> ok
        end,
        {ok, Dets} = dets:open_file(Dets, [{file, Path}])
    end.

in_other_process(Fun) ->
    Parent = self(),
    Tag = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() -> Parent ! {Tag, Fun()} end),
    receive
        {Tag, Result} ->
            await_down(Pid, Monitor),
            Result;
        {'DOWN', Monitor, process, Pid, Reason} ->
            error({fixture_child_failed, Reason})
    after 5000 ->
        exit(Pid, kill),
        await_down(Pid, Monitor),
        error(fixture_child_timeout)
    end.

await_down(Pid, Monitor) ->
    receive
        {'DOWN', Monitor, process, Pid, _} -> ok
    after 5000 -> error({fixture_monitor_timeout, Pid})
    end.

%% Force rename failure after the temporary snapshot has been created.
%% Restore the original filename even if the Gleam callback fails.
with_rename_failure(Path, Fun) ->
    Backup = <<Path/binary, ".original">>,
    ok = file:rename(Path, Backup),
    ok = file:make_dir(Path),
    try Fun()
    after
        ok = file:del_dir(Path),
        ok = file:rename(Backup, Path)
    end.

%% Open in a child, suspend its guardian, then let native DETS finish
%% owner-death close. The replacement must reclaim the old reservation.
%% Finally deliver the delayed DOWN and verify it cannot erase replacement.
with_delayed_guardian(Open, Replace, Verify) ->
    Parent = self(),
    Tag = make_ref(),
    {Owner, OwnerMonitor} = spawn_monitor(fun() ->
        {ok, Table} = Open(),
        Parent ! {Tag, Table},
        receive {Tag, stop} -> ok end
    end),
    receive
        {Tag, {persistent_set, _, Dets, Guardian, _, _}} ->
            Server = dets:info(Dets, owner),
            ServerMonitor = monitor(process, Server),
            GuardianMonitor = monitor(process, Guardian),
            true = erlang:suspend_process(Guardian),
            try
                Owner ! {Tag, stop},
                await_down(Owner, OwnerMonitor),
                await_down(Server, ServerMonitor),
                Replacement = Replace(),
                true = erlang:resume_process(Guardian),
                await_down(Guardian, GuardianMonitor),
                Verify(Replacement)
            after
                catch erlang:resume_process(Guardian),
                exit(Owner, kill),
                demonitor(OwnerMonitor, [flush]),
                demonitor(ServerMonitor, [flush]),
                demonitor(GuardianMonitor, [flush])
            end;
        {'DOWN', OwnerMonitor, process, Owner, Reason} ->
            error({fixture_open_failed, Reason})
    after 5000 ->
        exit(Owner, kill),
        await_down(Owner, OwnerMonitor),
        error(fixture_open_timeout)
    end.

%% Deterministically kill an owner during dets:open_file: suspend the native
%% server, receive its queued call, then kill the caller before it can return.
with_interrupted_open(Open, Verify) ->
    %% Start native DETS before suspension.
    _ = dets:all(),
    Server = whereis(dets),
    Tag = make_ref(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        receive {Tag, start} -> ok end,
        Open()
    end),
    try
        true = erlang:suspend_process(Server),
        1 = erlang:trace(Owner, true, [send]),
        Owner ! {Tag, start},
        receive
            {trace, Owner, send, {'$gen_call', _, {open, _, _}}, Server} -> ok
        after 5000 -> error(open_not_queued)
        end,
        exit(Owner, kill),
        await_down(Owner, Monitor),
        true = erlang:resume_process(Server),
        Verify()
    after
        catch erlang:resume_process(Server),
        exit(Owner, kill),
        demonitor(Monitor, [flush]),
        flush_trace(Owner)
    end.

flush_trace(Owner) ->
    receive
        {trace, Owner, send, _, _} -> flush_trace(Owner)
    after 0 -> ok
    end.

%% Hold the saving owner at its original DETS close. The temporary snapshot
%% is already complete. Even while the original native server is gone,
%% another public open must not acquire the reserved path.
with_paused_save(Open, Save, Verify) ->
    paused_save(Open, Save, resume, Verify).

with_killed_save(Open, Save, Stage, Verify) ->
    paused_save(Open, Save, Stage, Verify).

paused_save(Open, Save, Finish, Verify) ->
    Parent = self(),
    Tag = make_ref(),
    {Owner, OwnerMonitor} = spawn_monitor(fun() ->
        {ok, Table} = Open(),
        Parent ! {Tag, Table},
        receive {Tag, save} -> ok end,
        {ok, nil} = Save(Table),
        Parent ! {Tag, saved},
        receive {Tag, stop} -> ok end
    end),
    receive
        {Tag, {persistent_set, _, Dets, Guardian, _, _}} ->
            GuardianMonitor = monitor(process, Guardian),
            Server = dets:info(Dets, owner),
            ServerMonitor = monitor(process, Server),
            NativeRegistry = whereis(dets),
            true = erlang:suspend_process(NativeRegistry),
            try
                1 = erlang:trace(Owner, true, [send]),
                Owner ! {Tag, save},
                %% Let save read the original filename/type first. Holding
                %% the temp open gives us a race-free point to suspend the
                %% original file server before its eventual close.
                receive
                    {trace, Owner, send, {'$gen_call', _, {open, _, _}},
                        NativeRegistry} -> ok
                after 5000 -> error(snapshot_not_opening)
                end,
                case Finish of
                    opening_snapshot -> ok;
                    Closing when Closing =:= resume; Closing =:= closing_original ->
                        true = erlang:suspend_process(Server),
                        true = erlang:resume_process(NativeRegistry),
                        receive
                            {trace, Owner, send, {'$gen_call', _, {close, Dets}}, _} -> ok
                        after 5000 -> error(save_not_closing)
                        end
                end,
                case Finish of
                    resume ->
                        true = erlang:suspend_process(Owner),
                        true = erlang:resume_process(Server),
                        await_down(Server, ServerMonitor),
                        Verify(),
                        true = erlang:resume_process(Owner),
                        receive {Tag, saved} -> ok after 5000 -> error(save_timeout) end,
                        Owner ! {Tag, stop},
                        await_down(Owner, OwnerMonitor),
                        await_down(Guardian, GuardianMonitor);
                    closing_original ->
                        %% The temp DETS has closed, but its private file is
                        %% still present and the original close is pending.
                        exit(Owner, kill),
                        await_down(Owner, OwnerMonitor),
                        true = erlang:resume_process(Server),
                        await_down(Server, ServerMonitor),
                        await_down(Guardian, GuardianMonitor),
                        Verify();
                    opening_snapshot ->
                        %% Acquisition succeeded, but the native temp open
                        %% is still queued. Cleanup must wait for that open
                        %% and native owner-death close before unlinking.
                        exit(Owner, kill),
                        await_down(Owner, OwnerMonitor),
                        true = erlang:resume_process(NativeRegistry),
                        await_down(Server, ServerMonitor),
                        await_down(Guardian, GuardianMonitor),
                        Verify()
                end,
                nil
            after
                catch erlang:resume_process(NativeRegistry),
                catch erlang:resume_process(Server),
                catch erlang:resume_process(Owner),
                exit(Owner, kill),
                demonitor(OwnerMonitor, [flush]),
                demonitor(ServerMonitor, [flush]),
                demonitor(GuardianMonitor, [flush]),
                flush_trace(Owner)
            end;
        {'DOWN', OwnerMonitor, process, Owner, Reason} ->
            error({fixture_open_failed, Reason})
    after 5000 ->
        exit(Owner, kill),
        await_down(Owner, OwnerMonitor),
        error(fixture_open_timeout)
    end.
