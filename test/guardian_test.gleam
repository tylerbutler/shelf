import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process.{type Pid}
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}
import startest/expect

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Dynamic)

@external(erlang, "guardian_test_ffi", "extract_guardian")
fn extract_guardian_set(table: set.PSet(k, v)) -> Pid

@external(erlang, "guardian_test_ffi", "extract_guardian")
fn extract_guardian_bag(table: bag.PBag(k, v)) -> Pid

@external(erlang, "guardian_test_ffi", "extract_guardian")
fn extract_guardian_duplicate_bag(
  table: duplicate_bag.PDuplicateBag(k, v),
) -> Pid

pub fn guardian_tests() {
  describe("guardian lifecycle", [
    it("guardian is alive while table is open", fn() {
      let path = "/tmp/shelf_guardian_alive.dets"
      cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "guardian_alive",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_set(table)
      expect.to_equal(process.is_alive(guardian), True)

      let assert Ok(Nil) = set.close(table)
      cleanup(path)
      Nil
    }),
    it("guardian is stopped after set close", fn() {
      let path = "/tmp/shelf_guardian_set_close.dets"
      cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "guardian_set_close",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_set(table)
      let assert Ok(Nil) = set.close(table)

      // Small delay to allow the guardian to process the stop message
      process.sleep(10)
      expect.to_equal(process.is_alive(guardian), False)

      cleanup(path)
      Nil
    }),
    it("guardian is stopped after bag close", fn() {
      let path = "/tmp/shelf_guardian_bag_close.dets"
      cleanup(path)

      let assert Ok(table) =
        bag.open(
          name: "guardian_bag_close",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_bag(table)
      let assert Ok(Nil) = bag.close(table)

      process.sleep(10)
      expect.to_equal(process.is_alive(guardian), False)

      cleanup(path)
      Nil
    }),
    it("guardian is stopped after duplicate_bag close", fn() {
      let path = "/tmp/shelf_guardian_dupbag_close.dets"
      cleanup(path)

      let assert Ok(table) =
        duplicate_bag.open(
          name: "guardian_dupbag_close",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_duplicate_bag(table)
      let assert Ok(Nil) = duplicate_bag.close(table)

      process.sleep(10)
      expect.to_equal(process.is_alive(guardian), False)

      cleanup(path)
      Nil
    }),
    it("guardian is stopped after with_table completes", fn() {
      let path = "/tmp/shelf_guardian_with_table.dets"
      cleanup(path)

      // We need to capture the guardian PID from inside with_table
      let assert Ok(guardian) =
        set.with_table(
          "guardian_with_table",
          path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
          fun: fn(table) { Ok(extract_guardian_set(table)) },
        )

      process.sleep(10)
      expect.to_equal(process.is_alive(guardian), False)

      cleanup(path)
      Nil
    }),
    it("opening and closing many tables does not leak guardians", fn() {
      let path = "/tmp/shelf_guardian_leak.dets"
      cleanup(path)

      // Open and close 10 tables, collect guardian PIDs
      let guardians = open_close_collect(path, 10, [])

      process.sleep(20)
      // All guardians should be dead
      let all_dead =
        guardians
        |> list_all(fn(pid) { !process.is_alive(pid) })
      expect.to_equal(all_dead, True)

      cleanup(path)
      Nil
    }),
  ])
}

fn open_close_collect(path: String, remaining: Int, acc: List(Pid)) -> List(Pid) {
  case remaining {
    0 -> acc
    n -> {
      let name = "guardian_leak_" <> int_to_string(n)
      let assert Ok(table) =
        set.open(
          name: name,
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let guardian = extract_guardian_set(table)
      let assert Ok(Nil) = set.close(table)
      open_close_collect(path, n - 1, [guardian, ..acc])
    }
  }
}

fn list_all(items: List(a), predicate: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [first, ..rest] ->
      case predicate(first) {
        True -> list_all(rest, predicate)
        False -> False
      }
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String
