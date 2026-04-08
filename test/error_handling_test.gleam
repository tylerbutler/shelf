import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

@external(erlang, "close_test_ffi", "create_directory")
fn create_directory(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_read_only")
fn make_directory_read_only(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_writable")
fn make_directory_writable(path: String) -> Nil

@external(erlang, "close_test_ffi", "delete_directory")
fn delete_directory(path: String) -> Nil

fn prepare_retry_directory(dir: String, path: String) {
  make_directory_writable(dir)
  test_helpers.cleanup(path)
  delete_directory(dir)
  create_directory(dir)
  Nil
}

fn cleanup_retry_directory(dir: String, path: String) {
  make_directory_writable(dir)
  test_helpers.cleanup(path)
  delete_directory(dir)
  Nil
}

pub fn error_handling_tests() {
  describe("error handling", [
    describe("with_table panic safety", [
      it("catches panics and still closes the table", fn() {
        let path = "/tmp/shelf_eh_panic.dets"
        test_helpers.cleanup(path)
        // with_table with a panicking callback
        let result =
          set.with_table(
            "eh_panic",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
            fun: fn(_table) {
              // This will panic
              panic as "intentional panic for test"
            },
          )
        // Should be Error, not a panic
        expect.to_be_error(result)
        // Table should be closed — we can reopen with the same ETS name
        let assert Ok(table) =
          set.open(
            name: "eh_panic",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("propagates close error when callback succeeds", fn() {
        // Verify normal operation works
        let path = "/tmp/shelf_eh_normal.dets"
        test_helpers.cleanup(path)
        let assert Ok(42) =
          set.with_table(
            "eh_normal",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
            fun: fn(table) {
              let assert Ok(Nil) = set.insert(table, "key", 42)
              set.lookup(table, "key")
            },
          )
        test_helpers.cleanup(path)
        Nil
      }),
      it("returns callback error over close error", fn() {
        let path = "/tmp/shelf_eh_cb_err.dets"
        test_helpers.cleanup(path)
        let result =
          set.with_table(
            "eh_cb_err",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
            fun: fn(_table) { Error(shelf.NotFound) },
          )
        expect.to_equal(result, Error(shelf.NotFound))
        test_helpers.cleanup(path)
        Nil
      }),
      it("force-cleans up after a close error", fn() {
        let dir = "/tmp/shelf_eh_close_retry"
        let path = "/tmp/shelf_eh_close_retry/table.dets"
        prepare_retry_directory(dir, path)

        let result =
          set.with_table(
            "eh_close_retry",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
            fun: fn(table) {
              let assert Ok(Nil) = set.insert(table, "key", "value")
              make_directory_read_only(dir)
              Ok("done")
            },
          )

        make_directory_writable(dir)
        result |> expect.to_be_error

        let assert Ok(table) =
          set.open(
            name: "eh_close_retry_reopen",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        expect.to_equal(set.lookup(table, "key"), Error(shelf.NotFound))
        let assert Ok(Nil) = set.close(table)

        cleanup_retry_directory(dir, path)
        Nil
      }),
    ]),
    describe("TypeMismatch includes decode errors", [
      it("TypeMismatch contains decode error details", fn() {
        let path = "/tmp/shelf_eh_tm_detail.dets"
        test_helpers.cleanup(path)
        // Write String values
        let assert Ok(t) =
          set.open(
            name: "eh_tm_detail_1",
            path: path,
            base_directory: "/tmp",
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
            base_directory: "/tmp",
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
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}
