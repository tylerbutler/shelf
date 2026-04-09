import gleam/dynamic/decode
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

/// Write a raw entry directly into DETS, bypassing shelf's type checks.
@external(erlang, "reload_atomicity_test_ffi", "write_raw_dets_entry")
fn write_raw_dets_entry(path: String, key: String, value: a) -> Nil

pub fn reload_atomicity_tests() {
  describe("reload atomicity", [
    it("strict reload failure preserves original ETS data", fn() {
      let path = "/tmp/shelf_reload_atom.dets"
      test_helpers.cleanup(path)

      // Open table with String keys and Int values
      let assert Ok(table) =
        set.open(
          name: "reload_atom",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      // Insert valid data and save to DETS
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)
      let assert Ok(Nil) = set.save(table)

      // Write an invalid entry directly to DETS (string value instead of int)
      write_raw_dets_entry(path, "bad", "not_an_int")

      // Reload in strict mode should fail due to the invalid entry
      set.reload(table) |> expect.to_be_error

      // ETS must still have the original data (not empty, not partially loaded)
      let assert Ok(1) = set.lookup(table, "a")
      let assert Ok(2) = set.lookup(table, "b")
      let assert Ok(2) = set.size(table)

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("successful reload replaces ETS contents", fn() {
      let path = "/tmp/shelf_reload_ok.dets"
      test_helpers.cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "reload_ok",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      // Insert and save original data
      let assert Ok(Nil) = set.insert(table, "x", 10)
      let assert Ok(Nil) = set.save(table)

      // Add unsaved data
      let assert Ok(Nil) = set.insert(table, "y", 20)
      let assert Ok(2) = set.size(table)

      // Reload should discard unsaved "y"
      let assert Ok(_skipped) = set.reload(table)
      let assert Ok(1) = set.size(table)
      let assert Ok(10) = set.lookup(table, "x")
      set.lookup(table, "y") |> expect.to_be_error

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
  ])
}
