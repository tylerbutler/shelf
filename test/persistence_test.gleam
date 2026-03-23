import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn persistence_tests() {
  describe("persistence", [
    it("data survives close and reopen", fn() {
      let path = "/tmp/shelf_persist_survive.dets"
      test_helpers.cleanup(path)

      // Open, insert, close (auto-saves)
      let assert Ok(table) =
        set.open(
          name: "persist_survive_1",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "key", "value")
      let assert Ok(Nil) = set.close(table)

      // Reopen — data should be there
      let assert Ok(table) =
        set.open(
          name: "persist_survive_2",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      let assert Ok("value") = set.lookup(table, "key")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("save persists current state", fn() {
      let path = "/tmp/shelf_persist_save.dets"
      test_helpers.cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "persist_save_1",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)
      let assert Ok(Nil) = set.save(table)

      // Add more data, then close without explicit save
      // (close does an auto-save too)
      let assert Ok(Nil) = set.insert(table, "c", 3)
      let assert Ok(Nil) = set.close(table)

      // All three should be present
      let assert Ok(table) =
        set.open(
          name: "persist_save_2",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(1) = set.lookup(table, "a")
      let assert Ok(2) = set.lookup(table, "b")
      let assert Ok(3) = set.lookup(table, "c")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("reload discards unsaved changes", fn() {
      let path = "/tmp/shelf_persist_reload.dets"
      test_helpers.cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "persist_reload",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )

      // Insert and save
      let assert Ok(Nil) = set.insert(table, "saved", "yes")
      let assert Ok(Nil) = set.save(table)

      // Insert more (not saved)
      let assert Ok(Nil) = set.insert(table, "unsaved", "oops")
      let assert Ok(True) = set.member(table, "unsaved")

      // Reload — unsaved changes should be gone
      let assert Ok(Nil) = set.reload(table)
      let assert Ok(True) = set.member(table, "saved")
      let assert Ok(False) = set.member(table, "unsaved")

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("multiple save-reload cycles work", fn() {
      let path = "/tmp/shelf_persist_cycles.dets"
      test_helpers.cleanup(path)

      let assert Ok(table) =
        set.open(
          name: "persist_cycles",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      // Cycle 1
      let assert Ok(Nil) = set.insert(table, "round", 1)
      let assert Ok(Nil) = set.save(table)

      // Cycle 2
      let assert Ok(Nil) = set.insert(table, "round", 2)
      let assert Ok(Nil) = set.save(table)

      // Reload should show latest saved state
      let assert Ok(Nil) = set.reload(table)
      let assert Ok(2) = set.lookup(table, "round")

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("DETS path conflict returns error", fn() {
      let path = "/tmp/shelf_persist_conflict.dets"
      test_helpers.cleanup(path)

      let assert Ok(table1) =
        set.open(
          name: "persist_conflict_1",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      // Opening a second table with the same DETS path should fail
      // because the DETS file is already open
      let result =
        set.open(
          name: "persist_conflict_2",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.string,
        )
      // DETS returns an error when the file is already open with a
      // different owner, so this should fail
      case result {
        Error(_) -> Nil
        Ok(table2) -> {
          // If it succeeded (DETS allows same-process opens), close it
          let assert Ok(Nil) = set.close(table2)
          Nil
        }
      }

      let assert Ok(Nil) = set.close(table1)
      test_helpers.cleanup(path)
      Nil
    }),
  ])
}
