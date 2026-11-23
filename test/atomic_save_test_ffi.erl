-module(atomic_save_test_ffi).
-export([with_crashed_save/3, crash_child/0, with_cleanup_permission_failure/2,
         with_guardian_cleanup_retry/5]).

%% Gleam:
%% type SaveStage { OpeningSnapshot ClosingOriginal }
%% with_crashed_save(String, SaveStage, fn(String) -> a) -> a
%% Callback runs only after the separate OS process has exited. It receives
%% the exact abandoned directory; table.dets retains {"committed", 1}, while
%% {"uncommitted", 2} exists only in the interrupted snapshot.
%% Uses the current build's beams; never compiles, downloads, or kills this VM.
with_crashed_save(Directory, Stage, Verify)
        when Stage =:= opening_snapshot; Stage =:= closing_original ->
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    Paths = [filename:absname(Path) || Path <- code:get_path()],
    Args = ["+S", "1:1", "-noshell", "-noinput", "-pa"] ++ Paths ++
        ["-eval", "atomic_save_test_ffi:crash_child().", "-extra",
         binary_to_list(base64:encode(Directory)), atom_to_list(Stage)],
    %% A private monitored runner owns all ports and their late messages.
    %% Callback exceptions propagate normally, outside that runner.
    Parent = self(),
    Tag = make_ref(),
    {Runner, Monitor} = spawn_monitor(fun() ->
        Parent ! {Tag, crash_external(Erl, Args)}
    end),
    receive
        {Tag, Snapshot} ->
            await_runner(Runner, Monitor),
            Verify(Snapshot);
        {'DOWN', Monitor, process, Runner, Reason} ->
            error({crash_fixture_failed, Reason})
    after 30000 ->
        %% The runner has shorter bounded port waits and an OS-kill finalizer.
        %% Do not kill it here and interrupt that finalizer.
        error(crash_fixture_runner_timeout)
    end.

await_runner(Runner, Monitor) ->
    receive
        {'DOWN', Monitor, process, Runner, normal} -> ok;
        {'DOWN', Monitor, process, Runner, Reason} ->
            error({crash_fixture_failed, Reason})
    after 5000 -> error(crash_fixture_runner_timeout)
    end.

crash_external(Erl, Args) ->
    %% Fail before launching a VM if its required shutdown tool is absent.
    case os:find_executable("kill") of
        false -> error(crash_fixture_kill_unavailable);
        _ -> ok
    end,
    Port = open_port({spawn_executable, Erl},
        [binary, exit_status, use_stdio, stderr_to_stdout, {line, 4096},
         {args, Args}]),
    {os_pid, Pid} = erlang:port_info(Port, os_pid),
    try
        Snapshot = await_ready(Port, deadline(10000), 0),
        kill_exact(Pid),
        await_exit(Port, deadline(5000)),
        Snapshot
    after
        %% port_info is about our owned child, not abandonment probing.
        %% If readiness/assertions fail, still stop exactly this external VM.
        case erlang:port_info(Port) of
            undefined -> ok;
            _ ->
                kill_exact(Pid),
                await_exit(Port, deadline(5000))
        end
    end.

deadline(Milliseconds) ->
    erlang:monotonic_time(millisecond) + Milliseconds.

remaining(Deadline) ->
    max(0, Deadline - erlang:monotonic_time(millisecond)).

await_ready(Port, Deadline, Bytes) ->
    receive
        {Port, {data, {eol, <<"SHELF_READY ", Encoded/binary>>}}} ->
            base64:decode(Encoded);
        {Port, {data, {_, Line}}} when Bytes + byte_size(Line) < 16384 ->
            await_ready(Port, Deadline, Bytes + byte_size(Line));
        {Port, {data, _}} -> error(crash_fixture_output_limit);
        {Port, {exit_status, Status}} -> error({crash_child_exited, Status})
    after remaining(Deadline) -> error(crash_child_readiness_timeout)
    end.

await_exit(Port, Deadline) ->
    receive
        {Port, {exit_status, _}} -> ok;
        {Port, {data, _}} -> await_exit(Port, Deadline)
    after remaining(Deadline) -> error(crash_child_exit_timeout)
    end.

kill_exact(Pid) when is_integer(Pid), Pid > 0 ->
    case os:find_executable("kill") of
        false -> error(crash_fixture_kill_unavailable);
        Executable ->
            Kill = open_port({spawn_executable, Executable},
                [binary, exit_status, use_stdio, stderr_to_stdout,
                 {args, ["-KILL", integer_to_list(Pid)]}]),
            await_kill(Kill, deadline(5000))
    end.

await_kill(Port, Deadline) ->
    receive
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({crash_fixture_kill_failed, Status});
        {Port, {data, _}} -> await_kill(Port, Deadline)
    after remaining(Deadline) -> error(crash_fixture_kill_timeout)
    end.

