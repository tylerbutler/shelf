import gleam/dynamic/decode
import gleam/erlang/process.{type Pid}
import gleam/string
import guardian_test
import shelf.{type ShelfError}
import shelf/bag
import shelf/duplicate_bag
import shelf/internal
import shelf/set
import test_helper

@external(erlang, "close_test_ffi", "with_close_recovery_fixture")
fn with_close_recovery_fixture(fun: fn(String) -> a) -> a

@external(erlang, "close_test_ffi", "dets_reference_for_path")
fn dets_reference_for_path(path: String) -> internal.DetsReference

@external(erlang, "close_test_ffi", "dets_is_closed")
fn dets_is_closed(dets: internal.DetsReference) -> Bool

@external(erlang, "close_test_ffi", "registry_contains_path")
fn registry_contains_path(path: String) -> Bool

// Run the same lifecycle assertions through each public typed table API.
type TableOperations(table) {
  TableOperations(
    with_table: fn(String, fn(table) -> Result(Nil, ShelfError)) ->
      Result(Nil, ShelfError),
    open: fn(String) -> Result(table, ShelfError),
    insert: fn(table, String, String) -> Result(Nil, ShelfError),
    size: fn(table) -> Result(Int, ShelfError),
    save: fn(table) -> Result(Nil, ShelfError),
    close: fn(table) -> Result(Nil, ShelfError),
    guardian: fn(table) -> Pid,
  )
}

fn set_operations() -> TableOperations(set.PersistentSet(String, String)) {
  TableOperations(
    with_table: fn(path, callback) {
      set.with_table(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
        fun: callback,
      )
    },
    open: fn(path) {
      set.open(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
      )
    },
    insert: set.insert,
    size: set.size,
    save: set.save,
    close: set.close,
    guardian: guardian_test.extract_guardian_set,
  )
}

fn bag_operations() -> TableOperations(bag.PersistentBag(String, String)) {
  TableOperations(
    with_table: fn(path, callback) {
      bag.with_table(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
        fun: callback,
      )
    },
    open: fn(path) {
      bag.open(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
      )
    },
    insert: bag.insert,
    size: bag.size,
    save: bag.save,
    close: bag.close,
    guardian: guardian_test.extract_guardian_bag,
  )
}

fn duplicate_bag_operations() -> TableOperations(
  duplicate_bag.PersistentDuplicateBag(String, String),
) {
  TableOperations(
    with_table: fn(path, callback) {
      duplicate_bag.with_table(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
        fun: callback,
      )
    },
    open: fn(path) {
      duplicate_bag.open(
        "error_handling",
        path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.string,
      )
    },
    insert: duplicate_bag.insert,
    size: duplicate_bag.size,
    save: duplicate_bag.save,
    close: duplicate_bag.close,
    guardian: guardian_test.extract_guardian_duplicate_bag,
  )
}

pub fn catches_panics_and_still_closes_the_table_test() -> Nil {
  let path = "/tmp/shelf_eh_panic.dets"
  test_helper.cleanup(path)
  let captured = process.new_subject()
  let result =
    set.with_table(
      "eh_panic",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
      fun: fn(table) {
        let guardian = guardian_test.extract_guardian_set(table)
        process.send(captured, #(table, guardian, process.monitor(guardian)))
        panic as "intentional panic for test"
      },
    )
  let assert Error(shelf.ErlangError(detail)) = result
  assert string.contains(detail, "intentional panic for test")
  let assert Ok(#(original, guardian, monitor)) =
    process.receive(captured, within: 1000)
  let assert Error(shelf.TableClosed) = set.size(original)
  test_helper.await_guardian(monitor, guardian)
  let assert Ok(table) = set_operations().open(path)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn preserves_panic_detail_when_final_close_also_fails_test() -> Nil {
  let directory = "/tmp/shelf_eh_panic_close_failure"
  let path = directory <> "/table.dets"
  test_helper.prepare_retry_directory(directory, path)
  let operations = set_operations()
  let captured = process.new_subject()
  let result =
    operations.with_table(path, fn(table) {
      let assert Ok(Nil) = set.insert(table, "key", "unsaved")
      let guardian = operations.guardian(table)
      let monitor = process.monitor(guardian)
      test_helper.make_directory_read_only(directory)
      let save_result = set.save(table)
      process.send(captured, #(table, guardian, monitor, save_result))
      panic as "panic takes precedence over failed final save"
    })
  test_helper.make_directory_writable(directory)
  let assert Ok(#(original, guardian, monitor, save_result)) =
    process.receive(captured, within: 1000)
  let assert Error(shelf.ErlangError(save_detail)) = save_result
  assert string.contains(save_detail, "eacces")
  let assert Error(shelf.ErlangError(panic_detail)) = result
  assert string.contains(
    panic_detail,
    "panic takes precedence over failed final save",
  )
  let assert Error(shelf.TableClosed) = set.size(original)
  test_helper.await_guardian(monitor, guardian)
  let assert Ok(reopened) = operations.open(path)
  let assert Ok(0) = set.size(reopened)
  let assert Ok(Nil) = set.close(reopened)
  test_helper.cleanup_retry_directory(directory, path)
}

pub fn propagates_close_error_when_callback_succeeds_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_set_success",
    set_operations(),
    Ok(Nil),
  )
}

pub fn returns_callback_error_over_close_error_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_set_error",
    set_operations(),
    Error(shelf.NotFound),
  )
}

pub fn bag_propagates_final_close_error_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_bag_success",
    bag_operations(),
    Ok(Nil),
  )
}

