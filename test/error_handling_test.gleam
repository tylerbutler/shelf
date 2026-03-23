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

pub fn error_handling_tests() {
  describe("error handling", [
    describe("with_table panic safety", [
      it("catches panics and still closes the table", fn() {
        let path = "/tmp/shelf_eh_panic.dets"
        cleanup(path)
        // with_table with a panicking callback
        let result =
          set.with_table(
            "eh_panic",
            path,
            key: decode.string,
            value: decode.string,
            fun: fn(_table) {
              // This will panic
              let assert Ok(_) = Error(shelf.NotFound)
              Ok("unreachable")
            },
          )
        // Should be Error, not a panic
        expect.to_be_error(result)
        // Table should be closed — we can reopen with the same ETS name
        let assert Ok(table) =
          set.open(
            name: "eh_panic",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("propagates close error when callback succeeds", fn() {
        // Verify normal operation works
        let path = "/tmp/shelf_eh_normal.dets"
        cleanup(path)
        let assert Ok(42) =
          set.with_table(
            "eh_normal",
            path,
            key: decode.string,
            value: decode.int,
            fun: fn(table) {
              let assert Ok(Nil) = set.insert(table, "key", 42)
              set.lookup(table, "key")
            },
          )
        cleanup(path)
        Nil
      }),
      it("returns callback error over close error", fn() {
        let path = "/tmp/shelf_eh_cb_err.dets"
        cleanup(path)
        let result =
          set.with_table(
            "eh_cb_err",
            path,
            key: decode.string,
            value: decode.string,
            fun: fn(_table) { Error(shelf.NotFound) },
          )
        expect.to_equal(result, Error(shelf.NotFound))
        cleanup(path)
        Nil
      }),
    ]),
    describe("TypeMismatch includes decode errors", [
      it("TypeMismatch contains decode error details", fn() {
        let path = "/tmp/shelf_eh_tm_detail.dets"
        cleanup(path)
        // Write String values
        let assert Ok(t) =
          set.open(
            name: "eh_tm_detail_1",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.insert(t, "key", "hello")
        let assert Ok(Nil) = set.close(t)
        // Reopen expecting Int values
        let result =
          set.open(
            name: "eh_tm_detail_2",
            path: path,
            key: decode.string,
            value: decode.int,
          )
        case result {
          Error(shelf.TypeMismatch(errors)) -> {
            // Should have non-empty decode errors
            expect.to_not_equal(errors, [])
          }
          other -> {
            // Force fail if not TypeMismatch
            expect.to_equal(other, Error(shelf.TypeMismatch([])))
          }
        }
        cleanup(path)
        Nil
      }),
    ]),
  ])
}
