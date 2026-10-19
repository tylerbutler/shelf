import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/list
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import test_helper
import unitest

/// Write a raw entry directly into DETS, bypassing shelf's type checks.
@external(erlang, "reload_atomicity_test_ffi", "write_raw_dets_entry")
fn write_raw_dets_entry(path: String, key: String, value: a) -> Nil

pub fn reload_failure_preserves_original_ets_data_test() -> Nil {
  let path = "/tmp/shelf_reload_atom.dets"
  test_helper.cleanup(path)

  // Open table with String keys and Int values
  let assert Ok(table) =
    set.open(
      name: "reload_atom",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // Insert valid data and save to DETS
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.save(table)

  // Write an invalid entry directly to DETS (string value instead of int)
  write_raw_dets_entry(path, "bad", "not_an_int")

  // Reload in strict mode should fail due to the invalid entry
  let assert Error(_) = set.reload(table)

  // ETS must still have the original data (not empty, not partially loaded)
  let assert Ok(1) = set.lookup(table, "a")
  let assert Ok(2) = set.lookup(table, "b")
  let assert Ok(2) = set.size(table)

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  Nil
}

pub fn successful_reload_replaces_ets_contents_test() -> Nil {
  let path = "/tmp/shelf_reload_ok.dets"
  test_helper.cleanup(path)

  let assert Ok(table) =
    set.open(
      name: "reload_ok",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // Insert and save original data
  let assert Ok(Nil) = set.insert(table, "x", 10)
  let assert Ok(Nil) = set.save(table)

  // Add unsaved data
  let assert Ok(Nil) = set.insert(table, "y", 20)
  let assert Ok(2) = set.size(table)

  // Reload should discard unsaved "y"
  let assert Ok(Nil) = set.reload(table)
  let assert Ok(1) = set.size(table)
  let assert Ok(10) = set.lookup(table, "x")
  let assert Error(_) = set.lookup(table, "y")

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  Nil
}

// Separate fixture names and a tag keep these tests safe to run while another
// worktree runs the existing suite with its fixed /tmp paths.
fn entries(count: Int) -> List(#(Int, Int)) {
  int.range(from: 0, to: count, with: [], run: fn(acc, value) {
    [#(value, value), ..acc]
  })
  |> list.reverse
}

pub fn bounded_reload_set_three_batches_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let path = "/tmp/shelf_bounded_reload_set_8f188d1a.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open("bounded_reload_set", path, "/tmp", decode.int, decode.int)
  let saved = entries(10_003)
  let assert Ok(Nil) = set.insert_list(table, saved)
  let assert Ok(Nil) = set.save(table)
  let assert Ok(Nil) = set.delete_all(table)
  let assert Ok(Nil) = set.insert(table, -1, -1)

  let assert Ok(Nil) = set.reload(table)
  let assert Ok(10_003) = set.size(table)
  let assert Error(shelf.NotFound) = set.lookup(table, -1)
  list.each(saved, fn(entry) {
    let assert Ok(value) = set.lookup(table, entry.0)
    assert value == entry.1
  })

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bounded_reload_bag_large_key_order_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let path = "/tmp/shelf_bounded_reload_bag_8f188d1a.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    bag.open("bounded_reload_bag", path, "/tmp", decode.int, decode.int)
  let saved = entries(10_003) |> list.map(fn(entry) { #(0, entry.1) })
  // Repeated pairs, including ones on opposite sides of the validation batch
  // boundaries, must remain deduplicated for bag tables.
  let assert Ok(Nil) = bag.insert_list(table, saved)
  let assert Ok(Nil) = bag.insert_list(table, saved)
  let assert Ok(Nil) = bag.insert_list(table, [#(1, 7), #(1, 8), #(2, 9)])
  let assert Ok(Nil) = bag.close(table)

  // A normal open is the ordering oracle: DETS traversal order need not match
  // the insertion order of the original table.
  let assert Ok(table) =
    bag.open("bounded_reload_bag", path, "/tmp", decode.int, decode.int)
  let assert Ok(expected) = bag.lookup(table, 0)
  assert list.length(expected) == 10_003
  let assert Ok(other) = bag.lookup(table, 1)
  let assert Ok(Nil) = bag.delete_all(table)
  let assert Ok(Nil) = bag.insert(table, -1, -1)

  let assert Ok(Nil) = bag.reload(table)
  let assert Ok(actual) = bag.lookup(table, 0)
  assert actual == expected
  let assert Ok(actual_other) = bag.lookup(table, 1)
  assert actual_other == other
  let assert Ok([9]) = bag.lookup(table, 2)
  let assert Error(shelf.NotFound) = bag.lookup(table, -1)
  let assert Ok(10_006) = bag.size(table)

  // Empty scratch must also discard unsaved live contents.
  let assert Ok(Nil) = bag.delete_all(table)
  let assert Ok(Nil) = bag.save(table)
  let assert Ok(Nil) = bag.insert(table, -1, -1)
  let assert Ok(Nil) = bag.reload(table)
  let assert Ok(0) = bag.size(table)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bounded_reload_duplicate_bag_large_key_order_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let path = "/tmp/shelf_bounded_reload_duplicates_8f188d1a.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    duplicate_bag.open(
      "bounded_reload_duplicates",
      path,
      "/tmp",
      decode.int,
      decode.int,
    )
  let saved = entries(6001) |> list.map(fn(entry) { #(0, entry.1) })
  // The same key has 12,002 objects, with repeated values separated by more
  // than one validation batch.
  let assert Ok(Nil) = duplicate_bag.insert_list(table, saved)
  let assert Ok(Nil) = duplicate_bag.insert_list(table, saved)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [#(1, 7), #(1, 7), #(2, 9)])
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table) =
    duplicate_bag.open(
      "bounded_reload_duplicates",
      path,
      "/tmp",
      decode.int,
      decode.int,
    )
  let assert Ok(expected) = duplicate_bag.lookup(table, 0)
  assert list.length(expected) == 12_002
  assert list.count(expected, fn(value) { value == 42 }) == 2
  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  let assert Ok(Nil) = duplicate_bag.insert(table, -1, -1)

  let assert Ok(Nil) = duplicate_bag.reload(table)
  let assert Ok(actual) = duplicate_bag.lookup(table, 0)
  assert actual == expected
  let assert Ok([7, 7]) = duplicate_bag.lookup(table, 1)
  let assert Ok([9]) = duplicate_bag.lookup(table, 2)
  let assert Error(shelf.NotFound) = duplicate_bag.lookup(table, -1)
  let assert Ok(12_005) = duplicate_bag.size(table)

  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  let assert Ok(Nil) = duplicate_bag.save(table)
  let assert Ok(Nil) = duplicate_bag.insert(table, -1, -1)
  let assert Ok(Nil) = duplicate_bag.reload(table)
  let assert Ok(0) = duplicate_bag.size(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn bounded_reload_failure_after_validation_batch_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let path = "/tmp/shelf_bounded_reload_failure_8f188d1a.dets"
  test_helper.cleanup(path)

  // Keep one counter message in the owner's mailbox. This forces a typed
  // decoder error on entry 5001 regardless of DETS traversal order.
  let counter = process.new_subject()
  process.send(counter, 0)
  let decoder = {
    use value <- decode.then(decode.int)
    let assert Ok(count) = process.receive(counter, 0)
    process.send(counter, count + 1)
    case count {
      5000 -> decode.failure(0, "bounded reload failure")
      _ -> decode.success(value)
    }
  }
  let assert Ok(table) =
    set.open("bounded_reload_failure", path, "/tmp", decode.int, decoder)
  let assert Ok(Nil) = set.insert_list(table, entries(10_003))
  let assert Ok(Nil) = set.save(table)
  let assert Ok(Nil) = set.delete_all(table)
  let assert Ok(Nil) = set.insert(table, -1, 99)

  let assert Error(shelf.TypeMismatch([error])) = set.reload(table)
  assert error.expected == "bounded reload failure"
  let assert Ok(5001) = process.receive(counter, 0)
  let assert Ok([#(-1, 99)]) = set.to_list(table)

  // The same handle remains usable after failure.
  process.send(counter, 5001)
  let assert Ok(Nil) = set.reload(table)
  let assert Ok(15_004) = process.receive(counter, 0)
  let assert Ok(10_003) = set.size(table)
  let assert Error(shelf.NotFound) = set.lookup(table, -1)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bounded_reload_ownership_empty_and_closed_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let path = "/tmp/shelf_bounded_reload_lifecycle_8f188d1a.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open("bounded_reload_lifecycle", path, "/tmp", decode.int, decode.int)
  let assert Ok(Nil) = set.insert(table, -1, 99)
  let reply = process.new_subject()
  process.spawn(fn() { process.send(reply, set.reload(table)) })
  let assert Ok(Error(shelf.NotOwner)) = process.receive(reply, 5000)
  let assert Ok([#(-1, 99)]) = set.to_list(table)

  let assert Ok(Nil) = set.reload(table)
  let assert Ok(0) = set.size(table)
  let assert Ok(Nil) = set.close(table)
  let assert Error(shelf.TableClosed) = set.reload(table)
  test_helper.cleanup(path)
}

pub fn bounded_reload_bag_end_marker_key_test() -> Nil {
  use <- unitest.tag("bounded_reload")
  let end_key = atom.create("$end_of_table")
  let other_key = atom.create("other")
  let saved = [#(end_key, 1), #(end_key, 2), #(other_key, 3)]
  let bag_path = "/tmp/shelf_bounded_reload_bag_end_key_8f188d1a.dets"
  let duplicates_path =
    "/tmp/shelf_bounded_reload_duplicates_end_key_8f188d1a.dets"
  test_helper.cleanup(bag_path)
  test_helper.cleanup(duplicates_path)

  let assert Ok(table) =
    bag.open(
      "bounded_reload_end_key",
      bag_path,
      "/tmp",
      atom.decoder(),
      decode.int,
    )
  let assert Ok(Nil) = bag.insert_list(table, saved)
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(table) =
    bag.open(
      "bounded_reload_end_key",
      bag_path,
      "/tmp",
      atom.decoder(),
      decode.int,
    )
  let assert Ok(expected) = bag.lookup(table, end_key)
  let assert Ok(Nil) = bag.delete_all(table)
  let assert Ok(Nil) = bag.reload(table)
  let assert Ok(actual) = bag.lookup(table, end_key)
  assert actual == expected
  let assert Ok([3]) = bag.lookup(table, other_key)
  let assert Ok(3) = bag.size(table)
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table) =
    duplicate_bag.open(
      "bounded_reload_end_key",
      duplicates_path,
      "/tmp",
      atom.decoder(),
      decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert_list(table, saved)
  let assert Ok(Nil) = duplicate_bag.insert(table, end_key, 1)
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table) =
    duplicate_bag.open(
      "bounded_reload_end_key",
      duplicates_path,
      "/tmp",
      atom.decoder(),
      decode.int,
    )
  let assert Ok(expected) = duplicate_bag.lookup(table, end_key)
  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  let assert Ok(Nil) = duplicate_bag.reload(table)
  let assert Ok(actual) = duplicate_bag.lookup(table, end_key)
  assert actual == expected
  let assert Ok([3]) = duplicate_bag.lookup(table, other_key)
  let assert Ok(4) = duplicate_bag.size(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(bag_path)
  test_helper.cleanup(duplicates_path)
}
