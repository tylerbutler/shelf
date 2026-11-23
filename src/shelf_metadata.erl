%% Tool-backed macOS protection metadata. No file data is copied to disk.
%% bsdtar's complete stream is checked; only bounded AppleDouble/PAX records
%% are retained. Data bodies are discarded as they arrive.
-module(shelf_metadata).
-include_lib("kernel/include/file.hrl").
-export([check_platform/1, read/4, prepare_directory/2, apply/4, run/6,
         cleanup_directory/1, verify/5]).

-define(META_LIMIT, 1048576).
-define(TIMEOUT, 30000).

check_platform(Path) ->
    case os:type() of
        {unix, darwin} ->
            lists:foreach(fun(Name) -> executable(Path, Name) end,
                [ls, chmod, xattr, stat, chflags, bsdtar, df, timeout]),
            ok;
        _ -> metadata_error(Path, platform, unsupported_platform)
    end.

tool(ls) -> "/bin/ls";
tool(chmod) -> "/bin/chmod";
tool(xattr) -> "/usr/bin/xattr";
tool(stat) -> "/usr/bin/stat";
tool(chflags) -> "/usr/bin/chflags";
tool(bsdtar) -> "/usr/bin/bsdtar";
tool(df) -> "/bin/df";
tool(timeout) -> "/usr/bin/timeout".

executable(Path, timeout) ->
    case timeout_executable() of
        {ok, Executable} -> Executable;
        error -> metadata_error(Path, tools, {unavailable_tool, timeout})
    end;
executable(Path, Name) ->
    Expected = tool(Name),
    case os:find_executable(atom_to_list(Name)) of
        Expected -> Expected;
        _ -> metadata_error(Path, tools, {unavailable_tool, Name})
    end.

%% GNU coreutils >=9.0 has the required foreground signal-masking/waitpid
%% barrier too. Trust only Homebrew's standard prefix and versioned Cellar
%% binary, never an arbitrary gtimeout found through PATH.
timeout_executable() ->
    case os:find_executable(tool(timeout)) of
        false -> homebrew_timeout(["/opt/homebrew", "/usr/local"]);
        Native -> {ok, Native}
    end.

homebrew_timeout([]) -> error;
homebrew_timeout([Prefix | Rest]) ->
    Link = filename:join([Prefix, "bin", "gtimeout"]),
    case file:read_link(Link) of
        {ok, Target} ->
            case filename:split(Target) of
                ["..", "Cellar", "coreutils", Version, "bin", "gtimeout"] ->
                    Canonical = filename:join(
                        [Prefix, "Cellar", "coreutils", Version, "bin", "gtimeout"]),
                    case supported_coreutils(Version) andalso
                            regular_executable(Canonical) of
                        true -> {ok, Canonical};
                        false -> homebrew_timeout(Rest)
                    end;
                _ -> homebrew_timeout(Rest)
            end;
        {error, _} -> homebrew_timeout(Rest)
    end.

supported_coreutils(Version) ->
    case re:run(Version, "^([0-9]+)\\.([0-9]+)(?:_[0-9]+)?$",
            [{capture, [1, 2], list}]) of
        {match, [Major, Minor]} ->
            {list_to_integer(Major), list_to_integer(Minor)} >= {9, 0};
        nomatch -> false
    end.

