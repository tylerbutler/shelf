import gleam/dynamic/decode
import gleam/list
import gleam/order
import gleam/string
import shelf
import shelf/duplicate_bag
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn duplicate_bag_tests() {
  describe("shelf/duplicate_bag", [
    describe("lifecycle", [
      it("opens and closes a duplicate bag table", fn() {
        let path = "/tmp/shelf_dbag_lifecycle.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_lifecycle",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("with_table opens and auto-closes", fn() {
        let path = "/tmp/shelf_dbag_with_table.dets"
        test_helpers.cleanup(path)
        let assert Ok(values) = {
          use table <- duplicate_bag.with_table(
            "dbag_with_table",
            path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
          let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
          let assert Ok(Nil) = duplicate_bag.insert(table, "key", "hello")
          duplicate_bag.lookup(table, "key")
        }
        expect.to_equal(values, ["hello", "hello"])
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("read/write", [
      it("preserves duplicate key-value pairs", fn() {
        let path = "/tmp/shelf_dbag_dupes.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_dupes",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
        let assert Ok(Nil) = duplicate_bag.insert(table, "event", "click")
        let assert Ok(Nil) = duplicate_bag.insert(table, "event", "scroll")
        let assert Ok(values) = duplicate_bag.lookup(table, "event")
        // Should have 2 "click" and 1 "scroll"
        let click_count =
          list.filter(values, fn(v) { v == "click" }) |> list.length
        let scroll_count =
          list.filter(values, fn(v) { v == "scroll" }) |> list.length
        expect.to_equal(click_count, 2)
        expect.to_equal(scroll_count, 1)
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("returns NotFound for missing key", fn() {
        let path = "/tmp/shelf_dbag_notfound.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_notfound",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        expect.to_equal(
          duplicate_bag.lookup(table, "missing"),
          Error(shelf.NotFound),
        )
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("query", [
      it("member checks key existence", fn() {
        let path = "/tmp/shelf_dbag_member.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_member",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "exists", 1)
        let assert Ok(True) = duplicate_bag.member(table, "exists")
        let assert Ok(False) = duplicate_bag.member(table, "nope")
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("to_list returns all entries", fn() {
        let path = "/tmp/shelf_dbag_to_list.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_to_list",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
        let assert Ok(entries) = duplicate_bag.to_list(table)
        let sorted =
          list.sort(entries, fn(a, b) {
            let key_cmp = string.compare(a.0, b.0)
            case key_cmp {
              order.Eq -> int_compare(a.1, b.1)
              _ -> key_cmp
            }
          })
        expect.to_equal(sorted, [#("a", 1), #("a", 1), #("b", 2)])
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("fold accumulates over entries", fn() {
        let path = "/tmp/shelf_dbag_fold.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_fold",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "b", 3)
        let assert Ok(sum) =
          duplicate_bag.fold(table, from: 0, with: fn(acc, _key, val) {
            acc + val
          })
        expect.to_equal(sum, 5)
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("size returns entry count", fn() {
        let path = "/tmp/shelf_dbag_size.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_size",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(0) = duplicate_bag.size(table)
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
        let assert Ok(3) = duplicate_bag.size(table)
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("write", [
      it("insert_list inserts multiple entries", fn() {
        let path = "/tmp/shelf_dbag_insert_list.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_insert_list",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) =
          duplicate_bag.insert_list(table, [
            #("a", 1),
            #("a", 1),
            #("b", 2),
          ])
        let assert Ok(values_a) = duplicate_bag.lookup(table, "a")
        expect.to_equal(values_a, [1, 1])
        let assert Ok(values_b) = duplicate_bag.lookup(table, "b")
        expect.to_equal(values_b, [2])
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("delete", [
      it("delete_key removes all values for a key", fn() {
        let path = "/tmp/shelf_dbag_del_key.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_del_key",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "blue")
        let assert Ok(Nil) = duplicate_bag.delete_key(table, "color")
        expect.to_equal(
          duplicate_bag.lookup(table, "color"),
          Error(shelf.NotFound),
        )
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("delete_object removes matching entries", fn() {
        let path = "/tmp/shelf_dbag_del_obj.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_del_obj",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "red")
        let assert Ok(Nil) = duplicate_bag.insert(table, "color", "blue")
        let assert Ok(Nil) = duplicate_bag.delete_object(table, "color", "red")
        let assert Ok(values) = duplicate_bag.lookup(table, "color")
        expect.to_equal(values, ["blue"])
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("delete_all removes everything", fn() {
        let path = "/tmp/shelf_dbag_del_all.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_del_all",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
        let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
        let assert Ok(Nil) = duplicate_bag.delete_all(table)
        let assert Ok(0) = duplicate_bag.size(table)
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("persistence", [
      it("save persists data", fn() {
        let path = "/tmp/shelf_dbag_save.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_save_1",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "x", "a")
        let assert Ok(Nil) = duplicate_bag.insert(table, "x", "a")
        let assert Ok(Nil) = duplicate_bag.save(table)
        let assert Ok(Nil) = duplicate_bag.close(table)

        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_save_2",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(values) = duplicate_bag.lookup(table, "x")
        expect.to_equal(values, ["a", "a"])
        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("reload discards unsaved changes", fn() {
        let path = "/tmp/shelf_dbag_reload.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "dbag_reload",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = duplicate_bag.insert(table, "saved", "yes")
        let assert Ok(Nil) = duplicate_bag.save(table)
        let assert Ok(Nil) = duplicate_bag.insert(table, "unsaved", "oops")
        let assert Ok(True) = duplicate_bag.member(table, "unsaved")
        let assert Ok(Nil) = duplicate_bag.reload(table)
        let assert Ok(True) = duplicate_bag.member(table, "saved")
        let assert Ok(False) = duplicate_bag.member(table, "unsaved")
        let assert Ok(Nil) = duplicate_bag.close(table)
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
