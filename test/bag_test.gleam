import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import shelf
import shelf/bag
import test_helper

pub fn opens_and_closes_a_bag_table_test() -> Nil {
  let path = "/tmp/shelf_bag_lifecycle.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_lifecycle",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let legacy: bag.PBag(String, String) = table
  let table: bag.PersistentBag(String, String) = legacy
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn with_table_opens_and_auto_closes_test() -> Nil {
  let path = "/tmp/shelf_bag_with_table.dets"
  test_helper.cleanup(path)
  let assert Ok(["hello"]) = {
    use table <- bag.with_table(
      "bag_with_table",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
    let assert Ok(Nil) = bag.insert(table, "key", "hello")
    bag.lookup(table, "key")
  }
  test_helper.cleanup(path)
  Nil
}

pub fn stores_multiple_values_per_key_test() -> Nil {
  let path = "/tmp/shelf_bag_multi.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_multi",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(values) = bag.lookup(table, "color")
  let sorted = list.sort(values, string.compare)
  assert sorted == ["blue", "red"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn deduplicates_identical_key_value_pairs_test() -> Nil {
  let path = "/tmp/shelf_bag_dedup.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_dedup",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
  let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
  let assert Ok(values) = bag.lookup(table, "tag")
  assert values == ["gleam"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn returns_not_found_for_missing_key_test() -> Nil {
  let path = "/tmp/shelf_bag_notfound.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_notfound",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  assert bag.lookup(table, "missing") == Error(shelf.NotFound)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn member_checks_key_existence_test() -> Nil {
  let path = "/tmp/shelf_bag_member.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_member",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert(table, "exists", 1)
  let assert Ok(True) = bag.member(table, "exists")
  let assert Ok(False) = bag.member(table, "nope")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn to_list_returns_all_entries_test() -> Nil {
  let path = "/tmp/shelf_bag_to_list.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_to_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "b", 2)
  let assert Ok(Nil) = bag.insert(table, "a", 3)
  let assert Ok(entries) = bag.to_list(table)
  let sorted =
    list.sort(entries, fn(a, b) {
      case string.compare(a.0, b.0) {
        order.Eq -> int.compare(a.1, b.1)
        order.Lt -> order.Lt
        order.Gt -> order.Gt
      }
    })
  assert sorted == [#("a", 1), #("a", 3), #("b", 2)]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn fold_accumulates_over_entries_test() -> Nil {
  let path = "/tmp/shelf_bag_fold.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_fold",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "b", 2)
  let assert Ok(Nil) = bag.insert(table, "a", 3)
  let assert Ok(sum) =
    bag.fold(table, from: 0, with: fn(acc, _key, value) { acc + value })
  assert sum == 6
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn size_returns_entry_count_test() -> Nil {
  let path = "/tmp/shelf_bag_size.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_size",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(0) = bag.size(table)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)
  let assert Ok(3) = bag.size(table)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn insert_list_inserts_multiple_entries_test() -> Nil {
  let path = "/tmp/shelf_bag_insert_list.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_insert_list",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert_list(table, [#("a", 1), #("b", 2), #("a", 3)])
  let assert Ok(values_a) = bag.lookup(table, "a")
  let sorted_a = list.sort(values_a, int.compare)
  assert sorted_a == [1, 3]
  let assert Ok(values_b) = bag.lookup(table, "b")
  assert values_b == [2]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_object_removes_one_value_for_a_key_test() -> Nil {
  let path = "/tmp/shelf_bag_del_obj.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_del_obj",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(Nil) = bag.delete_object(table, "color", "red")
  let assert Ok(values) = bag.lookup(table, "color")
  assert values == ["blue"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_key_removes_all_values_for_a_key_test() -> Nil {
  let path = "/tmp/shelf_bag_del_key.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_del_key",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(Nil) = bag.delete_key(table, "color")
  assert bag.lookup(table, "color") == Error(shelf.NotFound)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn delete_all_removes_everything_test() -> Nil {
  let path = "/tmp/shelf_bag_del_all.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_del_all",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "b", 2)
  let assert Ok(Nil) = bag.delete_all(table)
  let assert Ok(0) = bag.size(table)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn save_persists_data_test() -> Nil {
  let path = "/tmp/shelf_bag_save.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_save_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = bag.insert(table, "x", 1)
  let assert Ok(Nil) = bag.insert(table, "x", 2)
  let assert Ok(Nil) = bag.save(table)
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table) =
    bag.open(
      name: "bag_save_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(values) = bag.lookup(table, "x")
  let sorted = list.sort(values, int.compare)
  assert sorted == [1, 2]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn reload_discards_unsaved_changes_test() -> Nil {
  let path = "/tmp/shelf_bag_reload.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open(
      name: "bag_reload",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "saved", "yes")
  let assert Ok(Nil) = bag.save(table)
  let assert Ok(Nil) = bag.insert(table, "unsaved", "oops")
  let assert Ok(True) = bag.member(table, "unsaved")
  let assert Ok(_) = bag.reload(table)
  let assert Ok(True) = bag.member(table, "saved")
  let assert Ok(False) = bag.member(table, "unsaved")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
  Nil
}
