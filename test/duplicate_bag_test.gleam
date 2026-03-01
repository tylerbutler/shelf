import gleam/dynamic.{type Dynamic}
import gleam/list
import shelf
import shelf/duplicate_bag
import startest.{describe, it}
import startest/expect

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Dynamic)

pub fn duplicate_bag_tests() {
  describe("shelf/duplicate_bag", [
    describe("lifecycle", [
      it("opens and closes a duplicate bag table", fn() {
        let path = "/tmp/shelf_dbag_lifecycle.dets"
        cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(name: "dbag_lifecycle", path: path)
        let assert Ok(Nil) = duplicate_bag.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("read/write", [
      it("preserves duplicate key-value pairs", fn() {
        let path = "/tmp/shelf_dbag_dupes.dets"
        cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(name: "dbag_dupes", path: path)
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
        cleanup(path)
        Nil
      }),
      it("returns NotFound for missing key", fn() {
        let path = "/tmp/shelf_dbag_notfound.dets"
        cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(name: "dbag_notfound", path: path)
        expect.to_equal(
          duplicate_bag.lookup(table, "missing"),
          Error(shelf.NotFound),
        )
        let assert Ok(Nil) = duplicate_bag.close(table)
        cleanup(path)
        Nil
      }),
    ]),
  ])
}
