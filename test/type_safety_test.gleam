import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/internal
import shelf/set
import storage_safety_test
import test_helper
import unitest

type RawDetsError {
  RawDetsError(String)
}

@external(erlang, "type_safety_test_ffi", "write_raw_dets")
fn write_raw_dets(
  path: String,
  table_type: internal.TableKind,
  entries: List(a),
) -> Result(Nil, RawDetsError)

@external(erlang, "type_safety_test_ffi", "read_raw_dets")
fn read_raw_dets(
  path: String,
  table_type: internal.TableKind,
) -> Result(List(Dynamic), RawDetsError)

pub fn malformed_entries() -> List(Dynamic) {
  [
    dynamic.array([dynamic.string("bad")]),
    dynamic.array([
      dynamic.string("bad"),
      dynamic.int(2),
      dynamic.string("extra payload"),
    ]),
    dynamic.array([
      dynamic.string("bad"),
      dynamic.int(2),
      dynamic.int(3),
      dynamic.int(4),
    ]),
  ]
}

pub fn assert_pair_shape_error(
  result: Result(a, shelf.ShelfError),
  entry: Dynamic,
) -> Nil {
  let assert Error(shelf.TypeMismatch([error])) = result
  assert error.expected == "Tuple of size 2"
  assert error.found == dynamic.classify(entry)
  assert error.path == []
}

fn rejects_oversized_entries(
  kind: internal.TableKind,
  open: fn(String, String) -> Result(table, shelf.ShelfError),
) -> Nil {
  use directory <- storage_safety_test.with_directory
  let path = directory <> "/table.dets"
  list.each(malformed_entries(), fn(entry) {
    let entries = [
      dynamic.array([dynamic.string("good"), dynamic.int(1)]),
      entry,
    ]
    let assert Ok(Nil) = write_raw_dets(path, kind, entries)
    assert_pair_shape_error(open(path, directory), entry)
    // Failed open must release its reservation without saving decoded pairs.
    assert_pair_shape_error(open(path, directory), entry)
    let assert Ok(actual) = read_raw_dets(path, kind)
    assert list.length(actual) == list.length(entries)
    list.each(entries, fn(original) {
      assert list.contains(actual, original)
    })
    test_helper.cleanup(path)
  })
}

pub fn strict_arity_set_open_test() -> Nil {
  use <- unitest.tag("strict_arity")
  rejects_oversized_entries(internal.Set, fn(path, directory) {
    set.open("strict_set", path, directory, decode.string, decode.int)
  })
}

pub fn strict_arity_bag_open_test() -> Nil {
  use <- unitest.tag("strict_arity")
  rejects_oversized_entries(internal.Bag, fn(path, directory) {
    bag.open("strict_bag", path, directory, decode.string, decode.int)
  })
}

pub fn strict_arity_duplicate_bag_open_test() -> Nil {
  use <- unitest.tag("strict_arity")
  rejects_oversized_entries(internal.DuplicateBag, fn(path, directory) {
    duplicate_bag.open(
      "strict_duplicate_bag",
      path,
      directory,
      decode.string,
      decode.int,
    )
  })
}

pub fn strict_arity_checks_shape_before_decoding_test() -> Nil {
  use <- unitest.tag("strict_arity")
  use directory <- storage_safety_test.with_directory
  let path = directory <> "/table.dets"
  let key_decoder: decode.Decoder(String) = {
    use _ <- decode.then(decode.string)
    panic as "Malformed records must not reach field decoders"
  }
  list.each(malformed_entries(), fn(entry) {
    let assert Ok(Nil) = write_raw_dets(path, internal.Set, [entry])
    assert_pair_shape_error(
      set.open("strict_before_decode", path, directory, key_decoder, decode.int),
      entry,
    )
    test_helper.cleanup(path)
  })
}

pub fn strict_arity_preserves_valid_pairs_test() -> Nil {
  use <- unitest.tag("strict_arity")
  use directory <- storage_safety_test.with_directory
  let path = directory <> "/pairs.dets"
  list.each(
    [
      #(internal.Set, 1, 0),
      #(internal.Bag, 1, 1),
      #(internal.DuplicateBag, 2, 1),
    ],
    fn(test_case) {
      let #(kind, ones, twos) = test_case
      let assert Ok(Nil) =
        write_raw_dets(path, kind, [#("key", 1), #("key", 2), #("key", 1)])
      let config = shelf.config("strict_pairs", path, directory)
      let assert Ok(#(ets, dets, guardian, _, decoder)) =
        internal.generic_open(config, kind, decode.string, decode.int)
      let assert Ok(entries) = internal.to_list(ets)
      assert list.count(entries, fn(entry) { entry == #("key", 1) }) == ones
      assert list.count(entries, fn(entry) { entry == #("key", 2) }) == twos
      assert list.length(entries) == ones + twos
      let assert Ok(Nil) = internal.save(ets, dets)
      let assert Ok(Nil) = internal.generic_reload(ets, dets, decoder)
      let assert Ok(reloaded) = internal.to_list(ets)
      assert reloaded == entries
      let assert Ok(Nil) = internal.close(ets, dets, guardian)
      let assert Ok(#(ets, dets, guardian, _, _)) =
        internal.generic_open(config, kind, decode.string, decode.int)
      let assert Ok(reopened) = internal.to_list(ets)
      assert reopened == entries
      let assert Ok(Nil) = internal.close(ets, dets, guardian)
      test_helper.cleanup(path)
    },
  )
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
