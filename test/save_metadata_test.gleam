import gleam/dynamic/decode
import gleam/list
import gleam/string
import shelf
import shelf/internal
import shelf/set
import storage_safety_test
import unitest

@external(erlang, "save_metadata_test_ffi", "with_handle")
fn with_handle(table: set.PersistentSet(k, v), fun: fn() -> a) -> a

@external(erlang, "save_metadata_test_ffi", "assert_closed")
fn assert_closed(table: set.PersistentSet(k, v)) -> Nil

@external(erlang, "save_metadata_test_ffi", "metadata")
fn metadata(path: String) -> #(Int, Int, Int)

@external(erlang, "save_metadata_test_ffi", "prepare_metadata")
fn prepare_metadata(path: String, mode: Int) -> #(Int, Int, Int)

@external(erlang, "save_metadata_test_ffi", "with_missing_original")
fn with_missing_original(path: String, fun: fn() -> a) -> a

@external(erlang, "save_metadata_test_ffi", "prepare_group_failure")
fn prepare_group_failure(directory: String, path: String) -> Bool

fn open(directory: String) -> set.PersistentSet(String, Int) {
  let assert Ok(table) =
    set.open_config(
      shelf.config("save_metadata", "table.dets", base_directory: directory),
      decode.string,
      decode.int,
    )
  table
}

fn preserves_metadata(mode: Int) -> Nil {
  use directory <- storage_safety_test.with_directory()
  let path = directory <> "/table.dets"
  let table = open(directory)
  use <- with_handle(table)
  let original = prepare_metadata(path, mode)
  assert original.0 == mode
  list.each([1, 2, 3], fn(value) {
    let assert Ok(Nil) = set.insert(table, "key", value)
    let assert Ok(Nil) = set.save(table)
    assert metadata(path) == original
    let assert Ok(Nil) = set.reload(table)
    assert set.lookup(table, "key") == Ok(value)
  })
  let assert Ok(Nil) = set.insert(table, "key", 4)
  let assert Ok(Nil) = set.close(table)
  assert metadata(path) == original
  let reopened = open(directory)
  use <- with_handle(reopened)
  assert set.lookup(reopened, "key") == Ok(4)
  let assert Ok(Nil) = set.close(reopened)
  assert metadata(path) == original
}

pub fn restricted_mode_survives_save_and_close_test() -> Nil {
  use <- unitest.tag("save_metadata")
  preserves_metadata(0o600)
}

pub fn nondefault_modes_and_ownership_survive_save_and_close_test() -> Nil {
  use <- unitest.tag("save_metadata")
  list.each([0o640, 0o660, 0o750, 0o2700], preserves_metadata)
}

pub fn metadata_read_failure_preserves_persisted_data_and_allows_retry_test() -> Nil {
  use <- unitest.tag("save_metadata")
  use directory <- storage_safety_test.with_directory()
  let path = directory <> "/table.dets"
  let table = open(directory)
  use <- with_handle(table)
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.save(table)
  let original = prepare_metadata(path, 0o600)
  let persisted = storage_safety_test.read_file(path)
  let assert Ok(Nil) = set.insert(table, "key", 2)
  with_missing_original(path, fn() {
    let assert Error(shelf.FileError(detail)) = set.save(table)
    assert string.contains(detail, "native_metadata")
    assert string.contains(detail, "read_original")
    assert string.contains(detail, "enoent")
    let assert Error(shelf.FileError(close_detail)) = set.close(table)
    assert string.contains(close_detail, "native_metadata")
    assert set.lookup(table, "key") == Ok(2)
  })
  assert storage_safety_test.list_directory(directory) == ["table.dets"]
  assert metadata(path) == original
  assert storage_safety_test.read_file(path) == persisted
  // Reload before retry: prove the prior persisted snapshot was not replaced.
  let assert Ok(Nil) = set.reload(table)
  assert set.lookup(table, "key") == Ok(1)
  let assert Ok(Nil) = set.insert(table, "key", 3)
  let assert Ok(Nil) = set.save(table)
  assert metadata(path) == original
  let assert Ok(Nil) = set.close(table)
  let reopened = open(directory)
  use <- with_handle(reopened)
  assert set.lookup(reopened, "key") == Ok(3)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn metadata_owner_write_failure_preserves_data_and_allows_retry_test() -> Nil {
  use <- unitest.tag("save_metadata")
  use directory <- storage_safety_test.with_directory()
  let path = directory <> "/table.dets"
  let table = open(directory)
  use <- with_handle(table)
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.save(table)
  let original = metadata(path)
  let persisted = storage_safety_test.read_file(path)
  // Only run where a real native ownership failure has been probed.
  use <- unitest.guard(prepare_group_failure(directory, path))
  let assert Ok(Nil) = set.insert(table, "key", 2)
  let assert Error(shelf.FileError(detail)) = set.save(table)
  assert string.contains(detail, "native_metadata")
  assert string.contains(detail, "apply_owner")
  assert string.contains(detail, "eperm")
  let assert Error(shelf.FileError(close_detail)) = set.close(table)
  assert string.contains(close_detail, "native_metadata")
  assert metadata(path) == original
  assert storage_safety_test.read_file(path) == persisted
  assert storage_safety_test.list_directory(directory) == ["table.dets"]
  assert set.lookup(table, "key") == Ok(2)
  let assert Ok(Nil) = set.reload(table)
  assert set.lookup(table, "key") == Ok(1)
  // Resolve the actual group-permission problem, then retry the same handle.
  let retry_metadata = prepare_metadata(path, 0o600)
  let assert Ok(Nil) = set.insert(table, "key", 3)
  let assert Ok(Nil) = set.save(table)
  assert metadata(path) == retry_metadata
  let assert Ok(Nil) = set.close(table)
  let reopened = open(directory)
  use <- with_handle(reopened)
  assert set.lookup(reopened, "key") == Ok(3)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn scoped_handles_shut_down_before_assertion_failure_escapes_test() -> Nil {
  use <- unitest.tag("save_metadata")
  use directory <- storage_safety_test.with_directory()
  let table = open(directory)
  let assert Error(_) =
    internal.rescue(fn() {
      use <- with_handle(table)
      // Include a save so the native server differs from the opening one.
      let assert Ok(Nil) = set.save(table)
      // Deliberately fail a Gleam assertion while both handles are live.
      assert set.lookup(table, "not_inserted") == Ok(1)
    })
  assert_closed(table)
  let reopened = open(directory)
  use <- with_handle(reopened)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}
