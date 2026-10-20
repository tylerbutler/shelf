import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import shelf
import shelf/duplicate_bag
import test_helper

pub fn opens_and_closes_a_duplicate_bag_table_test() -> Nil {
  let path = "/tmp/shelf_dbag_lifecycle.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_lifecycle",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let legacy: duplicate_bag.PDuplicateBag(String, String) = table
  let table: duplicate_bag.PersistentDuplicateBag(String, String) = legacy
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn with_table_opens_and_auto_closes_test() -> Nil {
  let path = "/tmp/shelf_dbag_with_table.dets"
  test_helper.cleanup(path)
  let assert Ok(values) = {
    use table <- duplicate_bag.with_table(
      "dbag_with_table",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
    let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
    let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
    duplicate_bag.lookup(table, "key")
  }
  assert values == ["hello", "hello"]
  test_helper.cleanup(path)
  Nil
}

pub fn configured_scope_uses_write_through_and_closes_test() -> Nil {
  let path = "/tmp/shelf_duplicate_bag_configured_scope.dets"
  test_helper.cleanup(path)
  let config =
    shelf.config("configured_scope", path, base_directory: "/tmp")
    |> shelf.write_mode(shelf.WriteThrough)
  let assert Ok(closed) = {
    use table <- duplicate_bag.with_table_config(
      config,
      key: decode.string,
      value: decode.string,
      map_error: fn(error) { error },
    )
    let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
    let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
    let assert Ok(Nil) = duplicate_bag.reload(table)
    let assert Ok(["hello", "hello"]) = duplicate_bag.lookup(table, "key")
    Ok(table)
  }
  let assert Error(shelf.TableClosed) = duplicate_bag.size(closed)
  test_helper.cleanup(path)
}

pub fn preserves_duplicate_key_value_pairs_test() -> Nil {
  let path = "/tmp/shelf_dbag_dupes.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_dupes",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
  let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
  let assert Ok(Nil) = duplicate_bag.insert(table, "event", "scroll")
  let assert Ok(values) = duplicate_bag.lookup(table, "event")
  // Should have 2 "click" and 1 "scroll"
  let click_count = list.filter(values, fn(v) { v == "click" }) |> list.length
  let scroll_count = list.filter(values, fn(v) { v == "scroll" }) |> list.length
  assert click_count == 2
  assert scroll_count == 1
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn returns_not_found_for_missing_key_test() -> Nil {
  let path = "/tmp/shelf_dbag_notfound.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_notfound",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  assert duplicate_bag.lookup(table, "missing") == Error(shelf.NotFound)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn member_checks_key_existence_test() -> Nil {
  let path = "/tmp/shelf_dbag_member.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_member",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "exists", 1)
  let assert Ok(True) = duplicate_bag.member(table, "exists")
  let assert Ok(False) = duplicate_bag.member(table, "nope")
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn to_list_returns_all_entries_test() -> Nil {
  let path = "/tmp/shelf_dbag_to_list.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_to_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  let assert Ok(entries) = duplicate_bag.to_list(table)
  let sorted =
    list.sort(entries, fn(a, b) {
      case string.compare(a.0, b.0) {
        order.Eq -> int.compare(a.1, b.1)
        order.Lt -> order.Lt
        order.Gt -> order.Gt
      }
    })
  assert sorted == [#("a", 1), #("a", 1), #("b", 2)]
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn fold_accumulates_over_entries_test() -> Nil {
  let path = "/tmp/shelf_dbag_fold.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_fold",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 3)
  let assert Ok(sum) =
    duplicate_bag.fold(table, from: 0, with: fn(acc, _key, value) {
      acc + value
    })
  assert sum == 5
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn size_returns_entry_count_test() -> Nil {
  let path = "/tmp/shelf_dbag_size.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_size",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(0) = duplicate_bag.size(table)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  let assert Ok(3) = duplicate_bag.size(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn insert_list_inserts_multiple_entries_test() -> Nil {
  let path = "/tmp/shelf_dbag_insert_list.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_insert_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [
      #("a", 1),
      #("a", 1),
      #("b", 2),
    ])
  let assert Ok(values_a) = duplicate_bag.lookup(table, "a")
  assert values_a == [1, 1]
  let assert Ok(values_b) = duplicate_bag.lookup(table, "b")
  assert values_b == [2]
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_key_removes_all_values_for_a_key_test() -> Nil {
  let path = "/tmp/shelf_dbag_del_key.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_del_key",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "blue")
  let assert Ok(Nil) = duplicate_bag.delete_key(table, "color")
  assert duplicate_bag.lookup(table, "color") == Error(shelf.NotFound)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_object_removes_matching_entries_test() -> Nil {
  let path = "/tmp/shelf_dbag_del_obj.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_del_obj",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
  let assert Ok(Nil) = duplicate_bag.insert(table, "color", "blue")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "color", "red")
  let assert Ok(values) = duplicate_bag.lookup(table, "color")
  assert values == ["blue"]
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_all_removes_everything_test() -> Nil {
  let path = "/tmp/shelf_dbag_del_all.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_del_all",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  let assert Ok(0) = duplicate_bag.size(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn save_persists_data_test() -> Nil {
  let path = "/tmp/shelf_dbag_save.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_save_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "x", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "x", "a")
  let assert Ok(Nil) = duplicate_bag.save(table)
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_save_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table, "x")
  assert values == ["a", "a"]
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn reload_discards_unsaved_changes_test() -> Nil {
  let path = "/tmp/shelf_dbag_reload.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      name: "dbag_reload",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "saved", "yes")
  let assert Ok(Nil) = duplicate_bag.save(table)
  let assert Ok(Nil) = duplicate_bag.insert(table, "unsaved", "oops")
  let assert Ok(True) = duplicate_bag.member(table, "unsaved")
  let assert Ok(_) = duplicate_bag.reload(table)
  let assert Ok(True) = duplicate_bag.member(table, "saved")
  let assert Ok(False) = duplicate_bag.member(table, "unsaved")
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
  Nil
}