regular_executable(Path) ->
    case file:read_link_info(Path) of
        {ok, #file_info{type = regular}} ->
            os:find_executable(Path) =:= Path;
        _ -> false
    end.

metadata_error(Path, Stage, Detail) ->
    error({file_error, Path, {native_metadata, Stage, Detail}}).

command(Guardian, Stage, Path, Name, Args, Consumer) ->
    Executable = executable(Path, Name),
    case request(Guardian, {metadata_tool, Executable, Args, Consumer}) of
        {ok, Output} -> Output;
        {error, Detail} -> metadata_error(Path, Stage, {Name, Detail})
    end.

request(Guardian, Operation) ->
    Reference = monitor(process, Guardian),
    Guardian ! {Operation, self(), Reference},
    receive
        {Reference, Reply} ->
            demonitor(Reference, [flush]),
            Reply;
        {'DOWN', Reference, process, Guardian, Reason} ->
            exit({shelf_guardian_failed, Reason})
    end.

text(G, Stage, Path, Tool, Args) ->
    command(G, Stage, Path, Tool, Args, text).

%% Resolve Apple's metadata utilities and a trusted deadline wrapper.
%% Environment variables that alter tar/ls
%% semantics are removed, rather than inheriting user archive policy.
environment(Directory) ->
    [{"LC_ALL", "C"}, {"LANG", "C"},
     {"TMPDIR", unicode:characters_to_list(Directory)},
     {"COPYFILE_DISABLE", false},
     {"COPYFILE_SYSTEM", false}, {"TAR_OPTIONS", false},
     {"TAR_READER_OPTIONS", false}, {"TAR_WRITER_OPTIONS", false},
     {"CLICOLOR", false}, {"CLICOLOR_FORCE", false}, {"LS_COLWIDTHS", false}].

%% Runs in the existing reservation guardian, which owns both the snapshot
%% and port. It cannot start cleanup while a tool still holds that snapshot.
%% These utilities run without shells, filters, recursion or child commands.
run(Owner, Monitor, Executable, Args, Consumer, Directory) ->
    State = initial(Consumer),
    %% The trusted timeout utility is the OS parent of the actual tool.
    %% --foreground is essential: SIGKILL must not kill the wrapper before
    %% it has reaped its direct child. No command here spawns descendants.
    Wrapped = ["--foreground", "--signal=KILL", "30", Executable | Args],
    case start_port(Wrapped, Directory) of
        {error, _} = Error -> Error;
        {ok, Port} ->
            Deadline = erlang:monotonic_time(millisecond) + ?TIMEOUT,
            try collect(Port, Owner, Monitor, Deadline, State, pending, false) of
                {exited, 0, FinalState} ->
                    try {ok, complete(FinalState)}
                    catch throw:{metadata_tool, Detail} -> {error, Detail}
                    end;
                {exited, Status, _} -> {error, {exit_status, Status}};
                {error, _} = ToolError -> ToolError
            after
                %% The child has exited before this close (including errors).
                try port_close(Port) catch error:badarg -> ok end,
                flush_port(Port)
            end
    end.

consume_guarded(Port, Status, Eof, State, Data) ->
    try {ok, consume(State, Data)}
    catch
        throw:{metadata_tool, Detail} ->
            await_completion(Port, Status, Eof),
            {error, Detail};
        Class:Reason:Stack ->
            %% Cleanup on defects too, but never turn them into success or
            %% a recoverable metadata error.
            await_completion(Port, Status, Eof),
            erlang:raise(Class, Reason, Stack)
    end.

start_port(Args, Directory) ->
    case timeout_executable() of
        error -> {error, {unavailable_tool, timeout}};
        {ok, Executable} -> start_port(Executable, Args, Directory)
    end.

start_port(Executable, Args, Directory) ->
    try open_port({spawn_executable, Executable},
            [binary, exit_status, use_stdio, stderr_to_stdout, eof,
             {env, environment(Directory)}, {args, Args}]) of
        Port -> {ok, Port}
    catch
        error:Reason when Reason =:= enoent; Reason =:= eacces;
                          Reason =:= system_limit; Reason =:= eagain ->
            {error, {start_tool, Reason}}
    end.

initial(text) -> {text, <<>>};
initial({archive, Size, Name, Type}) ->
    {archive, Size + 2 * ?META_LIMIT, 0,
     {header, <<>>, #{name => Name, type => Type, size => Size,
                     target => false, sidecar => none, headers => 0}}}.

collect(_Port, _Owner, _Monitor, _Deadline, State, Status, true)
        when is_integer(Status) ->
    {exited, Status, State};
collect(Port, Owner, Monitor, Deadline, State, Status, Eof) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} ->
            case consume_guarded(Port, Status, Eof, State, Data) of
                {ok, Next} ->
                    collect(Port, Owner, Monitor, Deadline, Next, Status, Eof);
                {error, _} = Error -> Error
            end;
        {Port, eof} ->
            collect(Port, Owner, Monitor, Deadline, State, Status, true);
        {Port, {exit_status, ExitStatus}} ->
            collect(Port, Owner, Monitor, Deadline, State, ExitStatus, Eof);
        {'DOWN', Monitor, process, Owner, Reason} = Down ->
            %% Put this exact monitor event back for guard_reservation/5,
            %% but only after its child has stopped touching the snapshot.
            await_completion(Port, Status, Eof),
            self() ! Down,
            _ = Reason,
            {error, owner_exited}
    after Remaining ->
        await_completion(Port, Status, Eof),
        {error, timeout}
    end.

