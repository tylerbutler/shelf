import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import shelf/set
import test_helper

pub fn multiple_processes_can_read_simultaneously_test() -> Nil {
  let path = "/tmp/shelf_conc_read.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "conc_read",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // Insert test data
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.insert(table, "c", 3)

  // Spawn 10 processes that all read concurrently
  let subject = process.new_subject()
  int.range(10, 0, [], list.prepend)
  |> list.each(fn(_i) {
    process.spawn(fn() {
      let first_lookup = set.lookup(table, "a")
      let second_lookup = set.lookup(table, "b")
      let third_lookup = set.lookup(table, "c")
      process.send(subject, #(first_lookup, second_lookup, third_lookup))
    })
  })

  // Collect all results
  int.range(10, 0, [], list.prepend)
  |> list.each(fn(_i) {
    let assert Ok(#(first_lookup, second_lookup, third_lookup)) =
      process.receive(subject, 5000)
    assert first_lookup == Ok(1)
    assert second_lookup == Ok(2)
    assert third_lookup == Ok(3)
    Nil
  })

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn rapid_owner_process_writes_to_different_keys_all_succeed_test() -> Nil {
  let path = "/tmp/shelf_conc_write_diff.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "conc_write_diff",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // Rapidly write many different keys
  let count = 100
  int.range(count, 0, [], list.prepend)
  |> list.each(fn(i) {
    let key = "key_" <> int.to_string(i)
    let assert Ok(Nil) = set.insert(table, key, i)
    Nil
  })

  // Verify all keys were written correctly
  int.range(count, 0, [], list.prepend)
  |> list.each(fn(i) {
    let key = "key_" <> int.to_string(i)
    assert set.lookup(table, key) == Ok(i)
    Nil
  })

  // Verify size
  let assert Ok(size) = set.size(table)
  assert size == count

  // Spawn readers to verify data concurrently
  let subject = process.new_subject()
  int.range(10, 0, [], list.prepend)
  |> list.each(fn(i) {
    process.spawn(fn() {
      let key = "key_" <> int.to_string(i * 10)
      let result = set.lookup(table, key)
      process.send(subject, #(key, result))
    })
  })

  int.range(10, 0, [], list.prepend)
  |> list.each(fn(i) {
    let assert Ok(#(_key, Ok(value))) = process.receive(subject, 5000)
    assert value >= 1 && value <= count
    // Suppress unused variable warning
    let _ = i
    Nil
  })

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn rapid_owner_process_overwrites_to_same_key_last_write_wins_test() -> Nil {
  let path = "/tmp/shelf_conc_write_same.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "conc_write_same",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // Rapidly overwrite the same key many times
  let count = 100
  int.range(count, 0, [], list.prepend)
  |> list.each(fn(i) {
    let assert Ok(Nil) = set.insert(table, "shared", i)
    Nil
  })

  // Last write should win
  let assert Ok(value) = set.lookup(table, "shared")
  assert value == count

  // Table should still be fully functional
  let assert Ok(Nil) = set.insert(table, "after", 999)
  assert set.lookup(table, "after") == Ok(999)

  // Concurrent reads should see consistent state
  let subject = process.new_subject()
  int.range(5, 0, [], list.prepend)
  |> list.each(fn(_i) {
    process.spawn(fn() {
      let result = set.lookup(table, "shared")
      process.send(subject, result)
    })
  })

  int.range(5, 0, [], list.prepend)
  |> list.each(fn(_i) {
    let assert Ok(Ok(value)) = process.receive(subject, 5000)
    assert value == count
    Nil
  })

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  Nil
}