%% Exported only as the -eval entry point of the isolated BEAM.
crash_child() ->
    [Encoded, StageText] = init:get_plain_arguments(),
    Directory = base64:decode(Encoded),
    Stage = case StageText of
        "opening_snapshot" -> opening_snapshot;
        "closing_original" -> closing_original
    end,
    Controller = self(),
    Tag = make_ref(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        Path = filename:join(Directory, <<"table.dets">>),
        {ok, Canonical} = shelf_ffi:validate_path(Path, Directory),
        {ok, {Ets, Dets, _Guardian}} =
            shelf_ffi:open_no_load(<<"crash_fixture">>, Canonical, set),
        {ok, nil} = shelf_ffi:insert(Ets, Dets, {<<"committed">>, 1}),
        {ok, nil} = shelf_ffi:dets_insert(Ets, Dets, {<<"committed">>, 1}),
        {ok, nil} = shelf_ffi:sync_dets(Dets),
        {ok, nil} = shelf_ffi:insert(Ets, Dets, {<<"uncommitted">>, 2}),
        Controller ! {Tag, Dets},
        receive {Tag, save} -> shelf_ffi:save(Ets, Dets) end
    end),
    Dets = receive
        {Tag, Handle} -> Handle;
        {'DOWN', Monitor, process, Owner, Reason} -> error({crash_child_open_failed, Reason})
    after 5000 -> error(crash_child_open_timeout)
    end,
    Server = dets:info(Dets, owner),
    NativeRegistry = whereis(dets),
    true = erlang:suspend_process(NativeRegistry),
    1 = erlang:trace(Owner, true, [send]),
    Owner ! {Tag, save},
    receive
        {trace, Owner, send, {'$gen_call', _, {open, _, _}}, NativeRegistry} -> ok
    after 5000 -> error(crash_child_snapshot_not_opening)
    end,
    case Stage of
        opening_snapshot -> ok;
        closing_original ->
            true = erlang:suspend_process(Server),
            true = erlang:resume_process(NativeRegistry),
            receive
                {trace, Owner, send, {'$gen_call', _, {close, Dets}}, _} -> ok
            after 5000 -> error(crash_child_original_not_closing)
            end
    end,
    {ok, Names} = file:list_dir(Directory),
    [SnapshotName] = [Name || Name <- Names, lists:prefix(".shelf-save-", Name)],
    Snapshot = filename:join(Directory, unicode:characters_to_binary(SnapshotName)),
    io:format("SHELF_READY ~s~n", [base64:encode(Snapshot)]),
    %% No sleep/poll loop. OS death, not a shared-VM owner exit, is the test.
    receive never -> error(crash_child_unexpected_resume) end.

%% Gleam: with_cleanup_permission_failure(String, fn() -> a) -> a
%% The private snapshot stays readable for preflight but cannot be unlinked
%% by an ordinary user. Tests running as root cannot rely on this fixture.
with_cleanup_permission_failure(Directory, Fun) ->
    ok = file:change_mode(Directory, 8#500),
    try Fun()
    after ok = file:change_mode(Directory, 8#700)
    end.

%% Gleam:
%% with_guardian_cleanup_retry(
%%   String,
%%   fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
%%   fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
%%   fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
%%   fn(String, shelf.ShelfError) -> Nil,
%% ) -> Nil
%%
%% Directory must be an exclusive storage_safety with_directory fixture.
%% Reuse its native-close barrier and shutdown/trace cleanup. Unknown files
%% reliably block cleanup even as root, unlike directory permission changes.
%% Verify runs in the owning process twice, with the retained directory and
%% each typed save error. After unblocking, that SAME owner saves and closes.
with_guardian_cleanup_retry(Directory, Open, Save, Close, Verify) ->
    BlockerName = <<"cleanup-retry-blocker">>,
    storage_safety_test_ffi:with_paused_save(Open, fun(Table) ->
        {error, {invalid_path, _} = FirstError} = Save(Table),
        [Snapshot] = retry_snapshot_directories(Directory),
        Blocker = filename:join(Snapshot, BlockerName),
        {ok, <<"block cleanup">>} = file:read_file(Blocker),
        nil = Verify(Snapshot, FirstError),
        %% An unsuccessful retry must retain the old directory, not acquire
        %% another snapshot or silently report success.
        {error, {invalid_path, _} = RetryError} = Save(Table),
        [Snapshot] = retry_snapshot_directories(Directory),
        {ok, <<"block cleanup">>} = file:read_file(Blocker),
        nil = Verify(Snapshot, RetryError),
        ok = file:delete(Blocker),
        {ok, nil} = Save(Table),
        [] = retry_snapshot_directories(Directory),
        {ok, nil} = Close(Table),
        [] = retry_snapshot_directories(Directory),
        {ok, nil}
    end, fun() ->
        %% The owner is suspended at its original native close, before
        %% rename and guardian cleanup can run.
        [Snapshot] = retry_snapshot_directories(Directory),
        ok = file:write_file(filename:join(Snapshot, BlockerName),
                             <<"block cleanup">>)
    end).

retry_snapshot_directories(Directory) ->
    {ok, Names} = file:list_dir(Directory),
    lists:sort([filename:join(Directory, unicode:characters_to_binary(Name))
                || Name <- Names, lists:prefix(".shelf-save-", Name)]).