await_completion(_Port, Status, true) when is_integer(Status) -> ok;
await_completion(Port, Status, Eof) ->
    %% Discard rather than capture after cancellation/overflow. The wrapper
    %% enforces the deadline and waits for its child, avoiding PID-reuse
    %% races in an Erlang-side "kill <pid>". Uninterruptible kernel I/O can
    %% delay this barrier; never unlink/reuse the pathname during that wait.
    receive
        {Port, {data, _}} -> await_completion(Port, Status, Eof);
        {Port, eof} -> await_completion(Port, Status, true);
        {Port, {exit_status, ExitStatus}} ->
            await_completion(Port, ExitStatus, Eof)
    end.

flush_port(Port) ->
    receive {Port, _} -> flush_port(Port)
    after 0 -> ok
    end.

fail(Detail) -> throw({metadata_tool, Detail}).
require(true) -> ok;
require(false) -> fail(unsupported_format).

require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

consume({text, Output}, Data) ->
    require(byte_size(Output) + byte_size(Data) =< ?META_LIMIT),
    {text, <<Output/binary, Data/binary>>};
consume({archive, Limit, Count, State}, Data) ->
    require(Count + byte_size(Data) =< Limit, archive_limit),
    {archive, Limit, Count + byte_size(Data), tar(State, Data)}.

complete({text, Output}) -> Output;
complete({archive, _, _, {trailer, Zeros, Info}}) when Zeros >= 1024 ->
    require(Zeros rem 512 =:= 0, archive_trailer_size),
    require(maps:get(target, Info), archive_missing_target),
    maps:get(sidecar, Info);
complete(_) -> fail(incomplete_archive).

%% Strict ustar/PAX framing, including checksums, exact body lengths,
%% padding, and the complete end-of-archive trailer. No prefix acceptance.
tar(State, <<>>) -> State;
tar({header, Buffer, Info}, Data) when byte_size(Buffer) + byte_size(Data) < 512 ->
    {header, <<Buffer/binary, Data/binary>>, Info};
tar({header, Buffer, Info}, Data) ->
    Needed = 512 - byte_size(Buffer),
    <<Part:Needed/binary, Rest/binary>> = Data,
    Header = <<Buffer/binary, Part/binary>>,
    case Header =:= <<0:4096>> of
        true -> tar({trailer, 512, Info}, Rest);
        false ->
            <<_:148/binary, Check:8/binary, _:356/binary>> = Header,
            <<Before:148/binary, _:8/binary, After/binary>> = Header,
            require(octal(Check) =:= lists:sum(binary_to_list(
                <<Before/binary, "        ", After/binary>>)), archive_checksum),
            <<Name:100/binary, _:24/binary, SizeField:12/binary,
              _:20/binary, Type, Link:100/binary, Magic:6/binary,
              Version:2/binary, _:80/binary, Prefix:155/binary, _:12/binary>> = Header,
            require(Magic =:= <<"ustar", 0>> andalso Version =:= <<"00">>,
                archive_header),
            require(Link =:= <<0:800>> andalso Prefix =:= <<0:1240>>,
                archive_path_header),
            Size = octal(SizeField),
            N = maps:get(headers, Info) + 1,
            require(N =< 8, archive_header_limit),
            {Kind, Updated} = tar_entry(Type, cstring(Name), Size, Info#{headers => N}),
            tar({body, Size, (512 - Size rem 512) rem 512,
                 Kind, [], Updated}, Rest)
    end;
tar({body, 0, Padding, Kind, Chunks, Info}, Data) ->
    Updated = case Kind of
        sidecar -> Info#{sidecar => iolist_to_binary(lists:reverse(Chunks))};
        pax -> pax(iolist_to_binary(lists:reverse(Chunks))), Info;
        discard -> Info
    end,
    tar({padding, Padding, Updated}, Data);
tar({body, Left, Padding, Kind, Chunks, Info}, Data) ->
    Take = min(Left, byte_size(Data)),
    <<Part:Take/binary, Rest/binary>> = Data,
    Next = case Kind of discard -> Chunks; _ -> [binary:copy(Part) | Chunks] end,
    tar({body, Left - Take, Padding, Kind, Next, Info}, Rest);
tar({padding, 0, Info}, Data) -> tar({header, <<>>, Info}, Data);
tar({padding, Left, Info}, Data) ->
    Take = min(Left, byte_size(Data)),
    <<Part:Take/binary, Rest/binary>> = Data,
    require(Part =:= binary:copy(<<0>>, Take), archive_padding),
    tar({padding, Left - Take, Info}, Rest);
tar({trailer, Count, Info}, Data) ->
    require(Data =:= binary:copy(<<0>>, byte_size(Data)), archive_trailer),
    {trailer, Count + byte_size(Data), Info}.

tar_entry($x, _, Size, Info) when Size =< ?META_LIMIT -> {pax, Info};
tar_entry($0, Name, Size, #{name := Name, type := regular,
                          size := Observed, target := false} = Info)
        when Size =< Observed + ?META_LIMIT ->
    %% An open DETS may finish initializing/flushing between our stat and
    %% bsdtar's stat. Framing uses the archive's declared size, not a stale
    %% size observation. The complete stream and total byte cap still apply.
    {discard, Info#{target => true}};
tar_entry($5, Name, 0, #{name := Expected, type := directory,
                       target := false} = Info) ->
    require(Name =:= Expected orelse Name =:= <<Expected/binary, "/">>),
    {discard, Info#{target => true}};
tar_entry($0, Name, Size, #{name := <<"./", Base/binary>>,
                          sidecar := none, target := false} = Info)
        when Size =< ?META_LIMIT ->
    require(Name =:= <<"./._", Base/binary>>, archive_sidecar_name),
    {sidecar, Info};
