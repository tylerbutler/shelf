import gleam/dynamic/decode
import shelf
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

@external(erlang, "writethrough_consistency_test_ffi", "close_dets_by_path")
fn close_dets_by_path(path: String) -> Nil

fn wt_open(name: String, path: String) {
  let config =
    shelf.config(name: name, path: path, base_directory: "/tmp")
    |> shelf.write_mode(shelf.WriteThrough)
  set.open_config(config, key: decode.string, value: decode.int)
}

pub fn writethrough_consistency_tests() {
  describe("WriteThrough DETS-first consistency", [
    it("insert: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_ins.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_ins", path)
      let assert Ok(Nil) = set.insert(table, "existing", 100)

      close_dets_by_path(path)

      set.insert(table, "new_key", 200) |> expect.to_be_error
      // ETS must NOT have the new key
      set.lookup(table, "new_key") |> expect.to_be_error
      // Original entry still present
      let assert Ok(100) = set.lookup(table, "existing")

      test_helpers.cleanup(path)
      Nil
    }),
    it("insert_list: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_insl.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_insl", path)
      let assert Ok(Nil) = set.insert(table, "pre", 1)

      close_dets_by_path(path)

      set.insert_list(table, [#("a", 10), #("b", 20)]) |> expect.to_be_error
      set.lookup(table, "a") |> expect.to_be_error
      let assert Ok(1) = set.lookup(table, "pre")

      test_helpers.cleanup(path)
      Nil
    }),
    it("delete_key: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_delk.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_delk", path)
      let assert Ok(Nil) = set.insert(table, "keep", 42)

      close_dets_by_path(path)

      set.delete_key(table, "keep") |> expect.to_be_error
      // ETS must still have the entry
      let assert Ok(42) = set.lookup(table, "keep")

      test_helpers.cleanup(path)
      Nil
    }),
    it("delete_object: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_delo.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_delo", path)
      let assert Ok(Nil) = set.insert(table, "stay", 99)

      close_dets_by_path(path)

      set.delete_object(table, "stay", 99) |> expect.to_be_error
      let assert Ok(99) = set.lookup(table, "stay")

      test_helpers.cleanup(path)
      Nil
    }),
    it("delete_all: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_dela.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_dela", path)
      let assert Ok(Nil) = set.insert(table, "a", 1)
      let assert Ok(Nil) = set.insert(table, "b", 2)

      close_dets_by_path(path)

      set.delete_all(table) |> expect.to_be_error
      let assert Ok(2) = set.size(table)

      test_helpers.cleanup(path)
      Nil
    }),
    it("insert_new: DETS failure leaves ETS unchanged", fn() {
      let path = "/tmp/shelf_wt_insn.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_insn", path)

      close_dets_by_path(path)

      set.insert_new(table, "fresh", 777) |> expect.to_be_error
      set.lookup(table, "fresh") |> expect.to_be_error

      test_helpers.cleanup(path)
      Nil
    }),
    it("update_counter: rolls back ETS on DETS failure", fn() {
      let path = "/tmp/shelf_wt_ctr.dets"
      test_helpers.cleanup(path)
      let assert Ok(table) = wt_open("wt_ctr", path)
      let assert Ok(Nil) = set.insert(table, "counter", 10)

      close_dets_by_path(path)

      set.update_counter(table, "counter", 5) |> expect.to_be_error
      // ETS must still have original value (10, not 15)
      let assert Ok(10) = set.lookup(table, "counter")

      test_helpers.cleanup(path)
      Nil
    }),
  ])
}
