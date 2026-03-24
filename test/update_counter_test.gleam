import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn update_counter_tests() {
  describe("update_counter", [
    it("missing key returns NotFound", fn() {
      let path = "/tmp/shelf_uc_missing.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "uc_missing",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      expect.to_equal(
        set.update_counter(table, "nonexistent", 1),
        Error(shelf.NotFound),
      )

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("multiple increments accumulate correctly", fn() {
      let path = "/tmp/shelf_uc_multi.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "uc_multi",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      let assert Ok(Nil) = set.insert(table, "hits", 0)
      let assert Ok(1) = set.update_counter(table, "hits", 1)
      let assert Ok(3) = set.update_counter(table, "hits", 2)
      let assert Ok(6) = set.update_counter(table, "hits", 3)
      let assert Ok(10) = set.update_counter(table, "hits", 4)

      expect.to_equal(set.lookup(table, "hits"), Ok(10))

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("negative increment decrements value", fn() {
      let path = "/tmp/shelf_uc_neg.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "uc_neg",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      let assert Ok(Nil) = set.insert(table, "counter", 10)
      let assert Ok(new_val) = set.update_counter(table, "counter", -3)
      expect.to_equal(new_val, 7)

      expect.to_equal(set.lookup(table, "counter"), Ok(7))

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("zero increment returns current value", fn() {
      let path = "/tmp/shelf_uc_zero.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) =
        set.open(
          name: "uc_zero",
          path: path,
          base_directory: "/tmp",
          key: decode.string,
          value: decode.int,
        )

      let assert Ok(Nil) = set.insert(table, "counter", 42)
      let assert Ok(new_val) = set.update_counter(table, "counter", 0)
      expect.to_equal(new_val, 42)

      expect.to_equal(set.lookup(table, "counter"), Ok(42))

      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
  ])
}