tar_entry(_, _, _, _) -> fail(unsupported_archive_entry).

octal(Field) ->
    Digits = string:trim(binary_to_list(Field), both, [0, 32]),
    require(Digits =/= [] andalso
        lists:all(fun(C) -> C >= $0 andalso C =< $7 end, Digits), archive_number),
    list_to_integer(Digits, 8).

cstring(Field) ->
    case binary:split(Field, <<0>>) of
        [Value, Tail] ->
            require(Tail =:= binary:copy(<<0>>, byte_size(Tail)), archive_cstring),
            Value;
        [Value] -> Value
    end.

pax(<<>>) -> ok;
pax(Data) ->
    case binary:split(Data, <<" ">>) of
        [Digits, _] when byte_size(Digits) > 0, byte_size(Digits) =< 8 ->
            require(lists:all(fun(C) -> C >= $0 andalso C =< $9 end,
                binary_to_list(Digits)), pax_length),
            Length = binary_to_integer(Digits),
            Prefix = byte_size(Digits) + 1,
            require(Length > Prefix andalso Length =< byte_size(Data), pax_record),
            <<_:Prefix/binary, Record:(Length - Prefix)/binary, Rest/binary>> = Data,
            case binary:split(Record, <<"=">>) of
                [Key, Value] ->
                    require(lists:member(Key,
                        [<<"ctime">>, <<"atime">>, <<"mtime">>,
                         <<"LIBARCHIVE.creationtime">>]), pax_key),
                    require(byte_size(Value) > 0 andalso binary:last(Value) =:= $\n,
                        pax_value),
                    pax(Rest);
                _ -> fail(unsupported_pax)
            end;
        _ -> fail(unsupported_pax)
    end.

read(G, Stage, Path, Directory) ->
    %% df's type filter distinguishes the supported local protection model
    %% from network/translated ACLs. An empty successful listing is rejected.
    local_filesystem(G, Stage, Path),
    Flags = text(G, Stage, Path, stat, ["-f", "%f", Path]),
    case Flags of
        <<"0\n">> -> ok;
        _ -> metadata_error(Path, Stage, unsupported_flags)
    end,
    %% A delete-denying ACE can prevent both atomic replacement and removal
    %% of a metadata hard link. ls DOES display this permission on files.
    %% Reject before acquiring the alias; never weaken the original to clean
    %% it up. Conservatively includes inheritance-only delete denials since
    %% ls cannot distinguish them without the lossless inspector.
    Listing = text(G, Stage, Path, ls, ["-blden", Path]),
    checked(Path, Stage, fun() ->
        case lines(Listing) of
            [_ | Aces] ->
                lists:foreach(fun(Line) ->
                    case binary:split(Line, <<" deny ">>) of
                        [_, Bits] ->
                            case lists:member(<<"delete">>,
                                    binary:split(Bits, <<",">>, [global])) of
                                true -> fail(unsupported_delete_acl);
                                false -> ok
                            end;
                        _ -> ok
                    end
                end, Aces);
            _ -> fail(unsupported_format)
        end
    end),
    %% Bound native packing BEFORE bsdtar can materialize AppleDouble
    %% metadata (resource forks are xattrs too).
    Attributes = attributes(G, Stage, Path),
    %% libarchive packs native metadata into a temporary file beside its
    %% input. A hard link keeps those metadata files inside our ACL-private
    %% staging directory, even when the original's parent has inherited
    %% grants. This is not a data copy and never writes the original inode.
    Link = filename:join(Directory, <<"metadata-source">>),
    case request(G, {metadata_link, Path}) of
        ok -> ok;
        {error, Reason} -> metadata_error(Path, Stage, {metadata_link, Reason})
    end,
    Acl = try acl(G, Stage, Link)
    after
        case request(G, metadata_unlink) of
            ok -> ok;
            {error, Reason2} -> metadata_error(Path, Stage, {metadata_unlink, Reason2})
        end
    end,
    {Acl, Attributes}.

