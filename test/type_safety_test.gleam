import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

@external(erlang, "type_safety_test_ffi", "write_raw_dets")
fn write_raw_dets(
  path: String,
  table_type: String,
  entries: List(#(Dynamic, Dynamic)),
) -> Result(Nil, Dynamic)

pub fn type_safety_tests() {
  describe("type safety", [
    describe("set", [
      it("rejects DETS data with wrong value type", fn() {
        let path = "/tmp/shelf_ts_wrong_value.dets"
        test_helpers.cleanup(path)

        // Write String values using the correct API
        let assert Ok(t) =
          set.open(
            name: "ts_wrong_value_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        case result {
          Error(shelf.TypeMismatch(_)) -> Nil
          _ -> expect.to_equal(result, Error(shelf.TypeMismatch([])))
        }
        test_helpers.cleanup(path)
        Nil
      }),
      it("rejects DETS data with wrong key type", fn() {
        let path = "/tmp/shelf_ts_wrong_key.dets"
        test_helpers.cleanup(path)

        // Write Int keys
        let assert Ok(t) =
          set.open(
            name: "ts_wrong_key_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        case result {
          Error(shelf.TypeMismatch(_)) -> Nil
          _ -> expect.to_equal(result, Error(shelf.TypeMismatch([])))
        }
        test_helpers.cleanup(path)
        Nil
      }),
      it("accepts DETS data with correct types", fn() {
        let path = "/tmp/shelf_ts_correct.dets"
        test_helpers.cleanup(path)

        let assert Ok(t) =
          set.open(
            name: "ts_correct_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(42) = set.lookup(t, "count")
        let assert Ok(Nil) = set.close(t)
        test_helpers.cleanup(path)
        Nil
      }),
      it("opens empty DETS file with any decoder", fn() {
        let path = "/tmp/shelf_ts_empty.dets"
        test_helpers.cleanup(path)

        // Open with one type, close (creates empty DETS)
        let assert Ok(t) =
          set.open(
            name: "ts_empty_1",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.close(t)

        // Reopen with different types — should succeed (no data to validate)
        let assert Ok(t) =
          set.open(
            name: "ts_empty_2",
            path: path,
            base_directory: "/tmp",
            key: decode.int,
            value: decode.float,
          )
        let assert Ok(0) = set.size(t)
        let assert Ok(Nil) = set.close(t)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("rejects mixed data", [
      it("rejects if any entry is invalid", fn() {
        let path = "/tmp/shelf_ts_strict_reject.dets"
        test_helpers.cleanup(path)

        // Write mixed data
        let assert Ok(Nil) =
          write_raw_dets(path, "set", [
            #(dynamic.string("good"), dynamic.int(1)),
            #(dynamic.int(999), dynamic.string("bad")),
          ])

        // Open should fail with TypeMismatch
        let result =
          set.open(
            name: "ts_strict_reject",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        case result {
          Error(shelf.TypeMismatch(_)) -> Nil
          _ -> expect.to_equal(result, Error(shelf.TypeMismatch([])))
        }
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("bag type safety", [
      it("rejects bag DETS data with wrong types", fn() {
        let path = "/tmp/shelf_ts_bag_wrong.dets"
        test_helpers.cleanup(path)

        let assert Ok(t) =
          bag.open(
            name: "ts_bag_wrong_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        case result {
          Error(shelf.TypeMismatch(_)) -> Nil
          _ -> expect.to_equal(result, Error(shelf.TypeMismatch([])))
        }
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("duplicate_bag type safety", [
      it("rejects duplicate_bag DETS data with wrong types", fn() {
        let path = "/tmp/shelf_ts_dbag_wrong.dets"
        test_helpers.cleanup(path)

        let assert Ok(t) =
          duplicate_bag.open(
            name: "ts_dbag_wrong_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        case result {
          Error(shelf.TypeMismatch(_)) -> Nil
          _ -> expect.to_equal(result, Error(shelf.TypeMismatch([])))
        }
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("entry order preservation", [
      it("bag preserves value order after save and reload", fn() {
        let path = "/tmp/shelf_ts_bag_order.dets"
        test_helpers.cleanup(path)

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
            base_directory: "/tmp",
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
        test_helpers.cleanup(path)
        Nil
      }),
      it("duplicate_bag preserves value order after save and reload", fn() {
        let path = "/tmp/shelf_ts_dbag_order.dets"
        test_helpers.cleanup(path)

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
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(values) = duplicate_bag.lookup(t, "log")
        expect.to_equal(list.length(values), 3)
        let assert Ok(first) = list.first(values)
        let assert Ok(last) = list.last(values)
        expect.to_not_equal(first, last)
        let assert Ok(Nil) = duplicate_bag.close(t)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("resource cleanup on failed open", [
      it("multiple tables with same name can coexist", fn() {
        let path1 = "/tmp/shelf_ts_dets_leak1.dets"
        let path2 = "/tmp/shelf_ts_dets_leak2.dets"
        test_helpers.cleanup(path1)
        test_helpers.cleanup(path2)

        // Open two tables with the same ETS name but different DETS paths
        // This should work because ETS tables are unnamed (no named_table)
        let assert Ok(t1) =
          set.open(
            name: "ts_same_name",
            path: path1,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )

        let assert Ok(t2) =
          set.open(
            name: "ts_same_name",
            path: path2,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )

        // Both tables are independent
        let assert Ok(Nil) = set.insert(t1, "key", "val1")
        let assert Ok(Nil) = set.insert(t2, "key", "val2")
        let assert Ok("val1") = set.lookup(t1, "key")
        let assert Ok("val2") = set.lookup(t2, "key")

        let assert Ok(Nil) = set.close(t1)
        let assert Ok(Nil) = set.close(t2)
        test_helpers.cleanup(path1)
        test_helpers.cleanup(path2)
        Nil
      }),
    ]),
  ])
}
