import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/string
import shelf
import shelf/set
import storage_safety_test as fixture
import unitest

@external(erlang, "filesystem_alias_test_ffi", "hardlink")
fn hardlink(target: String, alias: String) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "same_identity")
fn same_identity(first: String, second: String) -> Bool

@external(erlang, "filesystem_alias_test_ffi", "delete_file")
fn delete_file(path: String) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "identity_reserved")
fn identity_reserved(path: String) -> Bool

@external(erlang, "filesystem_alias_test_ffi", "snapshot_path")
fn snapshot_path(directory: String) -> String

@external(erlang, "filesystem_alias_test_ffi", "race_open")
fn race_open(
  first: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  second: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  close: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
) -> List(Result(Nil, shelf.ShelfError))

@external(erlang, "filesystem_alias_test_ffi", "dirty_file")
fn dirty_file(path: String) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "with_interrupted_acquisition")
fn with_interrupted_acquisition(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "identity_count")
fn identity_count(table: set.PersistentSet(k, v)) -> Int

@external(erlang, "filesystem_alias_test_ffi", "close_native")
fn close_native(table: set.PersistentSet(k, v)) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "with_original_close_failure")
fn with_original_close_failure(
  table: set.PersistentSet(k, v),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "filesystem_alias_test_ffi", "with_paused_repair")
fn with_paused_repair(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  alias_open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  close: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
) -> Result(Nil, shelf.ShelfError)

@external(erlang, "storage_safety_test_ffi", "with_paused_save")
fn with_paused_save(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_delayed_guardian")
fn with_delayed_guardian(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  replace: fn() -> set.PersistentSet(String, Int),
  verify: fn(set.PersistentSet(String, Int)) -> Nil,
) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_rename_failure")
fn with_rename_failure(path: String, verify: fn() -> Nil) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_interrupted_open")
fn with_interrupted_open(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

type SaveStage {
  ClosingOriginal
}

@external(erlang, "storage_safety_test_ffi", "with_killed_save")
fn with_killed_save(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  stage: SaveStage,
  verify: fn() -> Nil,
) -> Nil

fn open(
  directory: String,
  filename: String,
) -> Result(set.PersistentSet(String, Int), shelf.ShelfError) {
  set.open_config(
    shelf.config("filesystem_alias", filename, base_directory: directory),
    decode.string,
    decode.int,
  )
}

pub fn hardlink_conflicts_before_decode_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.save(table)
  hardlink(directory <> "/table.dets", directory <> "/alias.dets")
  // A deliberately incompatible decoder must never see the shared file.
  let assert Error(shelf.NameConflict) =
    set.open_config(
      shelf.config("loser", "alias.dets", base_directory: directory),
      decode.int,
      decode.string,
    )
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn hardlink_after_snapshot_conflicts_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.save(table)
  hardlink(directory <> "/table.dets", directory <> "/alias.dets")
  let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn existing_hardlink_conflicts_after_reopen_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(original) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(original)
  hardlink(directory <> "/table.dets", directory <> "/alias.dets")
  let assert Ok(table) = open(directory, "table.dets")
  let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn hardlink_before_first_save_conflicts_without_native_writes_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.sync(table)
  hardlink(path, directory <> "/alias.dets")
  let before = fixture.read_file(path)
  let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
  assert fixture.read_file(path) == before
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn snapshot_releases_old_but_retains_new_identity_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  hardlink(path, directory <> "/old.dets")
  let assert Ok(Nil) = set.save(table)
  assert !same_identity(path, directory <> "/old.dets")
  assert !identity_reserved(directory <> "/old.dets")
  assert identity_reserved(path)
  // The old hardlink is now genuinely distinct, and may be opened.
  let assert Ok(old) = open(directory, "old.dets")
  hardlink(path, directory <> "/current.dets")
  let assert Error(shelf.NameConflict) = open(directory, "current.dets")
  let assert Ok(Nil) = set.close(old)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) = open(directory, "current.dets")
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

fn require_alias(first: String, second: String) -> Nil {
  case same_identity(first, second) {
    True -> Nil
    False -> io.println("SKIP: filesystem does not alias " <> second)
  }
  use <- unitest.guard(same_identity(first, second))
  Nil
}

fn assert_alias_lifecycle(first: String, second: String) -> Nil {
  use directory <- fixture.with_directory()
  let first_path = directory <> "/" <> first
  fixture.write_file(first_path, "probe")
  require_alias(first_path, directory <> "/" <> second)
  delete_file(first_path)
  let assert Ok(table) = open(directory, first)
  let assert Error(shelf.NameConflict) = open(directory, second)
  let assert Ok(Nil) = set.save(table)
  let assert Error(shelf.NameConflict) = open(directory, second)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) = open(directory, second)
  let assert Error(shelf.NameConflict) = open(directory, first)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn case_alias_lifecycle_test() -> Nil {
  assert_alias_lifecycle("Case.dets", "case.dets")
}

pub fn unicode_alias_lifecycle_test() -> Nil {
  assert_alias_lifecycle("caf\u{E9}.dets", "cafe\u{301}.dets")
}

pub fn distinct_similar_names_are_not_conflated_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(first) = open(directory, "table.dets")
  let assert Ok(second) = open(directory, "table-.dets")
  assert !same_identity(directory <> "/table.dets", directory <> "/table-.dets")
  let assert Ok(Nil) = set.insert(first, "key", 1)
  let assert Ok(Nil) = set.insert(second, "key", 2)
  assert set.lookup(first, "key") == Ok(1)
  assert set.lookup(second, "key") == Ok(2)
  let assert Ok(Nil) = set.close(first)
  let assert Ok(Nil) = set.close(second)
  Nil
}

