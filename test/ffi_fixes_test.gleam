import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn ffi_fixes_tests() {
  describe("ffi fixes", [
    describe("operations on closed table", [
      it("size returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_size_closed.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_size_closed",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.size(of: table)
        expect.to_equal(result, Error(shelf.TableClosed))
        test_helpers.cleanup(path)
        Nil
      }),
      it("member returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_member_closed.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_member_closed",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.member(table, "any_key")
        expect.to_equal(result, Error(shelf.TableClosed))
        test_helpers.cleanup(path)
        Nil
      }),
      it("lookup returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_lookup_closed.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_lookup_closed",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.lookup(table, "any_key")
        expect.to_equal(result, Error(shelf.TableClosed))
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}
