import gleam/dynamic/decode
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn error_path_tests() {
  describe("error paths", [
    describe("update_counter errors", [
      it("update_counter on non-existent key returns NotFound", fn() {
        let path = "/tmp/shelf_ep_counter_missing.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ep_counter_missing",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let result = set.update_counter(table, "no_such_key", 1)
        expect.to_equal(result, Error(shelf.NotFound))
        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("update_counter on closed table errors", fn() {
        // Gleam's type system prevents calling update_counter on
        // PSet(String, String), so we test the closed-table error path.
        let path = "/tmp/shelf_ep_counter_closed.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ep_counter_closed",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "count", 10)
        let assert Ok(13) = set.update_counter(table, "count", 3)
        let assert Ok(13) = set.lookup(table, "count")
        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("sync operation", [
      it("sync flushes DETS buffer", fn() {
        let path = "/tmp/shelf_ep_sync_set.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ep_sync_set",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "x", 1)
        let assert Ok(Nil) = set.sync(table)
        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("bag sync", [
      it("bag sync works", fn() {
        let path = "/tmp/shelf_ep_sync_bag.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "ep_sync_bag",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "k", "v")
        let assert Ok(Nil) = bag.sync(table)
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("duplicate_bag sync", [
      it("duplicate_bag sync works", fn() {
        let path = "/tmp/shelf_ep_sync_dbag.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "ep_sync_dbag",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
        let assert Ok(Nil) = duplicate_bag.sync(table)
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("with_table error handling", [
      it("bag with_table returns callback error", fn() {
        let path = "/tmp/shelf_ep_bag_wt_err.dets"
        test_helpers.cleanup(path)
        let result =
          bag.with_table(
            "ep_bag_wt_err",
            path,
            key: decode.string,
            value: decode.string,
            fun: fn(_table) { Error(shelf.NotFound) },
          )
        expect.to_equal(result, Error(shelf.NotFound))
        test_helpers.cleanup(path)
        Nil
      }),
      it("duplicate_bag with_table returns callback error", fn() {
        let path = "/tmp/shelf_ep_dbag_wt_err.dets"
        test_helpers.cleanup(path)
        let result =
          duplicate_bag.with_table(
            "ep_dbag_wt_err",
            path,
            key: decode.string,
            value: decode.string,
            fun: fn(_table) { Error(shelf.NotFound) },
          )
        expect.to_equal(result, Error(shelf.NotFound))
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}
