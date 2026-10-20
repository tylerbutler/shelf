import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set

@external(erlang, "storage_safety_test_ffi", "with_directory")
pub fn with_directory(fun: fn(String) -> a) -> a

@external(erlang, "storage_safety_test_ffi", "write_file")
pub fn write_file(path: String, contents: String) -> Nil

@external(erlang, "storage_safety_test_ffi", "read_file")
pub fn read_file(path: String) -> BitArray

@external(erlang, "storage_safety_test_ffi", "list_directory")
pub fn list_directory(path: String) -> List(String)

@external(erlang, "storage_safety_test_ffi", "make_directory")
pub fn make_directory(path: String) -> Nil

@external(erlang, "storage_safety_test_ffi", "symlink")
pub fn symlink(target: String, path: String) -> Nil

@external(erlang, "storage_safety_test_ffi", "in_other_process")
fn in_other_process(fun: fn() -> a) -> a

@external(erlang, "storage_safety_test_ffi", "with_read_only")
fn with_read_only(table: set.PersistentSet(k, v), fun: fn() -> a) -> a

@external(erlang, "storage_safety_test_ffi", "with_rename_failure")
fn with_rename_failure(path: String, fun: fn() -> a) -> a

@external(erlang, "storage_safety_test_ffi", "with_delayed_guardian")
fn with_delayed_guardian(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  replace: fn() -> set.PersistentSet(String, Int),
  verify: fn(set.PersistentSet(String, Int)) -> Nil,
) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_interrupted_open")
fn with_interrupted_open(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_paused_save")
fn with_paused_save(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "storage_safety_test_ffi", "with_killed_save")
fn with_killed_save(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  stage: SaveStage,
  verify: fn() -> Nil,
) -> Nil

type SaveStage {
  OpeningSnapshot
  ClosingOriginal
}

fn config(directory: String, filename: String) -> shelf.Config {
  shelf.config("storage_safety", filename, base_directory: directory)
  |> shelf.write_mode(shelf.WriteThrough)
}

fn open(
  directory: String,
  filename: String,
) -> Result(set.PersistentSet(String, Int), shelf.ShelfError) {
  set.open_config(config(directory, filename), decode.string, decode.int)
}

fn mutations() -> List(
  fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
) {
  [
    fn(table) { set.insert(table, "new", 2) },
    fn(table) { set.insert_list(table, [#("key", 9), #("new", 2)]) },
    fn(table) { set.delete_key(table, "key") },
    fn(table) { set.delete_object(table, "key", 1) },
    set.delete_all,
    fn(table) { set.insert_new(table, "new", 2) },
    fn(table) { set.insert_new(table, "key", 2) },
    fn(table) {
      set.update_counter(table, "key", 2) |> result.map(fn(_) { Nil })
    },
  ]
}

fn assert_persisted_original(table: set.PersistentSet(String, Int)) -> Nil {
  assert set.to_list(table) == Ok([#("key", 1)])
  // Read DETS before any snapshot could overwrite evidence of divergence.
  let assert Ok(Nil) = set.reload(table)
  assert set.to_list(table) == Ok([#("key", 1)])
}

pub fn non_owner_mutations_do_not_touch_dets_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  mutations()
  |> list.each(fn(mutate) {
    assert in_other_process(fn() { mutate(table) }) == Error(shelf.NotOwner)
    assert_persisted_original(table)
  })
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn stale_mutations_do_not_touch_reopened_dets_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(stale) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(stale, "key", 1)
  let assert Ok(Nil) = set.close(stale)
  let assert Ok(replacement) = open(directory, "table.dets")
  mutations()
  |> list.each(fn(mutate) {
    assert mutate(stale) == Error(shelf.TableClosed)
    assert_persisted_original(replacement)
  })
  let assert Ok(Nil) = set.close(replacement)
  Nil
}

pub fn read_only_dets_errors_are_typed_and_counter_is_rolled_back_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  mutations()
  |> list.each(fn(mutate) {
    with_read_only(table, fn() {
      case mutate(table) {
        // The existing-key insert_new does not attempt a DETS write.
        Error(shelf.KeyAlreadyPresent) -> Nil
        Error(error) -> {
          let assert shelf.ErlangError(detail) = error
          assert string.contains(detail, "access_mode")
            || string.contains(detail, "file_error")
        }
        Ok(Nil) -> panic as "Expected a returned read-only DETS error"
      }
      assert set.to_list(table) == Ok([#("key", 1)])
    })
    assert_persisted_original(table)
  })
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn successful_write_through_mutations_survive_reload_before_snapshot_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  assert_persisted_original(table)
  let assert Ok(Nil) = set.insert_list(table, [#("key", 2), #("other", 3)])
  let assert Ok(Nil) = set.reload(table)
  assert set.lookup(table, "key") == Ok(2)
  assert set.lookup(table, "other") == Ok(3)
  let assert Ok(Nil) = set.insert_new(table, "new", 4)
  let assert Ok(Nil) = set.reload(table)
  assert set.lookup(table, "new") == Ok(4)
  let assert Ok(5) = set.update_counter(table, "key", 3)
  let assert Ok(Nil) = set.reload(table)
  assert set.lookup(table, "key") == Ok(5)
  let assert Ok(Nil) = set.delete_object(table, "key", 5)
  let assert Ok(Nil) = set.reload(table)
  assert set.member(table, "key") == Ok(False)
  let assert Ok(Nil) = set.delete_key(table, "other")
  let assert Ok(Nil) = set.reload(table)
  assert set.to_list(table) == Ok([#("new", 4)])
  let assert Ok(Nil) = set.delete_all(table)
  let assert Ok(Nil) = set.reload(table)
  assert set.size(table) == Ok(0)
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn bag_write_through_preserves_multiplicity_before_snapshot_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) =
    bag.open_config(config(directory, "bag.dets"), decode.string, decode.int)
  let assert Ok(Nil) = bag.insert(table, "key", 1)
  let assert Ok(Nil) = bag.insert_list(table, [#("key", 1), #("key", 2)])
  let assert Ok(Nil) = bag.reload(table)
  assert bag.size(table) == Ok(2)
  assert in_other_process(fn() { bag.delete_all(table) })
    == Error(shelf.NotOwner)
  let assert Ok(Nil) = bag.reload(table)
  assert bag.size(table) == Ok(2)
  let assert Ok(Nil) = bag.delete_object(table, "key", 1)
  let assert Ok(Nil) = bag.reload(table)
  assert bag.lookup(table, "key") == Ok([2])
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(replacement) =
    bag.open_config(config(directory, "bag.dets"), decode.string, decode.int)
  assert bag.delete_all(table) == Error(shelf.TableClosed)
  let assert Ok(Nil) = bag.reload(replacement)
  assert bag.lookup(replacement, "key") == Ok([2])
  let assert Ok(Nil) = bag.close(replacement)
  Nil
}

pub fn duplicate_bag_write_through_preserves_duplicates_before_snapshot_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) =
    duplicate_bag.open_config(
      config(directory, "bag.dets"),
      decode.string,
      decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", 1)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [#("key", 1), #("key", 2)])
  let assert Ok(Nil) = duplicate_bag.reload(table)
  assert duplicate_bag.size(table) == Ok(3)
  assert in_other_process(fn() { duplicate_bag.delete_all(table) })
    == Error(shelf.NotOwner)
  let assert Ok(Nil) = duplicate_bag.reload(table)
  assert duplicate_bag.size(table) == Ok(3)
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "key", 1)
  let assert Ok(Nil) = duplicate_bag.reload(table)
  assert duplicate_bag.lookup(table, "key") == Ok([2])
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(replacement) =
    duplicate_bag.open_config(
      config(directory, "bag.dets"),
      decode.string,
      decode.int,
    )
  assert duplicate_bag.delete_all(table) == Error(shelf.TableClosed)
  let assert Ok(Nil) = duplicate_bag.reload(replacement)
  assert duplicate_bag.lookup(replacement, "key") == Ok([2])
  let assert Ok(Nil) = duplicate_bag.close(replacement)
  Nil
}

pub fn cross_process_opens_conflict_before_and_after_save_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(table) = open(directory, "table.dets")
  let assert Error(shelf.NameConflict) =
    in_other_process(fn() { open(directory, "table.dets") })
  let assert Ok(Nil) = set.save(table)
  let assert Error(shelf.NameConflict) =
    in_other_process(fn() { open(directory, "table.dets") })
  let assert Ok(Nil) = set.insert(table, "key", 1)
  assert_persisted_original(table)
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn failed_open_releases_its_reservation_test() -> Nil {
  use directory <- with_directory()
  let path = directory <> "/table.dets"
  write_file(path, "not DETS")
  let assert Error(_) = open(directory, "table.dets")
  // Repeating the native error, rather than NameConflict, proves release.
  let assert Error(shelf.ErlangError(_)) = open(directory, "table.dets")
  Nil
}

pub fn delayed_guardian_cannot_unregister_replacement_test() -> Nil {
  use directory <- with_directory()
  with_delayed_guardian(
    fn() { open(directory, "table.dets") },
    fn() {
      let assert Ok(table) = open(directory, "table.dets")
      table
    },
    fn(table) {
      let assert Error(shelf.NameConflict) = open(directory, "table.dets")
      let assert Ok(Nil) = set.insert(table, "key", 1)
      assert_persisted_original(table)
      let assert Ok(Nil) = set.close(table)
      Nil
    },
  )
}

pub fn owner_exit_during_native_open_releases_reservation_test() -> Nil {
  use directory <- with_directory()
  with_interrupted_open(fn() { open(directory, "table.dets") }, fn() {
    let assert Ok(table) = open(directory, "table.dets")
    let assert Ok(Nil) = set.close(table)
    Nil
  })
}

pub fn owner_exit_during_failed_native_open_releases_reservation_test() -> Nil {
  use directory <- with_directory()
  with_interrupted_open(fn() { open(directory, "missing/table.dets") }, fn() {
    // Let the interrupted native open fail before creating the parent.
    let assert Error(shelf.FileError(_)) = open(directory, "missing/table.dets")
    make_directory(directory <> "/missing")
    let assert Ok(table) = open(directory, "missing/table.dets")
    let assert Ok(Nil) = set.close(table)
    Nil
  })
}

pub fn path_remains_reserved_between_save_close_and_reopen_test() -> Nil {
  use directory <- with_directory()
  with_paused_save(fn() { open(directory, "table.dets") }, set.save, fn() {
    let assert Error(shelf.NameConflict) = open(directory, "table.dets")
    Nil
  })
  let assert Ok(reopened) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn owner_death_during_save_cleans_only_its_snapshot_test() -> Nil {
  assert_killed_save_cleanup(ClosingOriginal)
}

pub fn owner_death_while_opening_snapshot_cleans_only_its_snapshot_test() -> Nil {
  assert_killed_save_cleanup(OpeningSnapshot)
}

fn assert_killed_save_cleanup(stage: SaveStage) -> Nil {
  use directory <- with_directory()
  let foreign_directory = directory <> "/.shelf-save-foreign"
  make_directory(foreign_directory)
  write_file(foreign_directory <> "/snapshot.dets", "foreign snapshot")
  write_file(directory <> "/table.dets.tmp", "foreign temporary file")
  with_killed_save(
    fn() {
      let assert Ok(table) = open(directory, "table.dets")
      let assert Ok(Nil) = set.insert(table, "key", 42)
      Ok(table)
    },
    set.save,
    stage,
    fn() {
      // The fixture has awaited owner, native DETS, and guardian shutdown.
      // Inspect before reopening so another save cannot mask leaked state.
      assert list_directory(directory)
        == [".shelf-save-foreign", "table.dets", "table.dets.tmp"]
      let assert Ok(reopened) = open(directory, "table.dets")
      assert set.lookup(reopened, "key") == Ok(42)
      let assert Ok(Nil) = set.close(reopened)
      assert list_directory(directory)
        == [".shelf-save-foreign", "table.dets", "table.dets.tmp"]
      assert read_file(foreign_directory <> "/snapshot.dets")
        == <<"foreign snapshot":utf8>>
      assert read_file(directory <> "/table.dets.tmp")
        == <<"foreign temporary file":utf8>>
    },
  )
}

pub fn save_preserves_unrelated_temporary_file_test() -> Nil {
  use directory <- with_directory()
  let temporary = directory <> "/table.dets.tmp"
  write_file(temporary, "unrelated bytes")
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.save(table)
  assert read_file(temporary) == <<"unrelated bytes":utf8>>
  assert list_directory(directory) == ["table.dets", "table.dets.tmp"]
  let assert Ok(Nil) = set.close(table)
  assert read_file(temporary) == <<"unrelated bytes":utf8>>
}

pub fn save_preserves_unrelated_closed_temporary_database_test() -> Nil {
  use directory <- with_directory()
  let assert Ok(temporary) = open(directory, "table.dets.tmp")
  let assert Ok(Nil) = set.insert(temporary, "unrelated", 99)
  let assert Ok(Nil) = set.close(temporary)
  let before = read_file(directory <> "/table.dets.tmp")
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.save(table)
  assert read_file(directory <> "/table.dets.tmp") == before
  let assert Ok(Nil) = set.close(table)
  let assert Ok(temporary) = open(directory, "table.dets.tmp")
  assert set.to_list(temporary) == Ok([#("unrelated", 99)])
  let assert Ok(Nil) = set.close(temporary)
  Nil
}

pub fn failed_save_cleans_only_its_private_snapshot_test() -> Nil {
  use directory <- with_directory()
  let path = directory <> "/table.dets"
  write_file(path <> ".tmp", "unrelated")
  let assert Ok(table) = open(directory, "table.dets")
  let assert Ok(Nil) = set.insert(table, "key", 1)
  with_rename_failure(path, fn() {
    let assert Error(_) = set.save(table)
    assert list_directory(directory)
      == ["table.dets", "table.dets.original", "table.dets.tmp"]
    assert read_file(path <> ".tmp") == <<"unrelated":utf8>>
    assert set.lookup(table, "key") == Ok(1)
    let assert Error(shelf.NameConflict) = open(directory, "table.dets")
    Nil
  })
  // Save could not reopen the directory. Terminal close must still release
  // the reservation, even though dets:info no longer remembers the filename.
  assert set.close(table) == Error(shelf.TableClosed)
  let assert Ok(reopened) = open(directory, "table.dets")
  let assert Ok(Nil) = set.close(reopened)
  Nil
}
