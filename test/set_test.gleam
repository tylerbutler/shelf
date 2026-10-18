import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string

const atom_safety_count = 100

import shelf
import shelf/set
import test_helpers

pub fn opens_and_closes_a_table_test() {
  let path = "/tmp/shelf_set_lifecycle.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_lifecycle",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn with_table_opens_and_auto_closes_test() {
  let path = "/tmp/shelf_set_with_table.dets"
  test_helpers.cleanup(path)
  let assert Ok(42) = {
    use table <- set.with_table(
      "set_with_table",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
    let assert Ok(Nil) = set.insert(table, "key", 42)
    set.lookup(table, "key")
  }
  test_helpers.cleanup(path)
  Nil
}

pub fn inserts_and_looks_up_a_value_test() {
  let path = "/tmp/shelf_set_insert.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_insert",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "alice", 42)
  let assert Ok(42) = set.lookup(table, "alice")
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn overwrites_existing_key_test() {
  let path = "/tmp/shelf_set_overwrite.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_overwrite",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key", "first")
  let assert Ok(Nil) = set.insert(table, "key", "second")
  let assert Ok("second") = set.lookup(table, "key")
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn returns_not_found_for_missing_key_test() {
  let path = "/tmp/shelf_set_notfound.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_notfound",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let result = set.lookup(table, "missing")
  let assert True = result == Error(shelf.NotFound)
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn member_checks_key_existence_test() {
  let path = "/tmp/shelf_set_member.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_member",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "exists", 1)
  let assert Ok(True) = set.member(table, "exists")
  let assert Ok(False) = set.member(table, "nope")
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn insert_new_fails_on_existing_key_test() {
  let path = "/tmp/shelf_set_insert_new.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_insert_new",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert_new(table, "key", "first")
  let result = set.insert_new(table, "key", "second")
  let assert True = result == Error(shelf.KeyAlreadyPresent)
  let assert Ok("first") = set.lookup(table, "key")
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn insert_list_inserts_multiple_entries_test() {
  let path = "/tmp/shelf_set_insert_list.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_insert_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(1) = set.lookup(table, "a")
  let assert Ok(2) = set.lookup(table, "b")
  let assert Ok(3) = set.lookup(table, "c")
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn delete_key_removes_an_entry_test() {
  let path = "/tmp/shelf_set_delete_key.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_delete_key",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.delete_key(table, "key")
  let assert True = set.lookup(table, "key") == Error(shelf.NotFound)
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn delete_all_removes_everything_test() {
  let path = "/tmp/shelf_set_delete_all.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_delete_all",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2)])
  let assert Ok(Nil) = set.delete_all(table)
  let assert Ok(0) = set.size(table)
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn to_list_returns_all_entries_test() {
  let path = "/tmp/shelf_set_to_list.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_to_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2)])
  let assert Ok(entries) = set.to_list(table)
  let sorted = list.sort(entries, fn(a, b) { string.compare(a.0, b.0) })
  let assert True = sorted == [#("a", 1), #("b", 2)]
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn size_returns_entry_count_test() {
  let path = "/tmp/shelf_set_size.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_size",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(0) = set.size(table)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(3) = set.size(table)
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn fold_accumulates_over_entries_test() {
  let path = "/tmp/shelf_set_fold.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_fold",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(sum) =
    set.fold(table, from: 0, with: fn(acc, _key, val) { acc + val })
  let assert True = sum == 6
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn many_distinct_names_do_not_exhaust_atoms_test() {
  // Regression test for #28: open_no_load used binary_to_atom on
  // user-provided names, risking atom exhaustion with many distinct names.
  // Now ETS tables use a fixed atom, so this is safe.
  int.range(1, atom_safety_count, [], fn(acc, i) {
    let name = "atom_safety_" <> string.inspect(i)
    let path = "/tmp/shelf_atom_safety_" <> string.inspect(i) <> ".dets"
    test_helpers.cleanup(path)
    let assert Ok(table) =
      set.open(
        name: name,
        path: path,
        base_directory: "/tmp",
        key: decode.string,
        value: decode.int,
      )
    let assert Ok(Nil) = set.insert(table, "k", i)
    let assert Ok(Nil) = set.close(table)
    test_helpers.cleanup(path)
    [i, ..acc]
  })
  Nil
}

pub fn same_name_with_different_paths_coexist_test() {
  let path_a = "/tmp/shelf_same_name_a.dets"
  let path_b = "/tmp/shelf_same_name_b.dets"
  test_helpers.cleanup(path_a)
  test_helpers.cleanup(path_b)
  let assert Ok(table_a) =
    set.open(
      name: "same_name",
      path: path_a,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(table_b) =
    set.open(
      name: "same_name",
      path: path_b,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table_a, "key", 1)
  let assert Ok(Nil) = set.insert(table_b, "key", 2)
  let assert Ok(1) = set.lookup(table_a, "key")
  let assert Ok(2) = set.lookup(table_b, "key")
  let assert Ok(Nil) = set.close(table_a)
  let assert Ok(Nil) = set.close(table_b)
  test_helpers.cleanup(path_a)
  test_helpers.cleanup(path_b)
  Nil
}

pub fn update_counter_increments_test() {
  let path = "/tmp/shelf_set_counter.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "set_counter",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "hits", 0)
  let assert Ok(1) = set.update_counter(table, "hits", 1)
  let assert Ok(3) = set.update_counter(table, "hits", 2)
  let assert Ok(0) = set.update_counter(table, "hits", -3)
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}
