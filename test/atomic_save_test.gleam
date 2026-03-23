import gleam/dynamic/decode
import gleam/int
import gleam/list
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn atomic_save_tests() {
  describe("atomic save", [
    it("save cleans up temp file", fn() {
      let path = "/tmp/shelf_as_temp.dets"
      let tmp_path = path <> ".tmp"
      test_helpers.cleanup(path)
      test_helpers.cleanup(tmp_path)

      let assert Ok(table) =
        set.open(
          name: "as_temp",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      let assert Ok(Nil) = set.insert(table, "key", 1)
      let assert Ok(Nil) = set.save(table)

      // The .tmp file should not remain after save
      let tmp_exists = test_helpers.delete_file(tmp_path)
      case tmp_exists {
        Error(_) -> Nil
        Ok(Nil) -> {
          // If delete succeeded, the tmp file existed — that's a failure
          expect.to_be_true(False)
          Nil
        }
      }

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("data survives save-close-reopen cycle", fn() {
      let path = "/tmp/shelf_as_reopen.dets"
      test_helpers.cleanup(path)

      // Open, insert, save, close
      let assert Ok(table) =
        set.open(
          name: "as_reopen",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(Nil) = set.insert(table, "x", 100)
      let assert Ok(Nil) = set.insert(table, "y", 200)
      let assert Ok(Nil) = set.save(table)
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify data is present
      let assert Ok(table2) =
        set.open(
          name: "as_reopen2",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      expect.to_equal(set.lookup(table2, "x"), Ok(100))
      expect.to_equal(set.lookup(table2, "y"), Ok(200))

      let assert Ok(Nil) = set.close(table2)
      test_helpers.cleanup(path)
      Nil
    }),
    it("save preserves data integrity with many entries", fn() {
      let path = "/tmp/shelf_as_integrity.dets"
      test_helpers.cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "as_integrity",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      let count = 100
      // Insert many entries
      list.range(1, count)
      |> list.each(fn(i) {
        let key = "entry_" <> int.to_string(i)
        let assert Ok(Nil) = set.insert(table, key, i)
        Nil
      })

      let assert Ok(Nil) = set.save(table)
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify count
      let assert Ok(table2) =
        set.open(
          name: "as_integrity2",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(size) = set.size(table2)
      expect.to_equal(size, count)

      // Spot-check some values
      expect.to_equal(set.lookup(table2, "entry_1"), Ok(1))
      expect.to_equal(set.lookup(table2, "entry_50"), Ok(50))
      expect.to_equal(set.lookup(table2, "entry_100"), Ok(100))

      let assert Ok(Nil) = set.close(table2)
      test_helpers.cleanup(path)
      Nil
    }),
  ])
}
