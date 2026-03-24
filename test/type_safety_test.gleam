import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}

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
        let assert Error(shelf.TypeMismatch(_)) = result
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
        let assert Error(shelf.TypeMismatch(_)) = result
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
        let assert Error(shelf.TypeMismatch(_)) = result
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
        let assert Error(shelf.TypeMismatch(_)) = result
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
        let assert Error(shelf.TypeMismatch(_)) = result
        cleanup(path)
        Nil
      }),
    ]),
    describe("decode policy config", [
      it("config defaults to Strict", fn() {
        // Just verify the builder works — Config is now opaque
        let _config = shelf.config(name: "test", path: "test.dets")
        Nil
      }),
      it("config decode_policy can be set to Lenient", fn() {
        let _config =
          shelf.config(name: "test", path: "test.dets")
          |> shelf.decode_policy(shelf.Lenient)
        Nil
      }),
    ]),
  ])
}
