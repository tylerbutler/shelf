import gleam/dynamic/decode
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import test_helper

@external(erlang, "guardian_test_ffi", "extract_guardian")
pub fn extract_guardian_set(table: set.PersistentSet(k, v)) -> Pid

@external(erlang, "guardian_test_ffi", "extract_guardian")
pub fn extract_guardian_bag(table: bag.PersistentBag(k, v)) -> Pid

@external(erlang, "guardian_test_ffi", "extract_guardian")
pub fn extract_guardian_duplicate_bag(
  table: duplicate_bag.PersistentDuplicateBag(k, v),
) -> Pid

pub fn guardian_is_alive_while_table_is_open_test() -> Nil {
  let path = "/tmp/shelf_guardian_alive.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "guardian_alive",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let guardian = extract_guardian_set(table)
  assert process.is_alive(guardian) == True

  let monitor = process.monitor(guardian)
  let assert Ok(Nil) = set.close(table)
  test_helper.await_guardian(monitor, guardian)
  test_helper.cleanup(path)
  Nil
}

pub fn guardian_is_stopped_after_set_close_test() -> Nil {
  let path = "/tmp/shelf_guardian_set_close.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "guardian_set_close",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let guardian = extract_guardian_set(table)
  let monitor = process.monitor(guardian)
  let assert Ok(Nil) = set.close(table)

  test_helper.await_guardian(monitor, guardian)
  assert process.is_alive(guardian) == False

  test_helper.cleanup(path)
  Nil
}

pub fn guardian_is_stopped_after_bag_close_test() -> Nil {
  let path = "/tmp/shelf_guardian_bag_close.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    bag.open(
      name: "guardian_bag_close",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let guardian = extract_guardian_bag(table)
  let monitor = process.monitor(guardian)
  let assert Ok(Nil) = bag.close(table)

  test_helper.await_guardian(monitor, guardian)
  assert process.is_alive(guardian) == False

  test_helper.cleanup(path)
  Nil
}

pub fn guardian_is_stopped_after_duplicate_bag_close_test() -> Nil {
  let path = "/tmp/shelf_guardian_dupbag_close.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    duplicate_bag.open(
      name: "guardian_dupbag_close",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let guardian = extract_guardian_duplicate_bag(table)
  let monitor = process.monitor(guardian)
  let assert Ok(Nil) = duplicate_bag.close(table)

  test_helper.await_guardian(monitor, guardian)
  assert process.is_alive(guardian) == False

  test_helper.cleanup(path)
  Nil
}

pub fn guardian_is_stopped_after_with_table_completes_test() -> Nil {
  let path = "/tmp/shelf_guardian_with_table.dets"
  test_helper.cleanup(path)

  // We need to capture the guardian PID from inside with_table
  let assert Ok(#(guardian, monitor)) =
    set.with_table(
      "guardian_with_table",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
      fun: fn(table) {
        let guardian = extract_guardian_set(table)
        Ok(#(guardian, process.monitor(guardian)))
      },
    )

  test_helper.await_guardian(monitor, guardian)
  assert process.is_alive(guardian) == False

  test_helper.cleanup(path)
  Nil
}

pub fn opening_and_closing_many_tables_does_not_leak_guardians_test() -> Nil {
  let path = "/tmp/shelf_guardian_leak.dets"
  test_helper.cleanup(path)

  // Open and close 10 tables, collect guardian PIDs
  let guardians = open_close_collect(path, 10, [])

  // All guardians should be dead
  let all_dead =
    guardians
    |> list.all(fn(pid) { !process.is_alive(pid) })
  assert all_dead == True

  test_helper.cleanup(path)
  Nil
}

fn open_close_collect(path: String, remaining: Int, acc: List(Pid)) -> List(Pid) {
  case remaining {
    0 -> acc
    n -> {
      let name = "guardian_leak_" <> int.to_string(n)
      let assert Ok(table) =
        set.open(
          name: name,
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_set(table)
      let monitor = process.monitor(guardian)
      let assert Ok(Nil) = set.close(table)
      test_helper.await_guardian(monitor, guardian)
      open_close_collect(path, n - 1, [guardian, ..acc])
    }
  }
}
