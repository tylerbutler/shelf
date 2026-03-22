import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import shelf
import shelf/bag
import startest.{describe, it}
import startest/expect

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Dynamic)

pub fn bag_tests() {
  describe("shelf/bag", [
    describe("lifecycle", [
      it("opens and closes a bag table", fn() {
        let path = "/tmp/shelf_bag_lifecycle.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_lifecycle",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("read/write", [
      it("stores multiple values per key", fn() {
        let path = "/tmp/shelf_bag_multi.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_multi",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(values) = bag.lookup(table, "color")
        let sorted = list.sort(values, string.compare)
        expect.to_equal(sorted, ["blue", "red"])
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
      it("deduplicates identical key-value pairs", fn() {
        let path = "/tmp/shelf_bag_dedup.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_dedup",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
        let assert Ok(Nil) = bag.insert(table, "tag", "gleam")
        let assert Ok(values) = bag.lookup(table, "tag")
        expect.to_equal(values, ["gleam"])
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
      it("returns NotFound for missing key", fn() {
        let path = "/tmp/shelf_bag_notfound.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_notfound",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        expect.to_equal(bag.lookup(table, "missing"), Error(shelf.NotFound))
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("delete", [
      it("delete_object removes one value for a key", fn() {
        let path = "/tmp/shelf_bag_del_obj.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_del_obj",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(Nil) = bag.delete_object(table, "color", "red")
        let assert Ok(values) = bag.lookup(table, "color")
        expect.to_equal(values, ["blue"])
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
      it("delete_key removes all values for a key", fn() {
        let path = "/tmp/shelf_bag_del_key.dets"
        cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "bag_del_key",
            path: path,
            key: decode.string,
            value: decode.string,
          )
        let assert Ok(Nil) = bag.insert(table, "color", "red")
        let assert Ok(Nil) = bag.insert(table, "color", "blue")
        let assert Ok(Nil) = bag.delete_key(table, "color")
        expect.to_equal(bag.lookup(table, "color"), Error(shelf.NotFound))
        let assert Ok(Nil) = bag.close(table)
        cleanup(path)
        Nil
      }),
    ]),
  ])
}
