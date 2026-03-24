import gleam/dynamic/decode
import gleam/list
import gleam/order
import gleam/string
import shelf
import shelf/bag
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn bag_tests() {
  describe("shelf/bag", [
    describe("lifecycle", [
      it("opens and closes a bag table", fn() {
        let path = "/tmp/shelf_bag_lifecycle.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_lifecycle",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("with_table opens and auto-closes", fn() {
        let path = "/tmp/shelf_bag_with_table.dets"
        test_helpers.cleanup(path)
        let assert Ok(["hello"]) = {
          use table <- bag.with_table(
            "bag_with_table",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
          let assert Ok(Nil) = bag.insert(table, "key", "hello")
          bag.lookup(table, "key")
        }
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("read/write", [
      it("stores multiple values per key", fn() {
        let path = "/tmp/shelf_bag_multi.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_multi",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(values) = bag.lookup(table, "color")
        let sorted = list.sort(values, string.compare)
        expect.to_equal(sorted, ["blue", "red"])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("deduplicates identical key-value pairs", fn() {
        let path = "/tmp/shelf_bag_dedup.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_dedup",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
        let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
        let assert Ok(values) = bag.lookup(table, "tag")
        expect.to_equal(values, ["gleam"])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("returns NotFound for missing key", fn() {
        let path = "/tmp/shelf_bag_notfound.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_notfound",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        expect.to_equal(bag.lookup(table, "missing"), Error(shelf.NotFound))
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("query", [
      it("member checks key existence", fn() {
        let path = "/tmp/shelf_bag_member.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_member",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = bag.insert(table, "exists", 1)
        let assert Ok(True) = bag.member(table, "exists")
        let assert Ok(False) = bag.member(table, "nope")
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("to_list returns all entries", fn() {
        let path = "/tmp/shelf_bag_to_list.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_to_list",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = bag.insert(table, "a", 1)
        let assert Ok(Nil) = bag.insert(table, "b", 2)
        let assert Ok(Nil) = bag.insert(table, "a", 3)
        let assert Ok(entries) = bag.to_list(table)
        let sorted =
          list.sort(entries, fn(a, b) {
            let key_cmp = string.compare(a.0, b.0)
            case key_cmp {
              order.Eq -> int_compare(a.1, b.1)
              _ -> key_cmp
            }
          })
        expect.to_equal(sorted, [#("a", 1), #("a", 3), #("b", 2)])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("fold accumulates over entries", fn() {
        let path = "/tmp/shelf_bag_fold.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_fold",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = bag.insert(table, "a", 1)
        let assert Ok(Nil) = bag.insert(table, "b", 2)
        let assert Ok(Nil) = bag.insert(table, "a", 3)
        let assert Ok(sum) =
          bag.fold(table, from: 0, with: fn(acc, _key, val) { acc + val })
        expect.to_equal(sum, 6)
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("size returns entry count", fn() {
        let path = "/tmp/shelf_bag_size.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_size",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(0) = bag.size(table)
        let assert Ok(Nil) = bag.insert(table, "a", 1)
        let assert Ok(Nil) = bag.insert(table, "a", 2)
        let assert Ok(Nil) = bag.insert(table, "b", 3)
        let assert Ok(3) = bag.size(table)
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("write", [
      it("insert_list inserts multiple entries", fn() {
        let path = "/tmp/shelf_bag_insert_list.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_insert_list",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) =
          bag.insert_list(table, [#("a", 1), #("b", 2), #("a", 3)])
        let assert Ok(values_a) = bag.lookup(table, "a")
        let sorted_a = list.sort(values_a, int_compare)
        expect.to_equal(sorted_a, [1, 3])
        let assert Ok(values_b) = bag.lookup(table, "b")
        expect.to_equal(values_b, [2])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("delete", [
      it("delete_object removes one value for a key", fn() {
        let path = "/tmp/shelf_bag_del_obj.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_del_obj",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(Nil) = bag.delete_object(table, "color", "red")
        let assert Ok(values) = bag.lookup(table, "color")
        expect.to_equal(values, ["blue"])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("delete_key removes all values for a key", fn() {
        let path = "/tmp/shelf_bag_del_key.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_del_key",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(Nil) = bag.delete_key(table, "color")
        expect.to_equal(bag.lookup(table, "color"), Error(shelf.NotFound))
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("delete_all removes everything", fn() {
        let path = "/tmp/shelf_bag_del_all.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_del_all",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = bag.insert(table, "a", 1)
        let assert Ok(Nil) = bag.insert(table, "b", 2)
        let assert Ok(Nil) = bag.delete_all(table)
        let assert Ok(0) = bag.size(table)
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("persistence", [
      it("save persists data", fn() {
        let path = "/tmp/shelf_bag_save.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_save_1",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = bag.insert(table, "x", 1)
        let assert Ok(Nil) = bag.insert(table, "x", 2)
        let assert Ok(Nil) = bag.save(table)
        let assert Ok(Nil) = bag.close(table)

        let assert Ok(table) =
          bag.open(
            name: "bag_save_2",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(values) = bag.lookup(table, "x")
        let sorted = list.sort(values, int_compare)
        expect.to_equal(sorted, [1, 2])
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("reload discards unsaved changes", fn() {
        let path = "/tmp/shelf_bag_reload.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_reload",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "saved", "yes")
        let assert Ok(Nil) = bag.save(table)
        let assert Ok(Nil) = bag.insert(table, "unsaved", "oops")
        let assert Ok(True) = bag.member(table, "unsaved")
        let assert Ok(Nil) = bag.reload(table)
        let assert Ok(True) = bag.member(table, "saved")
        let assert Ok(False) = bag.member(table, "unsaved")
        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}

fn int_compare(a: Int, b: Int) -> order.Order {
  case a == b {
    True -> order.Eq
    False ->
      case a < b {
        True -> order.Lt
        False -> order.Gt
      }
  }
}
