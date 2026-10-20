import gleam/dynamic/decode
import gleam/int
import gleam/list
import shelf/set
import storage_safety_test as fixture
import test_helper

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