fn assert_race(
  first: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  second: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
) -> Nil {
  let results = race_open(first, second, set.close)
  assert list.count(results, fn(result) { result == Ok(Nil) }) == 1
  assert list.count(results, fn(result) { result == Error(shelf.NameConflict) })
    == 1
}

pub fn existing_hardlink_first_open_race_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(table)
  hardlink(directory <> "/table.dets", directory <> "/alias.dets")
  assert_race(fn() { open(directory, "table.dets") }, fn() {
    open(directory, "alias.dets")
  })
}

fn assert_absent_alias_race(first: String, second: String) -> Nil {
  use directory <- fixture.with_directory()
  let first_path = directory <> "/" <> first
  fixture.write_file(first_path, "probe")
  require_alias(first_path, directory <> "/" <> second)
  delete_file(first_path)
  assert_race(fn() { open(directory, first) }, fn() { open(directory, second) })
}

pub fn absent_case_alias_first_open_race_test() -> Nil {
  assert_absent_alias_race("Case.dets", "case.dets")
}

pub fn absent_unicode_alias_first_open_race_test() -> Nil {
  assert_absent_alias_race("caf\u{E9}.dets", "cafe\u{301}.dets")
}

pub fn failed_native_open_releases_all_keys_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  fixture.write_file(path, "not DETS")
  hardlink(path, directory <> "/alias.dets")
  let assert Error(shelf.ErlangError(_)) = open(directory, "table.dets")
  assert !identity_reserved(path)
  let assert Error(shelf.ErlangError(_)) = open(directory, "alias.dets")
  assert !identity_reserved(path)
  Nil
}

pub fn unavailable_identity_returns_detailed_file_error_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Error(shelf.FileError(detail)) =
    open(directory, "missing/table.dets")
  assert string.contains(detail, "File not found")
  // A non-regular file is not a usable database identity either.
  fixture.make_directory(directory <> "/directory.dets")
  let assert Error(shelf.FileError(unsupported)) =
    open(directory, "directory.dets")
  assert string.contains(unsupported, "unsupported_identity")
  Nil
}