pub fn bag_preserves_callback_error_after_failed_close_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_bag_error",
    bag_operations(),
    Error(shelf.NotFound),
  )
}

pub fn duplicate_bag_propagates_final_close_error_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_duplicate_bag_success",
    duplicate_bag_operations(),
    Ok(Nil),
  )
}

pub fn duplicate_bag_preserves_callback_error_after_failed_close_test() -> Nil {
  assert_failed_final_close(
    "/tmp/shelf_eh_duplicate_bag_error",
    duplicate_bag_operations(),
    Error(shelf.NotFound),
  )
}

fn assert_failed_final_close(
  directory: String,
  operations: TableOperations(table),
  callback_result: Result(Nil, ShelfError),
) -> Nil {
  let path = directory <> "/table.dets"
  test_helper.prepare_retry_directory(directory, path)
  let captured = process.new_subject()
  let result =
    operations.with_table(path, fn(table) {
      let assert Ok(Nil) = operations.insert(table, "key", "unsaved")
      let guardian = operations.guardian(table)
      let monitor = process.monitor(guardian)
      test_helper.make_directory_read_only(directory)
      // Confirm this user actually cannot save. The final close attempts the
      // same save without any intervening permission or data changes.
      let save_result = operations.save(table)
      process.send(captured, #(table, guardian, monitor, save_result))
      callback_result
    })

  // Restore permissions before any assertion can fail.
  test_helper.make_directory_writable(directory)
  let assert Ok(#(original, guardian, monitor, save_result)) =
    process.receive(captured, within: 1000)
  let assert Error(shelf.ErlangError(detail)) = save_result
  assert string.contains(detail, "eacces")
  case callback_result {
    Ok(Nil) -> {
      assert result == save_result
    }
    Error(error) -> {
      assert result == Error(error)
    }
  }

  // Reopening alone missed the bug: DETS can reuse the still-open name.
  let assert Error(shelf.TableClosed) = operations.size(original)
  let assert Error(shelf.TableClosed) = operations.close(original)
  test_helper.await_guardian(monitor, guardian)
  let assert Ok(reopened) = operations.open(path)
  let assert Ok(0) = operations.size(reopened)
  let assert Ok(Nil) = operations.insert(reopened, "key", "persisted")
  let assert Ok(Nil) = operations.close(reopened)
  let assert Ok(reloaded) = operations.open(path)
  let assert Ok(1) = operations.size(reloaded)
  let assert Ok(Nil) = operations.close(reloaded)
  test_helper.cleanup_retry_directory(directory, path)
}

pub fn closed_set_does_not_clean_up_reopened_table_test() -> Nil {
  assert_reopened_table_survives(
    "/tmp/shelf_eh_reused_set.dets",
    set_operations(),
  )
}

pub fn set_removes_registry_entry_after_recovery_reopen_fails_test() -> Nil {
  assert_cleanup_after_recovery_reopen_fails(set_operations())
}

pub fn bag_removes_registry_entry_after_recovery_reopen_fails_test() -> Nil {
  assert_cleanup_after_recovery_reopen_fails(bag_operations())
}

pub fn duplicate_bag_removes_registry_entry_after_recovery_reopen_fails_test() -> Nil {
  assert_cleanup_after_recovery_reopen_fails(duplicate_bag_operations())
}

fn assert_cleanup_after_recovery_reopen_fails(
  operations: TableOperations(table),
) -> Nil {
  use path <- with_close_recovery_fixture()
  let captured = process.new_subject()
  let result =
    operations.with_table(path, fn(table) {
      let assert Ok(Nil) = operations.insert(table, "key", "unsaved")
      let guardian = operations.guardian(table)
      let monitor = process.monitor(guardian)
      let dets = dets_reference_for_path(path)
      assert !dets_is_closed(dets)
      // The temp snapshot can succeed, but replacing the original pathname
      // with a directory makes both rename and recovery reopen fail.
      let assert Ok(Nil) = test_helper.delete_file(path)
      test_helper.create_directory(path)
      process.send(captured, #(table, guardian, monitor, dets))
      Ok(Nil)
    })
  let assert Error(shelf.ErlangError(detail)) = result
  assert string.contains(detail, "eisdir")
  let assert Ok(#(original, guardian, monitor, dets)) =
    process.receive(captured, within: 1000)
  assert dets_is_closed(dets)
  let assert Error(shelf.TableClosed) = operations.size(original)
  test_helper.await_guardian(monitor, guardian)
  // Check before any reopen can hide the orphaned registry entry.
  assert !registry_contains_path(path)

  test_helper.delete_directory(path)
  let assert Ok(reopened) = operations.open(path)
  let assert Ok(Nil) = operations.insert(reopened, "key", "persisted")
  let assert Ok(Nil) = operations.close(reopened)
  assert !registry_contains_path(path)
}

pub fn closed_bag_does_not_clean_up_reopened_table_test() -> Nil {
  assert_reopened_table_survives(
    "/tmp/shelf_eh_reused_bag.dets",
    bag_operations(),
  )
}

pub fn closed_duplicate_bag_does_not_clean_up_reopened_table_test() -> Nil {
  assert_reopened_table_survives(
    "/tmp/shelf_eh_reused_duplicate_bag.dets",
    duplicate_bag_operations(),
  )
}

fn assert_reopened_table_survives(
  path: String,
  operations: TableOperations(table),
) -> Nil {
  test_helper.cleanup(path)
  let captured = process.new_subject()
  let result =
    operations.with_table(path, fn(original) {
      let guardian = operations.guardian(original)
      let monitor = process.monitor(guardian)
      let assert Ok(Nil) = operations.close(original)
      test_helper.await_guardian(monitor, guardian)
      let assert Ok(reopened) = operations.open(path)
      let assert Ok(Nil) = operations.insert(reopened, "key", "value")
      process.send(captured, reopened)
      Ok(Nil)
    })
  let assert Error(shelf.TableClosed) = result
  let assert Ok(reopened) = process.receive(captured, within: 1000)
  assert registry_contains_path(path)
  // ETS alone could still work even if cleanup closed the reused DETS name.
  let assert Ok(Nil) = operations.save(reopened)
  let guardian = operations.guardian(reopened)
  let monitor = process.monitor(guardian)
  let assert Ok(Nil) = operations.close(reopened)
  test_helper.await_guardian(monitor, guardian)
  let assert Ok(reloaded) = operations.open(path)
  let assert Ok(1) = operations.size(reloaded)
  let assert Ok(Nil) = operations.close(reloaded)
  test_helper.cleanup(path)
}

pub fn type_mismatch_contains_decode_error_details_test() -> Nil {
  let path = "/tmp/shelf_eh_tm_detail.dets"
  test_helper.cleanup(path)
  let assert Ok(table) = set_operations().open(path)
  let assert Ok(Nil) = set.insert(table, "key", "hello")
  let assert Ok(Nil) = set.close(table)
  let assert Error(shelf.TypeMismatch(errors)) =
    set.open(
      name: "eh_tm_detail_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  assert errors != []
  test_helper.cleanup(path)
}

pub fn delete_file_normalizes_success_test() -> Nil {
  let path = "/tmp/shelf_eh_delete_success.dets"
  test_helper.cleanup(path)
  let assert Ok(table) = set_operations().open(path)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(Nil) = test_helper.delete_file(path)
  let assert Error(test_helper.FileNotFound) = test_helper.delete_file(path)
  Nil
}

pub fn cleanup_ignores_only_missing_files_test() -> Nil {
  let path = "/tmp/shelf_eh_delete_missing.dets"
  test_helper.cleanup(path)
  let assert Error(test_helper.FileNotFound) = test_helper.delete_file(path)
  test_helper.cleanup(path)
}

pub fn delete_file_and_cleanup_report_other_errors_test() -> Nil {
  let directory = "/tmp/shelf_eh_delete_directory"
  test_helper.create_directory(directory)
  let delete_result = test_helper.delete_file(directory)
  let cleanup_result = internal.rescue(fn() { test_helper.cleanup(directory) })
  test_helper.delete_directory(directory)
  let assert Error(test_helper.FileDeleteFailed(detail)) = delete_result
  assert string.contains(detail, directory)
  let assert Error(assertion_detail) = cleanup_result
  assert string.contains(assertion_detail, "Failed to clean up")
  assert string.contains(assertion_detail, directory)
}

pub fn delete_file_reports_actual_permission_failure_test() -> Nil {
  let directory = "/tmp/shelf_eh_delete_permission"
  let path = directory <> "/table.dets"
  test_helper.prepare_retry_directory(directory, path)
  let assert Ok(table) = set_operations().open(path)
  let assert Ok(Nil) = set.close(table)
  test_helper.make_directory_read_only(directory)
  let result = test_helper.delete_file(path)
  test_helper.make_directory_writable(directory)
  test_helper.cleanup_retry_directory(directory, path)
  let assert Error(test_helper.FileDeleteFailed(detail)) = result
  assert string.contains(detail, "eacces")
  assert string.contains(detail, path)
}
