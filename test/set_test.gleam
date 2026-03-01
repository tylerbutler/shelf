import gleam/dynamic.{type Dynamic}
import gleam/list
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

pub fn set_tests() {
  describe("shelf/set", [
    describe("lifecycle", [
      it("opens and closes a table", fn() {
        let path = "/tmp/shelf_set_lifecycle.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_lifecycle", path: path)
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("with_table opens and auto-closes", fn() {
        let path = "/tmp/shelf_set_with_table.dets"
        cleanup(path)
        let assert Ok(42) = {
          use table <- set.with_table("set_with_table", path)
          let assert Ok(Nil) = set.insert(table, "key", 42)
          set.lookup(table, "key")
        }
        cleanup(path)
        Nil
      }),
    ]),
    describe("read/write", [
      it("inserts and looks up a value", fn() {
        let path = "/tmp/shelf_set_insert.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_insert", path: path)
        let assert Ok(Nil) = set.insert(table, "alice", 42)
        let assert Ok(42) = set.lookup(table, "alice")
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("overwrites existing key", fn() {
        let path = "/tmp/shelf_set_overwrite.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_overwrite", path: path)
        let assert Ok(Nil) = set.insert(table, "key", "first")
        let assert Ok(Nil) = set.insert(table, "key", "second")
        let assert Ok("second") = set.lookup(table, "key")
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("returns NotFound for missing key", fn() {
        let path = "/tmp/shelf_set_notfound.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_notfound", path: path)
        let result = set.lookup(table, "missing")
        expect.to_equal(result, Error(shelf.NotFound))
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("member checks key existence", fn() {
        let path = "/tmp/shelf_set_member.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_member", path: path)
        let assert Ok(Nil) = set.insert(table, "exists", 1)
        let assert Ok(True) = set.member(table, "exists")
        let assert Ok(False) = set.member(table, "nope")
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("insert_new fails on existing key", fn() {
        let path = "/tmp/shelf_set_insert_new.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_insert_new", path: path)
        let assert Ok(Nil) = set.insert_new(table, "key", "first")
        let result = set.insert_new(table, "key", "second")
        expect.to_equal(result, Error(shelf.KeyAlreadyPresent))
        let assert Ok("first") = set.lookup(table, "key")
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("insert_list inserts multiple entries", fn() {
        let path = "/tmp/shelf_set_insert_list.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_insert_list", path: path)
        let assert Ok(Nil) =
          set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
        let assert Ok(1) = set.lookup(table, "a")
        let assert Ok(2) = set.lookup(table, "b")
        let assert Ok(3) = set.lookup(table, "c")
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("delete", [
      it("delete_key removes an entry", fn() {
        let path = "/tmp/shelf_set_delete_key.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_delete_key", path: path)
        let assert Ok(Nil) = set.insert(table, "key", "val")
        let assert Ok(Nil) = set.delete_key(table, "key")
        expect.to_equal(set.lookup(table, "key"), Error(shelf.NotFound))
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("delete_all removes everything", fn() {
        let path = "/tmp/shelf_set_delete_all.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_delete_all", path: path)
        let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2)])
        let assert Ok(Nil) = set.delete_all(table)
        let assert Ok(0) = set.size(table)
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("query", [
      it("to_list returns all entries", fn() {
        let path = "/tmp/shelf_set_to_list.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_to_list", path: path)
        let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2)])
        let assert Ok(entries) = set.to_list(table)
        let sorted = list.sort(entries, fn(a, b) { string_compare(a.0, b.0) })
        expect.to_equal(sorted, [#("a", 1), #("b", 2)])
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("size returns entry count", fn() {
        let path = "/tmp/shelf_set_size.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_size", path: path)
        let assert Ok(0) = set.size(table)
        let assert Ok(Nil) =
          set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
        let assert Ok(3) = set.size(table)
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
      it("fold accumulates over entries", fn() {
        let path = "/tmp/shelf_set_fold.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_fold", path: path)
        let assert Ok(Nil) =
          set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
        let assert Ok(sum) =
          set.fold(table, from: 0, with: fn(acc, _key, val) { acc + val })
        expect.to_equal(sum, 6)
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
    ]),
    describe("counters", [
      it("update_counter increments", fn() {
        let path = "/tmp/shelf_set_counter.dets"
        cleanup(path)
        let assert Ok(table) = set.open(name: "set_counter", path: path)
        let assert Ok(Nil) = set.insert(table, "hits", 0)
        let assert Ok(1) = set.update_counter(table, "hits", 1)
        let assert Ok(3) = set.update_counter(table, "hits", 2)
        let assert Ok(0) = set.update_counter(table, "hits", -3)
        let assert Ok(Nil) = set.close(table)
        cleanup(path)
        Nil
      }),
    ]),
  ])
}

import gleam/string

fn string_compare(a: String, b: String) -> order.Order {
  string.compare(a, b)
}

import gleam/order
