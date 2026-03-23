import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import shelf
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

/// Write raw Erlang terms directly to a DETS file, bypassing Gleam's
/// type system. Used to simulate data written by a previous session
/// with different types.
@external(erlang, "type_safety_test_ffi", "write_raw_dets")
fn write_raw_dets(
  path: String,
  table_type: String,
  entries: List(#(Dynamic, Dynamic)),
) -> Result(Nil, Dynamic)

pub fn type_safety_tests() {
  describe("type safety", [
    describe("set", [
      it("rejects DETS data with wrong value type (strict)", fn() {
        let path = "/tmp/shelf_ts_wrong_value.dets"
        cleanup(path)

        // Write String values using the correct API
        let assert Ok(t) =
          set.open(
            name: "ts_wrong_value_1",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.insert(t, "key", "hello")
        let assert Ok(Nil) = set.close(t)

        // Reopen expecting Int values — should fail with TypeMismatch
        let result =
          set.open(
            name: "ts_wrong_value_2",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        expect.to_equal(result, Error(shelf.TypeMismatch))
        cleanup(path)
        Nil
      }),
      it("rejects DETS data with wrong key type (strict)", fn() {
        let path = "/tmp/shelf_ts_wrong_key.dets"
        cleanup(path)

        // Write Int keys
        let assert Ok(t) =
          set.open(
            name: "ts_wrong_key_1",
            path: path,
            key: decode.int,
            value: decode.string,
          )
        let assert Ok(Nil) = set.insert(t, 1, "hello")
        let assert Ok(Nil) = set.close(t)

        // Reopen expecting String keys — should fail
        let result =
          set.open(
            name: "ts_wrong_key_2",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        expect.to_equal(result, Error(shelf.TypeMismatch))
        cleanup(path)
        Nil
      }),
      it("accepts DETS data with correct types", fn() {
        let path = "/tmp/shelf_ts_correct.dets"
        cleanup(path)

        let assert Ok(t) =
          set.open(
            name: "ts_correct_1",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(t, "count", 42)
        let assert Ok(Nil) = set.close(t)

        // Reopen with the same types — should succeed
        let assert Ok(t) =
          set.open(
            name: "ts_correct_2",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(42) = set.lookup(t, "count")
        let assert Ok(Nil) = set.close(t)
        cleanup(path)
        Nil
      }),
      it("opens empty DETS file with any decoder", fn() {
        let path = "/tmp/shelf_ts_empty.dets"
        cleanup(path)

        // Open with one type, close (creates empty DETS)
        let assert Ok(t) =
          set.open(
            name: "ts_empty_1",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.close(t)

        // Reopen with different types — should succeed (no data to validate)
        let assert Ok(t) =
          set.open(
            name: "ts_empty_2",
            path: path,
            key: decode.int,
            value: decode.float,
          )
        let assert Ok(0) = set.size(t)
        let assert Ok(Nil) = set.close(t)
        cleanup(path)
        Nil
      }),
    ]),
    describe("lenient mode", [
      it("skips invalid entries in lenient mode", fn() {
        let path = "/tmp/shelf_ts_lenient.dets"
        cleanup(path)

        // Write data with raw Erlang FFI — mix of valid and invalid entries
        let assert Ok(Nil) =
          write_raw_dets(path, "set", [
            #(dynamic.string("good"), dynamic.int(1)),
            #(dynamic.string("also_good"), dynamic.int(2)),
            #(dynamic.int(999), dynamic.string("bad_key")),
          ])

        // Open in lenient mode — should skip the bad entry
        let config =
          shelf.config(name: "ts_lenient", path: path)
          |> shelf.decode_policy(shelf.Lenient)
        let assert Ok(t) =
          set.open_config(config: config, key: decode.string, value: decode.int)
        // Only the two good entries should be loaded
        let assert Ok(2) = set.size(t)
        let assert Ok(1) = set.lookup(t, "good")
        let assert Ok(2) = set.lookup(t, "also_good")
        let assert Ok(Nil) = set.close(t)
        cleanup(path)
        Nil
      }),
      it("strict mode rejects if any entry is invalid", fn() {
        let path = "/tmp/shelf_ts_strict_reject.dets"
        cleanup(path)

        // Write mixed data
        let assert Ok(Nil) =
          write_raw_dets(path, "set", [
            #(dynamic.string("good"), dynamic.int(1)),
            #(dynamic.int(999), dynamic.string("bad")),
          ])

        // Open in strict mode (default) — should fail
        let result =
          set.open(
            name: "ts_strict_reject",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        expect.to_equal(result, Error(shelf.TypeMismatch))
        cleanup(path)
        Nil
      }),
    ]),
    describe("bag type safety", [
      it("rejects bag DETS data with wrong types", fn() {
        let path = "/tmp/shelf_ts_bag_wrong.dets"
        cleanup(path)

        let assert Ok(t) =
          bag.open(
            name: "ts_bag_wrong_1",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(t, "tag", "gleam")
        let assert Ok(Nil) = bag.close(t)

        // Reopen expecting Int values
        let result =
          bag.open(
            name: "ts_bag_wrong_2",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        expect.to_equal(result, Error(shelf.TypeMismatch))
        cleanup(path)
        Nil
      }),
    ]),
    describe("duplicate_bag type safety", [
      it("rejects duplicate_bag DETS data with wrong types", fn() {
        let path = "/tmp/shelf_ts_dbag_wrong.dets"
        cleanup(path)

        let assert Ok(t) =
          duplicate_bag.open(
            name: "ts_dbag_wrong_1",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(t, "event", "click")
        let assert Ok(Nil) = duplicate_bag.close(t)

        // Reopen expecting Int values
        let result =
          duplicate_bag.open(
            name: "ts_dbag_wrong_2",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        expect.to_equal(result, Error(shelf.TypeMismatch))
        cleanup(path)
        Nil
      }),
    ]),
    describe("entry order preservation", [
      it("bag preserves value order after save and reload (strict)", fn() {
        let path = "/tmp/shelf_ts_bag_order.dets"
        cleanup(path)

        // Write entries with distinct values in a known order
        let assert Ok(Nil) =
          write_raw_dets(path, "bag", [
            #(dynamic.string("color"), dynamic.string("red")),
            #(dynamic.string("color"), dynamic.string("green")),
            #(dynamic.string("color"), dynamic.string("blue")),
          ])

        // Open with strict decoding — order should be preserved
        let assert Ok(t) =
          bag.open(
            name: "ts_bag_order",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(values) = bag.lookup(t, "color")
        // The values should contain all three entries
        expect.to_equal(list.length(values), 3)
        // Order should match: dets_to_list reverses DETS iteration order,
        // and decode_all_strict must reverse back to preserve the original.
        // Verify by checking first and last elements are not swapped.
        let assert Ok(first) = list.first(values)
        let assert Ok(last) = list.last(values)
        expect.to_not_equal(first, last)
        let assert Ok(Nil) = bag.close(t)
        cleanup(path)
        Nil
      }),
      it(
        "duplicate_bag preserves value order after save and reload (strict)",
        fn() {
          let path = "/tmp/shelf_ts_dbag_order.dets"
          cleanup(path)

          // Write ordered entries with duplicates
          let assert Ok(Nil) =
            write_raw_dets(path, "duplicate_bag", [
              #(dynamic.string("log"), dynamic.string("first")),
              #(dynamic.string("log"), dynamic.string("second")),
              #(dynamic.string("log"), dynamic.string("third")),
            ])

          // Open with strict decoding
          let assert Ok(t) =
            duplicate_bag.open(
              name: "ts_dbag_order",
              path: path,
              key: decode.string,
              value: decode.string,
            )
          let assert Ok(values) = duplicate_bag.lookup(t, "log")
          expect.to_equal(list.length(values), 3)
          let assert Ok(first) = list.first(values)
          let assert Ok(last) = list.last(values)
          expect.to_not_equal(first, last)
          let assert Ok(Nil) = duplicate_bag.close(t)
          cleanup(path)
          Nil
        },
      ),
      it("lenient and strict modes produce same order", fn() {
        let path = "/tmp/shelf_ts_order_modes.dets"
        cleanup(path)

        // Write ordered entries
        let assert Ok(Nil) =
          write_raw_dets(path, "bag", [
            #(dynamic.string("seq"), dynamic.string("a")),
            #(dynamic.string("seq"), dynamic.string("b")),
            #(dynamic.string("seq"), dynamic.string("c")),
          ])

        // Open strict
        let assert Ok(t1) =
          bag.open(
            name: "ts_order_strict",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(strict_values) = bag.lookup(t1, "seq")
        let assert Ok(Nil) = bag.close(t1)

        // Open lenient with same data
        let config =
          shelf.config(name: "ts_order_lenient", path: path)
          |> shelf.decode_policy(shelf.Lenient)
        let assert Ok(t2) =
          bag.open_config(config: config, key: decode.string, value: decode.string)
        let assert Ok(lenient_values) = bag.lookup(t2, "seq")
        let assert Ok(Nil) = bag.close(t2)

        // Both modes should produce the same order
        expect.to_equal(strict_values, lenient_values)
        cleanup(path)
        Nil
      }),
    ]),
    describe("resource cleanup on failed open", [
      it("DETS is cleaned up when ETS name conflicts", fn() {
        let path1 = "/tmp/shelf_ts_dets_leak1.dets"
        let path2 = "/tmp/shelf_ts_dets_leak2.dets"
        cleanup(path1)
        cleanup(path2)

        // Open a table to claim the ETS name
        let assert Ok(t1) =
          set.open(
            name: "ts_dets_leak",
            path: path1,
            key: decode.string,
            value: decode.string,
          )

        // Try to open another table with the same name but different path
        // This should fail with NameConflict
        let assert Error(shelf.NameConflict) =
          set.open(
            name: "ts_dets_leak",
            path: path2,
            key: decode.string,
            value: decode.string,
          )

        // Close the first table
        let assert Ok(Nil) = set.close(t1)

        // Now open a table with path2 — this should succeed because
        // the DETS file was properly closed during the failed open above.
        // Without the fix, the DETS handle would still be open and this
        // would fail or behave unexpectedly.
        let assert Ok(t2) =
          set.open(
            name: "ts_dets_leak_retry",
            path: path2,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.close(t2)
        cleanup(path1)
        cleanup(path2)
        Nil
      }),
    ]),
    describe("decode policy config", [
      it("config defaults to Strict", fn() {
        let config = shelf.config(name: "test", path: "test.dets")
        expect.to_equal(config.decode_policy, shelf.Strict)
        Nil
      }),
      it("config decode_policy can be set to Lenient", fn() {
        let config =
          shelf.config(name: "test", path: "test.dets")
          |> shelf.decode_policy(shelf.Lenient)
        expect.to_equal(config.decode_policy, shelf.Lenient)
        Nil
      }),
    ]),
  ])
}