pub fn owner_death_before_identity_publication_cleans_all_keys_test() -> Nil {
  use directory <- fixture.with_directory()
  with_interrupted_acquisition(fn() { open(directory, "table.dets") }, fn() {
    assert fixture.list_directory(directory) == ["table.dets"]
    assert !identity_reserved(directory <> "/table.dets")
    let assert Ok(table) = open(directory, "table.dets")
    let assert Ok(Nil) = set.close(table)
    Nil
  })
}

pub fn owner_death_during_existing_native_open_releases_alias_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(original) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(original)
  hardlink(directory <> "/table.dets", directory <> "/alias.dets")
  with_interrupted_open(fn() { open(directory, "table.dets") }, fn() {
    let assert Ok(table) = open(directory, "alias.dets")
    let assert Error(shelf.NameConflict) = open(directory, "table.dets")
    let assert Ok(Nil) = set.close(table)
    Nil
  })
}

pub fn stale_guardian_cannot_remove_replacement_identity_test() -> Nil {
  use directory <- fixture.with_directory()
  with_delayed_guardian(
    fn() { open(directory, "table.dets") },
    fn() {
      hardlink(directory <> "/table.dets", directory <> "/alias.dets")
      let assert Ok(table) = open(directory, "alias.dets")
      table
    },
    fn(table) {
      let assert Error(shelf.NameConflict) = open(directory, "table.dets")
      assert identity_reserved(directory <> "/alias.dets")
      let assert Ok(Nil) = set.close(table)
      Nil
    },
  )
}

pub fn absent_canonical_alias_first_open_race_test() -> Nil {
  use directory <- fixture.with_directory()
  assert_race(fn() { open(directory, "table.dets") }, fn() {
    open(directory, "./table.dets")
  })
}

pub fn failed_rename_cleanup_releases_all_lifetime_keys_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  hardlink(path, directory <> "/alias.dets")
  with_rename_failure(path, fn() {
    let assert Error(_) = set.save(table)
    let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
    Nil
  })
  assert set.close(table) == Error(shelf.TableClosed)
  assert !identity_reserved(path)
  let assert Ok(replacement) = open(directory, "alias.dets")
  let assert Ok(Nil) = set.close(replacement)
  Nil
}

pub fn retryable_original_close_failure_releases_abandoned_identity_test() -> Nil {
  use directory <- fixture.with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.save(table)
  list.each([1, 2, 3], fn(_) {
    with_original_close_failure(table, fn() {
      let assert Error(_) = set.save(table)
      assert fixture.list_directory(directory) == ["table.dets"]
      let assert Ok(Nil) = set.sync(table)
      assert set.lookup(table, "key") == Ok(42)
      assert identity_count(table) == 1
      Nil
    })
  })
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn renamed_snapshot_failed_reopen_retains_replacement_identity_test() -> Nil {
  use directory <- fixture.with_directory()
  with_paused_save(
    fn() {
      let assert Ok(table) = open(directory, "table.dets")
      hardlink(directory <> "/table.dets", directory <> "/old.dets")
      Ok(table)
    },
    fn(table) {
      let assert Error(_) = set.save(table)
      let path = directory <> "/table.dets"
      // These bytes came from the snapshot, proving rename succeeded.
      assert fixture.read_file(path) == <<"not DETS":utf8>>
      assert fixture.list_directory(directory)
        == ["alias.dets", "old.dets", "table.dets"]
      assert identity_reserved(path)
      assert identity_count(table) == 1
      assert same_identity(path, directory <> "/alias.dets")
      let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
      assert !identity_reserved(directory <> "/old.dets")
      let assert Ok(old) = open(directory, "old.dets")
      let assert Ok(Nil) = set.close(old)
      assert set.close(table) == Error(shelf.TableClosed)
      assert identity_count(table) == 0
      assert !identity_reserved(path)
      let assert Error(shelf.ErlangError(_)) = open(directory, "alias.dets")
      Ok(Nil)
    },
    fn() {
      let snapshot = snapshot_path(directory)
      hardlink(snapshot, directory <> "/alias.dets")
      // Preserve the reserved inode but make both native reopens fail.
      // Unlike chmod(000), this also works when the tests run privileged.
      fixture.write_file(snapshot, "not DETS")
      assert same_identity(snapshot, directory <> "/alias.dets")
      Nil
    },
  )
}

pub fn recovery_creation_retires_old_and_reserves_new_identity_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  hardlink(path, directory <> "/old.dets")
  with_original_close_failure(table, fn() {
    delete_file(path)
    let assert Error(_) = set.save(table)
    let assert Ok(Nil) = set.sync(table)
    assert identity_reserved(path)
    assert identity_count(table) == 1
    assert !identity_reserved(directory <> "/old.dets")
    let assert Ok(old) = open(directory, "old.dets")
    hardlink(path, directory <> "/current.dets")
    let assert Error(shelf.NameConflict) = open(directory, "current.dets")
    let assert Ok(Nil) = set.close(old)
    Nil
  })
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn closed_native_retired_identity_does_not_block_another_file_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(stale) = open(directory, "table.dets")
  hardlink(path, directory <> "/moved.dets")
  close_native(stale)
  delete_file(path)
  // Same stale-key condition as inode reuse, without relying on allocator
  // behavior: the old canonical path is gone and native DETS is closed.
  let assert Ok(replacement) = open(directory, "moved.dets")
  assert identity_count(stale) == 0
  let assert Error(shelf.NameConflict) = open(directory, "table.dets")
  hardlink(directory <> "/moved.dets", directory <> "/current.dets")
  assert set.close(stale) == Error(shelf.TableClosed)
  assert identity_reserved(directory <> "/current.dets")
  let assert Error(shelf.NameConflict) = open(directory, "current.dets")
  let assert Ok(Nil) = set.close(replacement)
  Nil
}

