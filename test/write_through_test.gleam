import gleam/dynamic.{type Dynamic}
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, Dynamic)

pub fn write_through_tests() {
  describe("write_through", [
    it("writes persist immediately without explicit save", fn() {
      let path = "/tmp/shelf_wt_persist.dets"
      cleanup(path)

      // Open in WriteThrough mode
      let config =
        shelf.config(name: "wt_persist_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) = set.open_config(config)
      let assert Ok(Nil) = set.insert(table, "key", "value")

      // Close without explicit save — but WriteThrough already persisted
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify data is there
      let assert Ok(table) = set.open(name: "wt_persist_2", path: path)
      let assert Ok("value") = set.lookup(table, "key")
      let assert Ok(Nil) = set.close(table)
      cleanup(path)
      Nil
    }),
    it("deletes persist immediately in write-through mode", fn() {
      let path = "/tmp/shelf_wt_delete.dets"
      cleanup(path)

      let config =
        shelf.config(name: "wt_delete_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) = set.open_config(config)
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)
      let assert Ok(Nil) = set.delete_key(table, "a")
      let assert Ok(Nil) = set.close(table)

      // Reopen — "a" should be gone, "b" should remain
      let assert Ok(table) = set.open(name: "wt_delete_2", path: path)
      expect.to_equal(set.lookup(table, "a"), Error(shelf.NotFound))
      let assert Ok(2) = set.lookup(table, "b")
      let assert Ok(Nil) = set.close(table)
      cleanup(path)
      Nil
    }),
    it("counter updates persist in write-through mode", fn() {
      let path = "/tmp/shelf_wt_counter.dets"
      cleanup(path)

      let config =
        shelf.config(name: "wt_counter_1", path: path)
        |> shelf.write_mode(shelf.WriteThrough)
      let assert Ok(table) = set.open_config(config)
      let assert Ok(Nil) = set.insert(table, "count", 0)
      let assert Ok(5) = set.update_counter(table, "count", 5)
      let assert Ok(Nil) = set.close(table)

      // Reopen and verify counter persisted
      let assert Ok(table) = set.open(name: "wt_counter_2", path: path)
      let assert Ok(5) = set.lookup(table, "count")
      let assert Ok(Nil) = set.close(table)
      cleanup(path)
      Nil
    }),
  ])
}