local_filesystem(G, Stage, Path) ->
    Fs = text(G, Stage, Path, df, ["-T", "apfs,hfs", Path]),
    checked(Path, Stage, fun() ->
        require(length(binary:split(Fs, <<"\n">>, [global])) =:= 3)
    end).

verify(G, Stage, Path, Directory, Expected) ->
    case read(G, Stage, Path, Directory) of
        Expected -> ok;
        _ -> metadata_error(Path, Stage, mismatch)
    end.

checked(Path, Stage, Fun) ->
    try Fun()
    catch throw:{metadata_tool, Detail} -> metadata_error(Path, Stage, Detail)
    end.

info(Stage, Path) ->
    case file:read_file_info(Path) of
        {ok, Info} -> Info;
        {error, Reason} -> metadata_error(Path, Stage, Reason)
    end.

acl(G, Stage, Path) ->
    %% ls is an independent entry-count/UUID check, NOT an ACL serializer:
    %% it hides inheritance flags on regular files.
    Listing = text(G, Stage, Path, ls, ["-blden", Path]),
    #file_info{size = Size, type = Type} = info(Stage, Path),
    {Parent, Base} = case Type of
        %% "./." makes libarchive's adjacent metadata tempfile land INSIDE
        %% the verified directory, not in its potentially permissive parent.
        directory -> {Path, <<".">>};
        regular -> {filename:dirname(Path), filename:basename(Path)};
        _ -> metadata_error(Path, Stage, unsupported_file_type)
    end,
    Name = <<"./", Base/binary>>,
    Sidecar = command(G, Stage, Path, bsdtar,
        ["-c", "--format=pax", "--mac-metadata", "--no-acls",
         "--no-xattrs", "--no-fflags", "--no-recursion", "-f", "-",
         "-C", Parent, Name],
        {archive, Size, Name, Type}),
    checked(Path, Stage, fun() ->
        Native = native_acl(Sidecar),
        Entries = acl_entries(Native),
        Lines = case lines(Listing) of
            [_File | Rows] -> Rows;
            _ -> fail(unsupported_format)
        end,
        require(length(Lines) =:= length(Entries)),
        lists:foreach(fun({Line, {Uuid, _}}) ->
            require(binary:match(Line, Uuid) =/= nomatch)
        end, lists:zip(Lines, Entries)),
        Canonical = case Entries of [] -> <<>>; _ -> Native end,
        {Canonical, [Entry || {_, Entry} <- Entries]}
    end).

