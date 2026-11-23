%% Sequential test fixtures only. Temporarily instrument BEAM abstract code
%% in memory, restoring it afterwards; no runtime configuration/test bypass
%% is present in the shipped module.
-module(metadata_instrumentation_test_ffi).
-export([with_verification_failure/2, with_gnu_timeout/1, has_gnu_timeout/0,
         has_apple_timeout/0, timed_writer/3,
         verification_result/3, before_cleanup/1]).

with_verification_failure(Path, Fun) ->
    with_patch([verify], fun() ->
        put({?MODULE, mismatch}, Path),
        put({?MODULE, mismatch_count}, 0),
        try
            Result = Fun(),
            %% One forced comparison failure each through save and close.
            2 = get({?MODULE, mismatch_count}),
            Result
        after
            erase({?MODULE, mismatch}),
            erase({?MODULE, mismatch_count})
        end
    end).

verification_result(Actual, Stage, _Path) ->
    case {get({?MODULE, mismatch}), Stage} of
        {Armed, verify_snapshot} when is_binary(Armed) ->
            put({?MODULE, mismatch_count},
                get({?MODULE, mismatch_count}) + 1),
            {Acl, Attributes} = Actual,
            {Acl, [{<<"shelf.injected">>, <<"00">>} | Attributes]};
        _ -> Actual
    end.

has_apple_timeout() ->
    os:find_executable("/usr/bin/timeout") =/= false.

has_gnu_timeout() ->
    lists:any(fun(Prefix) ->
        filelib:is_file(filename:join([Prefix, "bin", "gtimeout"]))
    end, ["/opt/homebrew", "/usr/local"]).

with_gnu_timeout(Fun) ->
    with_patch([gnu], Fun).

with_patch(Modes, Fun) ->
    {module, shelf_metadata} = code:ensure_loaded(shelf_metadata),
    {shelf_metadata, Original, Filename} = code:get_object_code(shelf_metadata),
    {ok, {shelf_metadata, [{abstract_code, {raw_abstract_v1, Forms}}]}} =
        beam_lib:chunks(Original, [abstract_code]),
    PatchedForms = [instrument(Form, Modes) || Form <- Forms],
    {ok, shelf_metadata, Patched, []} =
        compile:forms(PatchedForms, [binary, debug_info, return_errors, return_warnings]),
    true = code:soft_purge(shelf_metadata),
    {module, shelf_metadata} = code:load_binary(shelf_metadata, Filename, Patched),
    try Fun()
    after
        true = code:soft_purge(shelf_metadata),
        {module, shelf_metadata} =
            code:load_binary(shelf_metadata, Filename, Original),
        true = code:soft_purge(shelf_metadata)
    end.

instrument({function, L, verify, 5, Clauses} = Form, Modes) ->
    case lists:member(verify, Modes) of
        true -> {function, L, verify, 5, rewrite_read(Clauses)};
        false -> Form
    end;
instrument({function, L, timeout_executable, 0, _} = Form, Modes) ->
    case lists:member(gnu, Modes) of
        true ->
            Call = {call, L, {atom, L, homebrew_timeout},
                [erl_parse:abstract(["/opt/homebrew", "/usr/local"])]},
            {function, L, timeout_executable, 0,
                [{clause, L, [], [], [Call]}]};
        false -> Form
    end;
instrument({function, L, cleanup_directory, 1, Clauses} = Form, Modes) ->
    case lists:member(cleanup, Modes) of
        true ->
            Updated = [{clause, C, [Directory], Guards,
                [remote_call(C, before_cleanup, [Directory]) | Body]}
                || {clause, C, [Directory], Guards, Body} <- Clauses],
            {function, L, cleanup_directory, 1, Updated};
        false -> Form
    end;
instrument(Form, _) -> Form.

rewrite_read({call, L, {atom, _, read}, _} = Call) ->
    remote_call(L, verification_result,
        [Call, {var, L, 'Stage'}, {var, L, 'Path'}]);
rewrite_read(Tuple) when is_tuple(Tuple) ->
    list_to_tuple([rewrite_read(Item) || Item <- tuple_to_list(Tuple)]);
rewrite_read(List) when is_list(List) -> [rewrite_read(Item) || Item <- List];
rewrite_read(Other) -> Other.

remote_call(L, Function, Args) ->
    {call, L, {remote, L, {atom, L, ?MODULE}, {atom, L, Function}}, Args}.

