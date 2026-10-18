import gleam/dynamic/decode
import shelf
import shelf/set
import test_helpers

pub fn missing_key_returns_not_found_test() {
  let path = "/tmp/shelf_uc_missing.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "uc_missing",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let assert True =
    set.update_counter(table, "nonexistent", 1) == Error(shelf.NotFound)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn multiple_increments_accumulate_correctly_test() {
  let path = "/tmp/shelf_uc_multi.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "uc_multi",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let assert Ok(Nil) = set.insert(table, "hits", 0)
  let assert Ok(1) = set.update_counter(table, "hits", 1)
  let assert Ok(3) = set.update_counter(table, "hits", 2)
  let assert Ok(6) = set.update_counter(table, "hits", 3)
  let assert Ok(10) = set.update_counter(table, "hits", 4)

  let assert True = set.lookup(table, "hits") == Ok(10)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn negative_increment_decrements_value_test() {
  let path = "/tmp/shelf_uc_neg.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "uc_neg",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let assert Ok(Nil) = set.insert(table, "counter", 10)
  let assert Ok(new_val) = set.update_counter(table, "counter", -3)
  let assert True = new_val == 7

  let assert True = set.lookup(table, "counter") == Ok(7)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn zero_increment_returns_current_value_test() {
  let path = "/tmp/shelf_uc_zero.dets"
  test_helpers.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "uc_zero",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  let assert Ok(Nil) = set.insert(table, "counter", 42)
  let assert Ok(new_val) = set.update_counter(table, "counter", 0)
  let assert True = new_val == 42

  let assert True = set.lookup(table, "counter") == Ok(42)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}
