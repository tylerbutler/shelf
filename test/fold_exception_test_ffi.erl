-module(fold_exception_test_ffi).
-export([with_directory/1, finally/2, assert_propagates/2, fail/1,
         deleted_table/1]).

with_directory(Fun) ->
    Directory = filename:join(<<"/tmp">>, iolist_to_binary([
        "shelf_fold_", os:getpid(), "_",
        integer_to_list(erlang:unique_integer([positive, monotonic]))])),
    %% Failure to acquire must never lead to deleting someone else's files.
    ok = file:make_dir(Directory),
    try
        ok = file:change_mode(Directory, 8#700),
        Fun(Directory)
    after
        ok = file:del_dir_r(Directory)
    end.

finally(Cleanup, Fun) ->
    try Fun()
    after Cleanup()
    end.

%% Record the actual callback exception, including compiler-generated Gleam
%% panic/assert stacks. The fold must propagate precisely that same triple.
assert_propagates(Run, Callback) ->
    Tag = make_ref(),
    Self = self(),
    Wrapped = fun() ->
        try Callback()
        catch Class:Reason:Stack ->
            Self ! {Tag, {raised, Class, Reason, Stack}},
            erlang:raise(Class, Reason, Stack)
        end
    end,
    Actual = try Run(Wrapped) of
        Value -> {returned, Value}
    catch Class:Reason:Stack -> {raised, Class, Reason, Stack}
    end,
    receive
        {Tag, Expected} when Expected =:= Actual -> nil;
        {Tag, Expected} -> error({exception_changed, Expected, Actual})
    after 0 ->
        error({callback_did_not_raise, Actual})
    end.

fail(native_error) -> error({callback_error, <<"original">>});
fail(badarg) -> error(badarg);
fail(throw) -> throw({callback_throw, <<"original">>});
fail(exit) -> exit({callback_exit, <<"original">>}).

deleted_table(Fun) ->
    Table = ets:new(shelf_fold_deleted, [set, protected]),
    true = ets:delete(Table),
    Fun(Table).