%% Apple's native AppleDouble ATTR records are length-framed. Retain the
%% ACL text verbatim for verification, rather than using lossy NFSv4 mapping.
native_acl(none) -> <<>>;
native_acl(<<16#00051607:32, 16#00020000:32, _:16/binary, 2:16,
             9:32, 50:32, FinderSize:32, 2:32, Resource:32, RSize:32,
             _:34/binary, "ATTR", _:32, Total:32, Start:32, DataLen:32,
             0:96, 0:16, Count:16, _/binary>> = Data) ->
    require(Resource =:= 50 + FinderSize),
    require(Resource + RSize =:= byte_size(Data)),
    require(Total =:= Resource andalso Start + DataLen =:= Total),
    require(Start >= 120 andalso Start =< Resource andalso Count =< 128),
    attr_records(Data, 120, Start, Count, #{});
native_acl(_) -> fail(unsupported_appledouble).

attr_records(_, Position, Start, 0, Values) ->
    require(Position =< Start),
    maps:get(<<"com.apple.acl.text">>, Values, <<>>);
attr_records(Data, Position, Start, Count, Values) ->
    require(Position + 11 =< Start),
    <<_:Position/binary, Offset:32, Length:32, 0:16, N:8, _/binary>> = Data,
    require(N > 1 andalso Position + 11 + N =< Start),
    <<_:((Position + 11))/binary, NameField:N/binary, _/binary>> = Data,
    require(binary:last(NameField) =:= 0),
    Name = binary:part(NameField, 0, N - 1),
    require(binary:match(Name, <<0>>) =:= nomatch),
    require(not maps:is_key(Name, Values)),
    require(Offset >= Start andalso Offset + Length =< byte_size(Data)),
    Value = binary:copy(binary:part(Data, Offset, Length)),
    Next = Position + ((11 + N + 3) band bnot 3),
    attr_records(Data, Next, Start, Count - 1, Values#{Name => Value}).

acl_entries(<<>>) -> [];
acl_entries(Text) ->
    require(byte_size(Text) =< 32768 andalso binary:last(Text) =:= 0),
    <<Body:(byte_size(Text) - 1)/binary, 0>> = Text,
    case lines(Body) of
        [<<"!#acl 1">> | Entries] when length(Entries) =< 126 ->
            [acl_entry(Entry) || Entry <- Entries];
        _ -> fail(unsupported_acl)
    end.

acl_entry(Line) ->
    case binary:split(Line, <<":">>, [global]) of
        [Kind, Uuid, Name, _Id, Actions, Permissions] ->
            require(Kind =:= <<"user">> orelse Kind =:= <<"group">>),
            require(byte_size(Uuid) =:= 36),
            require(safe_name(Name) andalso binary:match(Name, <<":">>) =:= nomatch),
            [Action | Flags] = binary:split(Actions, <<",">>, [global]),
            require(Action =:= <<"allow">> orelse Action =:= <<"deny">>),
            require(lists:all(fun(F) -> lists:member(F,
                [<<"inherited">>, <<"file_inherit">>, <<"directory_inherit">>,
                 <<"limit_inherit">>, <<"only_inherit">>]) end, Flags)),
            Perms = binary:split(Permissions, <<",">>, [global]),
            require(lists:all(fun(P) -> lists:member(P,
                [<<"read">>, <<"write">>, <<"execute">>, <<"delete">>,
                 <<"append">>, <<"delete_child">>, <<"readattr">>,
                 <<"writeattr">>, <<"readextattr">>, <<"writeextattr">>,
                 <<"readsecurity">>, <<"writesecurity">>, <<"chown">>,
                 <<"list">>, <<"search">>, <<"add_file">>,
                 <<"add_subdirectory">>]) end, Perms)),
            Bits = lists:join(<<",">>, Perms ++ Flags),
            {Uuid, iolist_to_binary([Kind, ":", Name, " ", Action, " ", Bits])};
        _ -> fail(unsupported_acl)
    end.

safe_name(Name) ->
    byte_size(Name) > 0 andalso byte_size(Name) =< 255 andalso
    lists:all(fun(C) -> C >= 32 andalso C =< 126 end, binary_to_list(Name)).

lines(<<>>) -> [];
lines(Data) ->
    require(binary:last(Data) =:= $\n),
    Parts = binary:split(Data, <<"\n">>, [global]),
    lists:sublist(Parts, length(Parts) - 1).

attributes(G, Stage, Path) ->
    Output = text(G, Stage, Path, xattr, [Path]),
    Names = checked(Path, Stage, fun() ->
        Candidates = lines(Output),
        require(length(Candidates) =< 128),
        require(lists:all(fun safe_name/1, Candidates)),
        require(length(lists:usort(Candidates)) =:= length(Candidates)),
        Candidates
    end),
    %% Query lengths without fetching values first. In particular a resource
    %% fork must be bounded before xattr allocates it or copyfile packs it.
    Sizes = text(G, Stage, Path, ls, ["-bdln@", Path]),
    SizeMap = checked(Path, Stage, fun() ->
        Rows = case lines(Sizes) of
            [_Header | Tail] -> Tail;
            _ -> fail(unsupported_attribute_sizes)
        end,
        Sized = [attribute_size(Row) || Row <- Rows],
        require(lists:sort([Name || {Name, _} <- Sized]) =:= lists:sort(Names)),
        require(lists:all(fun({_, Size}) -> Size =< 65536 end, Sized)),
        require(lists:sum([Size || {_, Size} <- Sized]) =< ?META_LIMIT - 65536),
        maps:from_list(Sized)
    end),
    %% xattr prints raw newline-delimited names, even with -x. For each
    %% unique candidate demand an exact-name read. A split name either has
    %% a nonexistent fragment or duplicates the listing of a real fragment.
    Attributes = lists:sort([{Name, checked(Path, Stage, fun() ->
        Hex = text(G, Stage, Path, xattr, ["-px", "--", Name, Path]),
        Digits = [C || C <- binary_to_list(Hex), C =/= 32, C =/= 10],
        require(length(Digits) =< 131072 andalso length(Digits) rem 2 =:= 0),
        require(length(Digits) =:= 2 * maps:get(Name, SizeMap)),
        require(lists:all(fun(C) ->
            (C >= $0 andalso C =< $9) orelse (C >= $A andalso C =< $F)
        end, Digits)),
        list_to_binary(Digits)
    end)} || Name <- Names]),
    checked(Path, Stage, fun() ->
        case lists:sum([byte_size(Hex) || {_, Hex} <- Attributes])
                =< 2 * (?META_LIMIT - 65536) of
            true -> Attributes;
            false -> fail(metadata_too_large)
        end
    end).

attribute_size(Row) ->
    case binary:split(Row, <<"\t">>, [global]) of
        [<<>>, Name, SizeField] ->
            Digits = string:trim(binary_to_list(SizeField), both, " "),
            require(Digits =/= [] andalso length(Digits) =< 10 andalso
                lists:all(fun(C) -> C >= $0 andalso C =< $9 end, Digits)),
            {Name, list_to_integer(Digits)};
        _ -> fail(unsupported_attribute_sizes)
    end.

prepare_directory(G, Directory) ->
    local_filesystem(G, staging_filesystem, Directory),
    _ = text(G, staging_acl, Directory, chmod, ["-N", Directory]),
    case file:change_mode(Directory, 8#700) of
        ok -> ok;
        {error, Reason} -> metadata_error(Directory, staging_mode, Reason)
    end,
    _ = attributes(G, verify_staging, Directory),
    case acl(G, verify_staging, Directory) of
        {<<>>, []} -> ok;
        _ -> metadata_error(Directory, verify_staging, unexpected_acl)
    end,
    #file_info{mode = Mode} = info(verify_staging, Directory),
    case Mode band 8#7777 of
        8#700 -> ok;
        _ -> metadata_error(Directory, verify_staging, mode_mismatch)
    end.

apply(G, Path, {_, Entries}, Attributes) ->
    %% Old snapshot ACLs can deny attribute writes. Strip them only inside
    %% the ACL-private directory; the original is never changed.
    _ = text(G, apply_acl, Path, chmod, ["-N", Path]),
    Existing = attributes(G, read_snapshot, Path),
    lists:foreach(fun({Name, _}) ->
        case lists:keymember(Name, 1, Attributes) of
            true -> ok;
            false -> text(G, remove_attribute, Path, xattr, ["-d", "--", Name, Path])
        end
    end, Existing),
    lists:foreach(fun({Name, Hex}) ->
        text(G, apply_attribute, Path, xattr, ["-wx", "--", Name, Hex, Path])
    end, Attributes),
    lists:foldl(fun(Entry, Index) ->
        text(G, apply_acl, Path, chmod,
            ["+a#", integer_to_list(Index), Entry, Path]),
        Index + 1
    end, 0, Entries),
    _ = text(G, apply_flags, Path, chflags, ["0", Path]),
    ok.

%% Only our own names, inside an exclusively acquired private directory.
%% Called after the guardian's OS-child termination barrier on owner death.
cleanup_directory(Directory) ->
    _ = file:delete(filename:join(Directory, <<"metadata-source">>)),
    case file:list_dir(Directory) of
        {ok, Names} ->
            lists:foreach(fun(Name) ->
                case re:run(Name, "^tar\\.[A-Za-z0-9]{8}$", [{capture, none}]) of
                    match -> _ = file:delete(filename:join(Directory, Name));
                    nomatch -> ok
                end
            end, Names);
        {error, _} -> ok
    end,
    ok.
