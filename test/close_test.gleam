import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

@external(erlang, "close_test_ffi", "simulate_external_dets_close")
fn simulate_external_dets_close(path: String) -> Nil

@external(erlang, "close_test_ffi", "cleanup_after_failed_close")
fn cleanup_after_failed_close(path: String, name: String) -> Nil

pub fn close_save_failure_tests() {
  describe("close/3 save failure", [
    it("returns TableClosed and tears down state for terminal failures", fn() {
      let path = "/tmp/shelf_close_err.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "close_err",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "k", "v")

      simulate_external_dets_close(path)

      expect.to_equal(set.close(table), Error(shelf.TableClosed))
      expect.to_equal(set.lookup(table, "k"), Error(shelf.TableClosed))

      cleanup_after_failed_close(path, "close_err")
      Nil
    }),
    it("preserves ETS data on retryable save failures", fn() {
      let dir = "/tmp/shelf_close_preserve"
      let path = "/tmp/shelf_close_preserve/table.dets"
      test_helpers.prepare_retry_directory(dir, path)
      let assert Ok(table) =
        set.open(
          name: "close_preserve",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "key1", "value1")

      test_helpers.make_directory_read_only(dir)

      set.close(table) |> expect.to_be_error
      let assert Ok("value1") = set.lookup(table, "key1")
      test_helpers.make_directory_writable(dir)
      let assert Ok(Nil) = set.close(table)

      test_helpers.cleanup_retry_directory(dir, path)
      Nil
    }),
    it("allows retrying close after a retryable save failure", fn() {
      let dir = "/tmp/shelf_close_usable"
      let path = "/tmp/shelf_close_usable/table.dets"
      test_helpers.prepare_retry_directory(dir, path)
      let assert Ok(table) =
        set.open(
          name: "close_usable",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "a", "1")

      test_helpers.make_directory_read_only(dir)

      let assert Error(_) = set.close(table)
      let assert Ok("1") = set.lookup(table, "a")
      let assert Ok(Nil) = set.insert(table, "b", "2")
      let assert Ok("2") = set.lookup(table, "b")
      test_helpers.make_directory_writable(dir)
      let assert Ok(Nil) = set.close(table)

      test_helpers.cleanup_retry_directory(dir, path)
      Nil
    }),
    it("preserves state in WriteThrough mode", fn() {
      let dir = "/tmp/shelf_close_wt"
      let path = "/tmp/shelf_close_wt/table.dets"
      test_helpers.prepare_retry_directory(dir, path)

      let config =
        shelf.config(name: "close_wt", path: path, base_directory: "/tmp")
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config, key: decode.string, value: decode.string)
      let assert Ok(Nil) = set.insert(table, "x", "y")

      test_helpers.make_directory_read_only(dir)

      let assert Error(_) = set.close(table)
      let assert Ok("y") = set.lookup(table, "x")
      test_helpers.make_directory_writable(dir)
      let assert Ok(Nil) = set.close(table)

      test_helpers.cleanup_retry_directory(dir, path)
      Nil
    }),
  ])
}