%% The real reservation guardian must not enter cleanup until the timed
%% writer is dead/reaped. Stop at that boundary and handshake with the
%% parent; this is not an elapsed-time assertion.
before_cleanup(Directory) ->
    case ets:whereis(?MODULE) of
        undefined -> ok;
        _ ->
            case ets:lookup(?MODULE, Directory) of
                [{Directory, Parent, Tag, Pid}] ->
                    Dead = not process_exists(Pid),
                    Parent ! {Tag, cleanup_barrier, self(), Directory,
                        Dead, filelib:is_dir(Directory)},
                    receive {Tag, continue} -> ok
                    after 5000 -> error(fixture_cleanup_ack_timeout)
                    end;
                [] -> ok
            end
    end.

process_exists(Pid) ->
    Port = open_port({spawn_executable, "/bin/ps"},
        [binary, exit_status, use_stdio, stderr_to_stdout,
         {args, ["-p", integer_to_list(Pid), "-o", "pid="]}]),
    ps_status(Port).

ps_status(Port) ->
    receive
        {Port, {data, _}} -> ps_status(Port);
        {Port, {exit_status, 0}} -> true;
        {Port, {exit_status, 1}} -> false
    after 5000 -> error(fixture_ps_timeout)
    end.

timed_writer(Directory, Open, Gnu) ->
    Modes = case Gnu of true -> [cleanup, gnu]; false -> [cleanup] end,
    with_patch(Modes, fun() -> timed_writer_impl(Directory, Open) end).

timed_writer_impl(Directory, Open) ->
    Parent = self(),
    Tag = make_ref(),
    ?MODULE = ets:new(?MODULE, [named_table, protected]),
    {Owner, OwnerMonitor} = spawn_monitor(fun() ->
        {ok, {persistent_set, _, _, Guardian, _, _}} = Open(),
        Ref = make_ref(),
        Guardian ! {acquire_snapshot, self(), Ref},
        receive
            {Ref, {ok, {Private, _}}} ->
                Parent ! {Tag, acquired, Guardian, Private},
                Python = os:find_executable("python3"),
                %% Both files are bounded. The second write would occur
                %% after the 30s production deadline if the child survived.
                Code = "import os,sys,time; "
                    "open(sys.argv[1]+'/snapshot.dets','wb').write(b'initial'); "
                    "open(sys.argv[1]+'/metadata-source','w').write(str(os.getpid())); "
                    "time.sleep(45); "
                    "open(sys.argv[2],'wb').write(b'late-write')",
                Late = filename:join(Directory, <<"late-write">>),
                Guardian ! {{metadata_tool, Python,
                    ["-c", Code, Private, Late], text}, self(), make_ref()},
                receive stop -> ok end
        end
    end),
    try
        receive
            {Tag, acquired, Guardian, Private} ->
                GuardianMonitor = monitor(process, Guardian),
                try
                    Pid = await_writer(Private,
                        erlang:monotonic_time(millisecond) + 10000),
                    ets:insert(?MODULE, {Private, self(), Tag, Pid}),
                    exit(Owner, kill),
                    await_down(OwnerMonitor, Owner, 5000),
                    receive
                        {Tag, cleanup_barrier, Guardian, Private, Dead, Exists} ->
                            try
                                true = Dead,
                                true = Exists,
                                true = is_process_alive(Guardian)
                            after Guardian ! {Tag, continue}
                            end
                    after 40000 -> error(fixture_tool_deadline_timeout)
                    end,
                    await_down(GuardianMonitor, Guardian, 5000),
                    false = filelib:is_dir(Private),
                    false = filelib:is_file(
                        filename:join(Directory, <<"late-write">>)),
                    nil
                after demonitor(GuardianMonitor, [flush])
                end;
            {'DOWN', OwnerMonitor, process, Owner, Reason} ->
                error({fixture_owner_failed, Reason})
        after 10000 -> error(fixture_acquire_timeout)
        end
    after
        exit(Owner, kill),
        demonitor(OwnerMonitor, [flush]),
        ets:delete(?MODULE)
    end.

await_writer(Directory, Deadline) ->
    case file:read_file(filename:join(Directory, <<"metadata-source">>)) of
        {ok, Binary} when byte_size(Binary) > 0 ->
            binary_to_integer(Binary);
        _ ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 5 -> await_writer(Directory, Deadline) end;
                false -> error(fixture_writer_start_timeout)
            end
    end.

await_down(Monitor, Pid, Timeout) ->
    receive {'DOWN', Monitor, process, Pid, _} -> ok
    after Timeout -> error(fixture_process_shutdown_timeout)
    end.
