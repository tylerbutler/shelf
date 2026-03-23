import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Dynamic)

pub fn ffi_fixes_tests() {
  describe("ffi fixes", [
    describe("operations on closed table", [
      it("size returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_size_closed.dets"
        cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_size_closed",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.size(of: table)
        expect.to_equal(result, Error(shelf.TableClosed))
        cleanup(path)
        Nil
      }),
      it("member returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_member_closed.dets"
        cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_member_closed",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.member(table, "any_key")
        expect.to_equal(result, Error(shelf.TableClosed))
        cleanup(path)
        Nil
      }),
      it("lookup returns TableClosed after close", fn() {
        let path = "/tmp/shelf_ffi_lookup_closed.dets"
        cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "ffi_lookup_closed",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)
        let result = set.lookup(table, "any_key")
        expect.to_equal(result, Error(shelf.TableClosed))
        cleanup(path)
        Nil
      }),
    ]),
  ])
}
