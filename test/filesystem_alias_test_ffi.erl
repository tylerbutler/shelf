-module(filesystem_alias_test_ffi).
-include_lib("kernel/include/file.hrl").
-export([hardlink/2, same_identity/2, delete_file/1, identity_reserved/1,
         snapshot_path/1, race_open/3, dirty_file/1,
         with_interrupted_acquisition/2, with_paused_repair/3,
         identity_count/1, with_original_close_failure/2, close_native/1]).

hardlink(Target, Alias) ->
    ok = file:make_link(Target, Alias),
    nil.

same_identity(First, Second) ->
    case {file:read_file_info(First), file:read_file_info(Second)} of
        {{ok, One}, {ok, Two}} -> identity(One) =:= identity(Two);
        {{ok, _}, {error, enoent}} -> false
    end.

identity(#file_info{major_device = Major, minor_device = Minor, inode = Inode})
        when is_integer(Inode), Inode > 0 ->
    {file_identity, Major, Minor, Inode}.

delete_file(Path) ->
    ok = file:delete(Path),
    nil.

identity_reserved(Path) ->
    {ok, Info} = file:read_file_info(Path),
    ets:member(shelf_dets_registry, identity(Info)).

identity_count({persistent_set, _, Name, _, _, _}) ->
    length([Key || {{file_identity, _, _, _} = Key, _} <-
        ets:match_object(shelf_dets_registry, {'_', Name})]).

close_native({persistent_set, _, Dets, _, _, _}) ->
    ok = dets:close(Dets),
    nil.

%% A failed read-only delete latches a native write error which close returns.
%% Save's existing recovery reopens the original successfully, so this is a
%% retryable failure, not a terminal handle or a failed rename.
with_original_close_failure({persistent_set, _, Dets, _, _, _}, Fun) ->
    Path = dets:info(Dets, filename),
    ok = dets:close(Dets),
    {ok, Dets} = dets:open_file(Dets, [{file, Path}, {access, read}]),
    {error, _} = dets:delete_all_objects(Dets),
    Fun().

snapshot_path(Directory) ->
    {ok, Names} = file:list_dir(Directory),
    [Snapshot] = [filename:join([Directory, unicode:characters_to_binary(Name),
                                 <<"snapshot.dets">>])
                  || Name <- Names, lists:prefix(".shelf-save-", Name)],
    Snapshot.

%% Hold both successful owners alive until both initial opens have replied.
%% Never pass an opaque handle to a process that does not own it.
race_open(First, Second, Close) ->
    Parent = self(),
    Tag = make_ref(),
    Children = [spawn_monitor(fun() ->
        receive {Tag, start} -> ok end,
        Result = Open(),
        Parent ! {Tag, self(), case Result of
            {ok, _} -> {ok, nil};
            {error, _} = Error -> Error
        end},
        receive {Tag, finish} -> ok end,
        case Result of
            {ok, Table} -> {ok, nil} = Close(Table);
            {error, _} -> ok
        end
    end) || Open <- [First, Second]],
    try
        [Pid ! {Tag, start} || {Pid, _} <- Children],
        Results = [receive
            {Tag, Pid, Result} -> Result;
            {'DOWN', Monitor, process, Pid, Reason} ->
                error({race_child_failed, Reason})
        after 10000 -> error(race_open_timeout)
        end || {Pid, Monitor} <- Children],
        [Pid ! {Tag, finish} || {Pid, _} <- Children],
        [await_down(Pid, Monitor) || {Pid, Monitor} <- Children],
        Results
    after
        [begin exit(Pid, kill), demonitor(Monitor, [flush]) end
         || {Pid, Monitor} <- Children]
    end.

await_down(Pid, Monitor) ->
    receive
        {'DOWN', Monitor, process, Pid, normal} -> ok;
        {'DOWN', Monitor, process, Pid, Reason} ->
            error({fixture_child_failed, Reason})
    after 10000 -> error({fixture_child_timeout, Pid})
    end.

%% Mark the version-9 closed flag dirty, as an interrupted native writer
%% would. DETS' own repair code reconstructs the file on the next open.
dirty_file(Path) ->
    {ok, File} = file:open(Path, [read, write, raw, binary]),
    try
        {ok, <<1:32>>} = file:pread(File, 8, 4),
        ok = file:pwrite(File, 8, <<0:32>>)
    after ok = file:close(File)
    end,
    nil.

%% Kill after the guardian has acquired the path but before identity
%% publication. The owner, not the guardian, creates the final native file.
with_interrupted_acquisition(Open, Verify) ->
    _ = dets:all(),
    Native = whereis(dets),
    Parent = self(),
    Tag = make_ref(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        receive {Tag, start} -> ok end,
        Open(),
        Parent ! {Tag, unexpected_open}
    end),
    true = erlang:suspend_process(Native),
    try
        1 = erlang:trace(Owner, true, [send]),
        Owner ! {Tag, start},
        Guardian = receive
            {trace, Owner, send,
                {'$gen_call', _, {open, {shelf_dets, Owner, _, Pid}, _}},
                Native} -> Pid
        after 5000 -> error(native_open_not_queued)
        end,
        GuardianMonitor = monitor(process, Guardian),
        exit(Owner, kill),
        receive {'DOWN', Monitor, process, Owner, killed} -> ok end,
        true = erlang:resume_process(Native),
        await_down(Guardian, GuardianMonitor),
        Verify()
    after
        resume(Native),
        exit(Owner, kill),
        demonitor(Monitor, [flush]),
        flush_trace()
    end.

resume(Pid) ->
    try erlang:resume_process(Pid) catch error:badarg -> ok end.

flush_trace() ->
    receive
        {trace, _, _, _, _} -> flush_trace();
        {trace, _, _, _} -> flush_trace()
    after 0 -> ok
    end.

%% Suspend the opening owner at return from dets:open_file, before the
%% guardian publishes the repaired inode. A competing alias open must wait.
with_paused_repair(Open, AliasOpen, Close) ->
    _ = dets:all(),
    Native = whereis(dets),
    Parent = self(),
    Tag = make_ref(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        receive {Tag, start} -> ok end,
        {ok, Table} = Open(),
        Parent ! {Tag, opened},
        receive {Tag, finish} -> ok end,
        {ok, nil} = Close(Table)
    end),
    true = erlang:suspend_process(Native),
    1 = erlang:trace(Owner, true, [send]),
    try
        Owner ! {Tag, start},
        Name = receive
            {trace, Owner, send, {'$gen_call', _, {open, Dets, _}}, Native} ->
                Dets
        after 5000 -> error(repair_open_timeout)
        end,
        true = erlang:suspend_process(Owner),
        true = erlang:resume_process(Native),
        await_native_open(Name, 500),
        %% Repair has exposed a new inode; finish_open has not run.
        {AliasOwner, AliasMonitor} = spawn_monitor(fun() ->
            Result = case AliasOpen() of
                {ok, AliasTable} ->
                    {ok, nil} = Close(AliasTable),
                    {ok, nil};
                {error, _} = Error -> Error
            end,
            Parent ! {Tag, alias_result, Result}
        end),
        try
            receive
                {Tag, alias_result, Early} -> error({unreserved_repair_window, Early})
            after 50 -> ok
            end,
            true = erlang:resume_process(Owner),
            receive {Tag, opened} -> ok after 5000 -> error(open_timeout) end,
            Result = receive
                {Tag, alias_result, Reply} -> Reply
            after 10000 -> error(alias_open_timeout)
            end,
            await_down(AliasOwner, AliasMonitor),
            Owner ! {Tag, finish},
            await_down(Owner, Monitor),
            Result
        after
            exit(AliasOwner, kill),
            demonitor(AliasMonitor, [flush])
        end
    after
        resume(Native),
        resume(Owner),
        exit(Owner, kill),
        demonitor(Monitor, [flush]),
        flush_trace()
    end.

await_native_open(_Name, 0) -> error(native_open_timeout);
await_native_open(Name, Attempts) ->
    case dets:info(Name, filename) of
        undefined ->
            timer:sleep(10),
            await_native_open(Name, Attempts - 1);
        _ -> ok
    end.
