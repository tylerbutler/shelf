import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/internal
import shelf/set
import test_helper

type RawDetsError {
  RawDetsError(String)
}

@external(erlang, "type_safety_test_ffi", "write_raw_dets")
fn write_raw_dets(
  path: String,
  table_type: internal.TableKind,
  entries: List(#(Dynamic, Dynamic)),
) -> Result(Nil, RawDetsError)

@external(erlang, "close_test_ffi", "with_close_recovery_fixture")
fn with_table_fixture(fun: fn(String) -> a) -> a

pub fn native_table_kind_mismatch_has_typed_detail_test() -> Nil {
  list.each(
    [internal.Set, internal.Bag, internal.DuplicateBag],
    fn(stored_kind) {
      use path <- with_table_fixture()
      let assert Ok(path) = shelf.validate_path(path, "/tmp")
      let assert Ok(Nil) =
        write_raw_dets(path, stored_kind, [
          #(dynamic.string("key"), dynamic.string("preserved")),
        ])
      assert_table_kind_result(
        set.open("kind", path, "/tmp", decode.string, decode.string),
        stored_kind == internal.Set,
        fn(table) { set.lookup(table, "key") },
        set.close,
      )
      assert_table_kind_result(
        bag.open("kind", path, "/tmp", decode.string, decode.string),
        stored_kind == internal.Bag,
        fn(table) {
          let assert Ok(["preserved"]) = bag.lookup(table, "key")
          Ok("preserved")
        },
        bag.close,
      )
      assert_table_kind_result(
        duplicate_bag.open("kind", path, "/tmp", decode.string, decode.string),
        stored_kind == internal.DuplicateBag,
        fn(table) {
          let assert Ok(["preserved"]) = duplicate_bag.lookup(table, "key")
          Ok("preserved")
        },
        duplicate_bag.close,
      )
      // Reopen after every incompatible kind has been attempted.
      let assert Ok(#(ets, dets, guardian)) =
        internal.open_no_load("kind", path, stored_kind)
      let assert Ok(Nil) =
        internal.stream_validate_and_load(
          ets,
          dets,
          internal.build_entry_decoder(decode.string, decode.string),
        )
      let assert Ok([#("key", "preserved")]) = internal.to_list(ets)
      let assert Ok(Nil) = internal.close(ets, dets, guardian)
      Nil
    },
  )
}

fn assert_table_kind_result(
  result: Result(table, shelf.ShelfError),
  compatible: Bool,
  lookup: fn(table) -> Result(String, shelf.ShelfError),
  close: fn(table) -> Result(Nil, shelf.ShelfError),
) -> Nil {
  case compatible {
    True -> {
      let assert Ok(table) = result
      let assert Ok("preserved") = lookup(table)
      let assert Ok(Nil) = close(table)
      Nil
    }
    False -> {
      let assert Error(shelf.FileError(detail)) = result
      assert string.contains(detail, "DETS file has a different table type")
      assert string.contains(detail, "table.dets")
    }
  }
}

pub fn native_table_kind_decoder_errors_remain_usable_test() -> Nil {
  use path <- with_table_fixture()
  let assert Ok(table) =
    set.open("decoder", path, "/tmp", decode.string, decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "preserved")
  let assert Ok(Nil) = set.close(table)
  let assert Error(shelf.TypeMismatch(errors)) =
    set.open("decoder", path, "/tmp", decode.string, decode.int)
  let assert [error, ..] = errors
  assert error.expected == "Int"
  assert error.found != ""
  assert error.path == ["1"]
  let assert Ok(table) =
    set.open("decoder", path, "/tmp", decode.string, decode.string)
  let assert Ok("preserved") = set.lookup(table, "key")
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn rejects_dets_data_with_wrong_value_type_test() -> Nil {
  let path = "/tmp/shelf_ts_wrong_value.dets"
  test_helper.cleanup(path)

  // Write String values using the correct API.
  let assert Ok(table) =
    set.open(
      name: "ts_wrong_value_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key", "hello")
  let assert Ok(Nil) = set.close(table)

  // Reopen expecting Int values — should fail with TypeMismatch.
  let assert Error(shelf.TypeMismatch(_)) =
    set.open(
      name: "ts_wrong_value_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  test_helper.cleanup(path)
}

pub fn rejects_dets_data_with_wrong_key_type_test() -> Nil {
  let path = "/tmp/shelf_ts_wrong_key.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "ts_wrong_key_1",
      path: path,
      base_directory: "/tmp",
      key: decode.int,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, 1, "hello")
  let assert Ok(Nil) = set.close(table)

  let assert Error(shelf.TypeMismatch(_)) =
    set.open(
      name: "ts_wrong_key_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  test_helper.cleanup(path)
}

pub fn accepts_dets_data_with_correct_types_test() -> Nil {
  let path = "/tmp/shelf_ts_correct.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "ts_correct_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "count", 42)
  let assert Ok(Nil) = set.close(table)

  // Reopen with the same types — should succeed.
  let assert Ok(table) =
    set.open(
      name: "ts_correct_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(42) = set.lookup(table, "count")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn opens_empty_dets_file_with_any_decoder_test() -> Nil {
  let path = "/tmp/shelf_ts_empty.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "ts_empty_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.close(table)

  // Reopen with different types — no data to validate.
  let assert Ok(table) =
    set.open(
      name: "ts_empty_2",
      path: path,
      base_directory: "/tmp",
      key: decode.int,
      value: decode.float,
    )
  let assert Ok(0) = set.size(table)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn rejects_if_any_entry_is_invalid_test() -> Nil {
  let path = "/tmp/shelf_ts_strict_reject.dets"
  test_helper.cleanup(path)

  let assert Ok(Nil) =
    write_raw_dets(path, internal.Set, [
      #(dynamic.string("good"), dynamic.int(1)),
      #(dynamic.int(999), dynamic.string("bad")),
    ])

  let assert Error(shelf.TypeMismatch(_)) =
    set.open(
      name: "ts_strict_reject",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  test_helper.cleanup(path)
}

pub fn rejects_bag_dets_data_with_wrong_types_test() -> Nil {
  let path = "/tmp/shelf_ts_bag_wrong.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    bag.open(
      name: "ts_bag_wrong_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
  let assert Ok(Nil) = bag.close(table)

  let assert Error(shelf.TypeMismatch(_)) =
    bag.open(
      name: "ts_bag_wrong_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  test_helper.cleanup(path)
}

pub fn rejects_duplicate_bag_dets_data_with_wrong_types_test() -> Nil {
  let path = "/tmp/shelf_ts_dbag_wrong.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    duplicate_bag.open(
      name: "ts_dbag_wrong_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Error(shelf.TypeMismatch(_)) =
    duplicate_bag.open(
      name: "ts_dbag_wrong_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  test_helper.cleanup(path)
}

pub fn bag_preserves_value_order_after_save_and_reload_test() -> Nil {
  let path = "/tmp/shelf_ts_bag_order.dets"
  test_helper.cleanup(path)

  let assert Ok(Nil) =
    write_raw_dets(path, internal.Bag, [
      #(dynamic.string("color"), dynamic.string("red")),
      #(dynamic.string("color"), dynamic.string("green")),
      #(dynamic.string("color"), dynamic.string("blue")),
    ])

  let assert Ok(table) =
    bag.open(
      name: "ts_bag_order",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(values) = bag.lookup(table, "color")
  let assert [first, _, last] = values
  assert first != last
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_preserves_value_order_after_save_and_reload_test() -> Nil {
  let path = "/tmp/shelf_ts_dbag_order.dets"
  test_helper.cleanup(path)

  let assert Ok(Nil) =
    write_raw_dets(path, internal.DuplicateBag, [
      #(dynamic.string("log"), dynamic.string("first")),
      #(dynamic.string("log"), dynamic.string("second")),
      #(dynamic.string("log"), dynamic.string("third")),
    ])

  let assert Ok(table) =
    duplicate_bag.open(
      name: "ts_dbag_order",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table, "log")
  let assert [first, _, last] = values
  assert first != last
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn multiple_tables_with_same_name_can_coexist_test() -> Nil {
  let first_path = "/tmp/shelf_ts_dets_leak1.dets"
  let second_path = "/tmp/shelf_ts_dets_leak2.dets"
  test_helper.cleanup(first_path)
  test_helper.cleanup(second_path)

  // ETS tables are unnamed, so a diagnostic name can be shared.
  let assert Ok(first_table) =
    set.open(
      name: "ts_same_name",
      path: first_path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(second_table) =
    set.open(
      name: "ts_same_name",
      path: second_path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(first_table, "key", "val1")
  let assert Ok(Nil) = set.insert(second_table, "key", "val2")
  let assert Ok("val1") = set.lookup(first_table, "key")
  let assert Ok("val2") = set.lookup(second_table, "key")
  let assert Ok(Nil) = set.close(first_table)
  let assert Ok(Nil) = set.close(second_table)
  test_helper.cleanup(first_path)
  test_helper.cleanup(second_path)
}

pub fn raw_dets_open_failure_has_typed_detail_test() -> Nil {
  let path = "/tmp/shelf_ts_raw_missing"
  test_helper.delete_directory(path)
  let assert Error(RawDetsError(detail)) =
    write_raw_dets(path <> "/table.dets", internal.Set, [])
  assert detail != ""
}
