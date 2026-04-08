import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

@external(erlang, "close_test_ffi", "close_dets_externally")
fn close_dets_externally(path: String) -> Nil

@external(erlang, "close_test_ffi", "force_cleanup")
fn force_cleanup(path: String, name: String) -> Nil

pub fn close_save_failure_tests() {
  describe("close/3 save failure", [
    it("returns error when save fails", fn() {
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

      // Sabotage: close DETS externally so save will fail
      close_dets_externally(path)

      // close() should return an error
      set.close(table) |> expect.to_be_error

      force_cleanup(path, "close_err")
      Nil
    }),
    it("preserves ETS data when save fails", fn() {
      let path = "/tmp/shelf_close_preserve.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "close_preserve",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "key1", "value1")

      // Sabotage DETS
      close_dets_externally(path)

      // close() should fail
      let assert Error(_) = set.close(table)

      // Data should still be readable from ETS
      let assert Ok("value1") = set.lookup(table, "key1")

      force_cleanup(path, "close_preserve")
      Nil
    }),
    it("table remains usable after failed close", fn() {
      let path = "/tmp/shelf_close_usable.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "close_usable",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "a", "1")

      // Sabotage DETS
      close_dets_externally(path)

      // close() should fail
      let assert Error(_) = set.close(table)

      // Table should still be usable for reads and writes
      let assert Ok("1") = set.lookup(table, "a")
      let assert Ok(Nil) = set.insert(table, "b", "2")
      let assert Ok("2") = set.lookup(table, "b")

      force_cleanup(path, "close_usable")
      Nil
    }),
    it("preserves state in WriteThrough mode", fn() {
      let path = "/tmp/shelf_close_wt.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "close_wt", path: path, base_directory: "/tmp")
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config, key: decode.string, value: decode.string)
      let assert Ok(Nil) = set.insert(table, "x", "y")

      // Sabotage DETS
      close_dets_externally(path)

      // close() should fail
      let assert Error(_) = set.close(table)

      // ETS data should still be there
      let assert Ok("y") = set.lookup(table, "x")

      force_cleanup(path, "close_wt")
      Nil
    }),
  ])
}
