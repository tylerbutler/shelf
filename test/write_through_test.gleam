import gleam/dynamic/decode
import gleam/list
import gleam/order
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn write_through_tests() {
  describe("write_through", [
    it("writes persist immediately without explicit save", fn() {
      let path = "/tmp/shelf_wt_persist.dets"
      test_helpers.cleanup(path)

      // Open in WriteThrough mode
      let config =
        shelf.config(name: "wt_persist_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(
          config: config,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = set.insert(table, "key", "value")

      // Close without explicit save — but WriteThrough already persisted
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify data is there
      let assert Ok(table) =
        set.open(
          name: "wt_persist_2",
          path: path,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok("value") = set.lookup(table, "key")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("deletes persist immediately in write-through mode", fn() {
      let path = "/tmp/shelf_wt_delete.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_delete_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)
      let assert Ok(Nil) = set.delete_key(table, "a")
      let assert Ok(Nil) = set.close(table)

      // Reopen — "a" should be gone, "b" should remain
      let assert Ok(table) =
        set.open(
          name: "wt_delete_2",
          path: path,
          key: decode.string,
          value: decode.int,
        )
      expect.to_equal(set.lookup(table, "a"), Error(shelf.NotFound))
      let assert Ok(2) = set.lookup(table, "b")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("counter updates persist in write-through mode", fn() {
      let path = "/tmp/shelf_wt_counter.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_counter_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) = set.insert(table, "count", 0)
      let assert Ok(5) = set.update_counter(table, "count", 5)
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify counter persisted
      let assert Ok(table) =
        set.open(
          name: "wt_counter_2",
          path: path,
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(5) = set.lookup(table, "count")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("delete_object persists in write-through mode", fn() {
      let path = "/tmp/shelf_wt_delobj.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_delobj_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) = set.insert(table, "x", 10)
      let assert Ok(Nil) = set.insert(table, "y", 20)
      let assert Ok(Nil) = set.delete_object(table, "x", 10)
      let assert Ok(Nil) = set.close(table)

      let assert Ok(table) =
        set.open(
          name: "wt_delobj_2",
          path: path,
          key: decode.string,
          value: decode.int,
        )
      expect.to_equal(set.lookup(table, "x"), Error(shelf.NotFound))
      let assert Ok(20) = set.lookup(table, "y")
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("delete_all persists in write-through mode", fn() {
      let path = "/tmp/shelf_wt_delall.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_delall_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)
      let assert Ok(Nil) = set.delete_all(table)
      let assert Ok(Nil) = set.close(table)

      let assert Ok(table) =
        set.open(
          name: "wt_delall_2",
          path: path,
          key: decode.string,
          value: decode.int,
        )
      let assert Ok(0) = set.size(table)
      let assert Ok(Nil) = set.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("insert_list persists in write-through mode", fn() {
      let path = "/tmp/shelf_wt_inslist.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_inslist_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        set.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) =
        set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
      let assert Ok(Nil) = set.close(table)

      let assert Ok(table) =
        set.open(
          name: "wt_inslist_2",
          path: path,
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
    it("bag WriteThrough persists inserts immediately", fn() {
      let path = "/tmp/shelf_wt_bag.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_bag_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        bag.open_config(
          config: config,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = bag.insert(table, "color", "red")
      let assert Ok(Nil) = bag.insert(table, "color", "blue")
      let assert Ok(Nil) = bag.close(table)

      // Reopen and verify both values persisted
      let assert Ok(table) =
        bag.open(
          name: "wt_bag_2",
          path: path,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(values) = bag.lookup(table, "color")
      let sorted = list.sort(values, fn(a, b) { string_compare(a, b) })
      expect.to_equal(sorted, ["blue", "red"])
      let assert Ok(Nil) = bag.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("bag WriteThrough delete_key persists immediately", fn() {
      let path = "/tmp/shelf_wt_bag_del.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_bag_del_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        bag.open_config(config: config, key: decode.string, value: decode.int)
      let assert Ok(Nil) = bag.insert(table, "k", 1)
      let assert Ok(Nil) = bag.insert(table, "k", 2)
      let assert Ok(Nil) = bag.delete_key(table, "k")
      let assert Ok(Nil) = bag.close(table)

      let assert Ok(table) =
        bag.open(
          name: "wt_bag_del_2",
          path: path,
          key: decode.string,
          value: decode.int,
        )
      expect.to_equal(bag.lookup(table, "k"), Error(shelf.NotFound))
      let assert Ok(Nil) = bag.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("duplicate_bag WriteThrough persists inserts immediately", fn() {
      let path = "/tmp/shelf_wt_dbag.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_dbag_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        duplicate_bag.open_config(
          config: config,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
      let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
      let assert Ok(Nil) = duplicate_bag.close(table)

      // Reopen and verify both duplicate entries persisted
      let assert Ok(table) =
        duplicate_bag.open(
          name: "wt_dbag_2",
          path: path,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(values) = duplicate_bag.lookup(table, "event")
      expect.to_equal(values, ["click", "click"])
      let assert Ok(Nil) = duplicate_bag.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
    it("duplicate_bag WriteThrough delete_object persists immediately", fn() {
      let path = "/tmp/shelf_wt_dbag_delobj.dets"
      test_helpers.cleanup(path)

      let config =
        shelf.config(name: "wt_dbag_delobj_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) =
        duplicate_bag.open_config(
          config: config,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(Nil) = duplicate_bag.insert(table, "x", "a")
      let assert Ok(Nil) = duplicate_bag.insert(table, "x", "b")
      let assert Ok(Nil) = duplicate_bag.delete_object(table, "x", "a")
      let assert Ok(Nil) = duplicate_bag.close(table)

      let assert Ok(table) =
        duplicate_bag.open(
          name: "wt_dbag_delobj_2",
          path: path,
          key: decode.string,
          value: decode.string,
        )
      let assert Ok(values) = duplicate_bag.lookup(table, "x")
      expect.to_equal(values, ["b"])
      let assert Ok(Nil) = duplicate_bag.close(table)
      test_helpers.cleanup(path)
      Nil
    }),
  ])
}

fn string_compare(a: String, b: String) -> order.Order {
  case a == b {
    True -> order.Eq
    False ->
      case a_less_than_b(a, b) {
        True -> order.Lt
        False -> order.Gt
      }
  }
}

@external(erlang, "shelf_wt_test_ffi", "less_than")
fn a_less_than_b(a: String, b: String) -> Bool