pub fn snapshot_identity_is_reserved_before_exposure_test() -> Nil {
  use directory <- fixture.with_directory()
  with_paused_save(fn() { open(directory, "table.dets") }, set.save, fn() {
    let snapshot = snapshot_path(directory)
    assert identity_reserved(snapshot)
    hardlink(snapshot, directory <> "/alias.dets")
    let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
    Nil
  })
  assert !identity_reserved(directory <> "/alias.dets")
  let assert Ok(table) = open(directory, "alias.dets")
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn owner_death_during_save_releases_all_identities_test() -> Nil {
  use directory <- fixture.with_directory()
  with_killed_save(
    fn() {
      let assert Ok(table) = open(directory, "table.dets")
      hardlink(directory <> "/table.dets", directory <> "/alias.dets")
      Ok(table)
    },
    set.save,
    ClosingOriginal,
    fn() {
      assert fixture.list_directory(directory) == ["alias.dets", "table.dets"]
      assert !identity_reserved(directory <> "/alias.dets")
      let assert Ok(table) = open(directory, "alias.dets")
      let assert Error(shelf.NameConflict) = open(directory, "table.dets")
      let assert Ok(Nil) = set.close(table)
      Nil
    },
  )
}

pub fn native_repair_replacement_is_reserved_before_decode_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.close(table)
  hardlink(path, directory <> "/old.dets")
  dirty_file(path)
  let assert Ok(repaired) = open(directory, "table.dets")
  assert !same_identity(path, directory <> "/old.dets")
  assert !identity_reserved(directory <> "/old.dets")
  let assert Ok(old) = open(directory, "old.dets")
  hardlink(path, directory <> "/alias.dets")
  let assert Error(shelf.NameConflict) = open(directory, "alias.dets")
  assert set.lookup(repaired, "key") == Ok(42)
  let assert Ok(Nil) = set.close(old)
  let assert Ok(Nil) = set.close(repaired)
  Nil
}

pub fn native_repair_exposure_window_blocks_competing_alias_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(table)
  dirty_file(path)
  assert with_paused_repair(
      fn() { open(directory, "table.dets") },
      fn() {
        hardlink(path, directory <> "/alias.dets")
        open(directory, "alias.dets")
      },
      set.close,
    )
    == Error(shelf.NameConflict)
  Nil
}
