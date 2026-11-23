import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import shelf
import shelf/set
import storage_safety_test as fixture
import test_helper

type SaveStage {
  OpeningSnapshot
  ClosingOriginal
}

@external(erlang, "atomic_save_test_ffi", "with_crashed_save")
fn with_crashed_save(
  directory: String,
  stage: SaveStage,
  verify: fn(String) -> a,
) -> a

@external(erlang, "atomic_save_test_ffi", "with_cleanup_permission_failure")
fn with_cleanup_permission_failure(directory: String, verify: fn() -> a) -> a

@external(erlang, "storage_safety_test_ffi", "with_paused_save")
fn with_paused_save(
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  verify: fn() -> Nil,
) -> Nil

@external(erlang, "atomic_save_test_ffi", "with_guardian_cleanup_retry")
fn with_guardian_cleanup_retry(
  directory: String,
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  save: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  close: fn(set.PersistentSet(String, Int)) -> Result(Nil, shelf.ShelfError),
  verify: fn(String, shelf.ShelfError) -> Nil,
) -> Nil

pub fn guardian_retains_failed_cleanup_and_retries_before_next_save_test() -> Nil {
  use directory <- fixture.with_directory()
  with_guardian_cleanup_retry(
    directory,
    fn() {
      let assert Ok(table) =
        set.open(
          name: "cleanup_retry",
          path: "table.dets",
          base_directory: directory,
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(Nil) = set.insert(table, "key", 42)
      Ok(table)
    },
    set.save,
    set.close,
    fn(snapshot, error) {
      let assert shelf.InvalidPath(message) = error
      assert string.contains(message, snapshot <> "/cleanup-retry-blocker")
    },
  )
  assert fixture.list_directory(directory) == ["table.dets"]
  let assert Ok(table) =
    set.open(
      name: "cleanup_retry_reopen",
      path: "table.dets",
      base_directory: directory,
      key: decode.string,
      value: decode.int,
    )
  assert set.lookup(table, "key") == Ok(42)
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn guardian_cleans_native_sidecars_after_save_test() -> Nil {
  use directory <- fixture.with_directory()
  with_paused_save(
    fn() {
      set.open(
        name: "sidecar_cleanup",
        path: "table.dets",
        base_directory: directory,
        key: decode.string,
        value: decode.int,
      )
    },
    set.save,
    fn() {
      let assert [name] =
        fixture.list_directory(directory)
        |> list.filter(fn(name) { string.starts_with(name, ".shelf-save-") })
      list.each(
        [
          "snapshot.dets.16",
          "fs_nonode@nohost_86491_386.17",
          "metadata-source",
          "tar.A1b2C3d4",
        ],
        fn(sidecar) {
          fixture.write_file(directory <> "/" <> name <> "/" <> sidecar, "temp")
        },
      )
    },
  )
  assert fixture.list_directory(directory) == ["table.dets"]
}

pub fn cleanup_after_whole_vm_kill_preserves_committed_data_test() -> Nil {
  list.each([OpeningSnapshot, ClosingOriginal], fn(stage) {
    use directory <- fixture.with_directory()
    use snapshot <- with_crashed_save(directory, stage)
    let assert Ok(Nil) =
      shelf.cleanup_snapshot(snapshot, base_directory: directory)
    assert fixture.list_directory(directory) == ["table.dets"]

    let assert Ok(table) =
      set.open(
        name: "crash_recovery",
        path: "table.dets",
        base_directory: directory,
        key: decode.string,
        value: decode.int,
      )
    assert set.lookup(table, "committed") == Ok(1)
    assert set.lookup(table, "uncommitted") == Error(shelf.NotFound)
    let assert Ok(Nil) = set.close(table)
  })
}

pub fn cleanup_failure_reports_path_and_allows_retry_test() -> Nil {
  use directory <- fixture.with_directory()
  let snapshot = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(snapshot)
  fixture.write_file(snapshot <> "/snapshot.dets", "leftover")
  with_cleanup_permission_failure(snapshot, fn() {
    let assert Error(shelf.FileError(message)) =
      shelf.cleanup_snapshot(snapshot, base_directory: directory)
    assert string.contains(message, snapshot <> "/snapshot.dets")
    assert string.contains(message, "delete")
    assert fixture.read_file(snapshot <> "/snapshot.dets")
      == <<"leftover":utf8>>
  })
  let assert Ok(Nil) =
    shelf.cleanup_snapshot(snapshot, base_directory: directory)
  assert fixture.list_directory(directory) == []
}

pub fn cleanup_metadata_failure_reports_path_and_allows_retry_test() -> Nil {
  use directory <- fixture.with_directory()
  let snapshot = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(snapshot)
  fixture.write_file(snapshot <> "/metadata-source", "metadata alias")
  with_cleanup_permission_failure(snapshot, fn() {
    let assert Error(shelf.FileError(message)) =
      shelf.cleanup_snapshot(snapshot, base_directory: directory)
    assert string.contains(message, snapshot <> "/metadata-source")
    assert string.contains(message, "delete")
    assert fixture.read_file(snapshot <> "/metadata-source")
      == <<"metadata alias":utf8>>
  })
  let assert Ok(Nil) =
    shelf.cleanup_snapshot(snapshot, base_directory: directory)
  assert fixture.list_directory(directory) == []
}

pub fn cleanup_removes_legacy_snapshot_and_native_sidecars_test() -> Nil {
  use directory <- fixture.with_directory()
  let snapshot = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(snapshot)
  list.each(
    [
      "snapshot.dets",
      "snapshot.dets.1",
      "snapshot.dets.16",
      "fs_nonode@nohost_86491_386.17",
      "metadata-source",
      "tar.A1b2C3d4",
    ],
    fn(name) { fixture.write_file(snapshot <> "/" <> name, "leftover") },
  )
  fixture.write_file(directory <> "/table.dets", "committed data")
  let unrelated = directory <> "/.shelf-save-86491-19"
  fixture.make_directory(unrelated)
  fixture.write_file(unrelated <> "/snapshot.dets", "unrelated save")

  let assert Ok(Nil) =
    shelf.cleanup_snapshot(".shelf-save-86491-18", base_directory: directory)
  assert fixture.list_directory(directory)
    == [
      ".shelf-save-86491-19",
      "table.dets",
    ]
  assert fixture.read_file(directory <> "/table.dets")
    == <<"committed data":utf8>>
  assert fixture.read_file(unrelated <> "/snapshot.dets")
    == <<"unrelated save":utf8>>
}

pub fn cleanup_rejects_unknown_entries_before_deleting_anything_test() -> Nil {
  list.each(
    [
      "notes",
      "snapshot.dets.backup",
      "snapshot.dets.",
      "fs_unrelated",
      "metadata-source.backup",
      "tar.A1b2C3d",
      "tar.A1b2C3d45",
      "tar.A1b2C3d_",
    ],
    fn(unknown) {
      use directory <- fixture.with_directory()
      let snapshot = directory <> "/.shelf-save-86491-18"
      fixture.make_directory(snapshot)
      fixture.write_file(snapshot <> "/snapshot.dets", "snapshot")
      fixture.write_file(snapshot <> "/metadata-source", "metadata alias")
      fixture.write_file(snapshot <> "/tar.A1b2C3d4", "metadata archive")
      fixture.write_file(snapshot <> "/" <> unknown, "keep")

      let assert Error(shelf.InvalidPath(_)) =
        shelf.cleanup_snapshot(snapshot, base_directory: directory)
      assert fixture.read_file(snapshot <> "/snapshot.dets")
        == <<"snapshot":utf8>>
      assert fixture.read_file(snapshot <> "/metadata-source")
        == <<"metadata alias":utf8>>
      assert fixture.read_file(snapshot <> "/tar.A1b2C3d4")
        == <<"metadata archive":utf8>>
      assert fixture.read_file(snapshot <> "/" <> unknown) == <<"keep":utf8>>
    },
  )
}

pub fn cleanup_rejects_nested_directory_and_entry_symlink_test() -> Nil {
  use directory <- fixture.with_directory()
  let snapshot = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(snapshot)
  fixture.write_file(snapshot <> "/snapshot.dets", "snapshot")
  fixture.make_directory(snapshot <> "/snapshot.dets.1")

  let assert Error(shelf.InvalidPath(_)) =
    shelf.cleanup_snapshot(snapshot, base_directory: directory)
  assert fixture.read_file(snapshot <> "/snapshot.dets") == <<"snapshot":utf8>>

  let linked_snapshot = directory <> "/.shelf-save-86491-19"
  fixture.make_directory(linked_snapshot)
  fixture.write_file(directory <> "/target", "keep")
  fixture.symlink(directory <> "/target", linked_snapshot <> "/snapshot.dets")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.cleanup_snapshot(linked_snapshot, base_directory: directory)
  assert fixture.read_file(directory <> "/target") == <<"keep":utf8>>
  assert fixture.list_directory(linked_snapshot) == ["snapshot.dets"]
}

pub fn cleanup_rejects_candidate_symlink_and_base_escape_test() -> Nil {
  use directory <- fixture.with_directory()
  let snapshot = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(snapshot)
  fixture.write_file(snapshot <> "/snapshot.dets", "keep")
  let link = directory <> "/.shelf-save-86491-19"
  fixture.symlink(snapshot, link)
  fixture.make_directory(directory <> "/allowed")

  list.each([link, link <> "/"], fn(candidate) {
    let assert Error(shelf.InvalidPath(_)) =
      shelf.cleanup_snapshot(candidate, base_directory: directory)
  })
  let assert Error(shelf.InvalidPath(_)) =
    shelf.cleanup_snapshot(
      "../.shelf-save-86491-18",
      base_directory: directory <> "/allowed",
    )
  assert fixture.read_file(snapshot <> "/snapshot.dets") == <<"keep":utf8>>
}

pub fn cleanup_rejects_metadata_symlinks_before_deleting_anything_test() -> Nil {
  list.each(["metadata-source", "tar.A1b2C3d4"], fn(name) {
    use directory <- fixture.with_directory()
    let snapshot = directory <> "/.shelf-save-86491-18"
    fixture.make_directory(snapshot)
    fixture.write_file(snapshot <> "/snapshot.dets", "snapshot")
    fixture.write_file(directory <> "/target", "keep")
    fixture.symlink(directory <> "/target", snapshot <> "/" <> name)
    let assert Error(shelf.InvalidPath(_)) =
      shelf.cleanup_snapshot(snapshot, base_directory: directory)
    assert fixture.read_file(snapshot <> "/snapshot.dets")
      == <<"snapshot":utf8>>
    assert fixture.read_file(directory <> "/target") == <<"keep":utf8>>
    assert list.length(fixture.list_directory(snapshot)) == 2
  })
}

pub fn cleanup_rejects_unrelated_directory_and_null_bytes_test() -> Nil {
  use directory <- fixture.with_directory()
  let unrelated = directory <> "/not-a-snapshot"
  fixture.make_directory(unrelated)
  fixture.write_file(unrelated <> "/snapshot.dets", "keep")
  list.each(
    [
      #(unrelated, directory),
      #(".shelf-save-x-18", directory),
      #(".shelf-save-86491-", directory),
      #(".shelf-save-86491-18\u{0}", directory),
      #(".shelf-save-86491-18", directory <> "\u{0}"),
    ],
    fn(candidate) {
      let assert Error(shelf.InvalidPath(_)) =
        shelf.cleanup_snapshot(candidate.0, base_directory: candidate.1)
    },
  )
  assert fixture.read_file(unrelated <> "/snapshot.dets") == <<"keep":utf8>>
}

pub fn cleanup_cannot_remove_the_trusted_base_directory_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/.shelf-save-86491-18"
  fixture.make_directory(base)
  fixture.write_file(base <> "/snapshot.dets", "keep")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.cleanup_snapshot(base, base_directory: base)
  assert fixture.read_file(base <> "/snapshot.dets") == <<"keep":utf8>>
}

pub fn cleanup_reports_missing_directory_with_path_test() -> Nil {
  use directory <- fixture.with_directory()
  let missing = directory <> "/.shelf-save-86491-18"
  let assert Error(shelf.FileError(message)) =
    shelf.cleanup_snapshot(missing, base_directory: directory)
  assert string.contains(message, missing)
  assert string.contains(message, "enoent")
}

pub fn save_cleans_up_temporary_file_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/table.dets"

  let assert Ok(table) =
    set.open(
      name: "as_temp",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.save(table)

  // Neither the private snapshot file nor its directory should remain.
  assert fixture.list_directory(directory) == ["table.dets"]

  let assert Ok(Nil) = set.close(table)
  assert fixture.list_directory(directory) == ["table.dets"]
  Nil
}

pub fn data_survives_save_close_reopen_cycle_test() -> Nil {
  let path = "/tmp/shelf_as_reopen.dets"
  test_helper.cleanup(path)

  // Open, insert, save, close
  let assert Ok(table) =
    set.open(
      name: "as_reopen",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "x", 100)
  let assert Ok(Nil) = set.insert(table, "y", 200)
  let assert Ok(Nil) = set.save(table)
  let assert Ok(Nil) = set.close(table)

  // Reopen and verify data is present
  let assert Ok(table2) =
    set.open(
      name: "as_reopen2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  assert set.lookup(table2, "x") == Ok(100)
  assert set.lookup(table2, "y") == Ok(200)

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
  Nil
}

pub fn save_preserves_data_integrity_with_many_entries_test() -> Nil {
  let path = "/tmp/shelf_as_integrity.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "as_integrity",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let count = 100
  // Insert many entries
  int.range(count, 0, [], list.prepend)
  |> list.each(fn(i) {
    let key = "entry_" <> int.to_string(i)
    let assert Ok(Nil) = set.insert(table, key, i)
    Nil
  })

  let assert Ok(Nil) = set.save(table)
  let assert Ok(Nil) = set.close(table)

  // Reopen and verify count
  let assert Ok(table2) =
    set.open(
      name: "as_integrity2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(size) = set.size(table2)
  assert size == count

  // Spot-check some values
  assert set.lookup(table2, "entry_1") == Ok(1)
  assert set.lookup(table2, "entry_50") == Ok(50)
  assert set.lookup(table2, "entry_100") == Ok(100)

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
  Nil
}
