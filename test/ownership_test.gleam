import gleam/dynamic/decode
import gleam/erlang/process
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn ownership_tests() {
  describe("ownership", [
    describe("non-owner writes return NotOwner", [
      it("set insert from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_insert.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_insert",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.insert(table, "key", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set insert_list from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_insert_list.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_insert_list",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.insert_list(table, [#("a", 1), #("b", 2)])
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set insert_new from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_insert_new.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_insert_new",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.insert_new(table, "key", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set delete_key from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_delete_key.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_delete_key",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "key", 1)

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.delete_key(table, "key")
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        // Verify data is untouched
        expect.to_equal(set.lookup(table, "key"), Ok(1))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set delete_object from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_delete_obj.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_delete_obj",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "key", 1)

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.delete_object(table, "key", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set delete_all from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_delete_all.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_delete_all",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "key", 1)

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.delete_all(table)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        // Verify data is untouched
        expect.to_equal(set.lookup(table, "key"), Ok(1))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set update_counter from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_counter.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_counter",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "hits", 0)

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.update_counter(table, "hits", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        // Verify counter is untouched
        expect.to_equal(set.lookup(table, "hits"), Ok(0))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("non-owner lifecycle operations return NotOwner", [
      it("set save from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_save.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_save",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.save(table)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set sync from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_sync.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_sync",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.sync(table)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set close from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_close.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_close",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.close(table)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        // Owner can still close
        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set reload from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_reload.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_reload",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.reload(table)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("cross-process reads succeed", [
      it("set lookup from non-owner succeeds", fn() {
        let path = "/tmp/shelf_own_read.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_read",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "a", 1)
        let assert Ok(Nil) = set.insert(table, "b", 2)

        let subject = process.new_subject()
        process.spawn(fn() {
          let r1 = set.lookup(table, "a")
          let r2 = set.member(table, "b")
          let r3 = set.size(table)
          let r4 = set.to_list(table)
          process.send(subject, #(r1, r2, r3, r4))
        })

        let assert Ok(#(r1, r2, r3, r4)) = process.receive(subject, 5000)
        expect.to_equal(r1, Ok(1))
        expect.to_equal(r2, Ok(True))
        expect.to_equal(r3, Ok(2))
        // to_list returns unspecified order, just check it has 2 entries
        let assert Ok(entries) = r4
        expect.to_equal(
          entries
            |> list_length,
          2,
        )

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
      it("set fold from non-owner succeeds", fn() {
        let path = "/tmp/shelf_own_fold.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_fold",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.insert(table, "a", 10)
        let assert Ok(Nil) = set.insert(table, "b", 20)

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = set.fold(table, 0, fn(acc, _k, v) { acc + v })
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Ok(30))

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("bag non-owner writes return NotOwner", [
      it("bag insert from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_bag_insert.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          bag.open(
            name: "own_bag_insert",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = bag.insert(table, "key", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("duplicate_bag non-owner writes return NotOwner", [
      it("duplicate_bag insert from non-owner returns NotOwner", fn() {
        let path = "/tmp/shelf_own_dbag_insert.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          duplicate_bag.open(
            name: "own_dbag_insert",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        let subject = process.new_subject()
        process.spawn(fn() {
          let result = duplicate_bag.insert(table, "key", 1)
          process.send(subject, result)
        })

        let assert Ok(result) = process.receive(subject, 5000)
        expect.to_equal(result, Error(shelf.NotOwner))

        let assert Ok(Nil) = duplicate_bag.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("owner process close still returns TableClosed after shutdown", [
      it("operations on closed table return TableClosed", fn() {
        let path = "/tmp/shelf_own_after_close.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "own_after_close",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )
        let assert Ok(Nil) = set.close(table)

        // After close, operations should return TableClosed
        expect.to_equal(set.insert(table, "key", 1), Error(shelf.TableClosed))
        expect.to_equal(set.lookup(table, "key"), Error(shelf.TableClosed))

        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}

import gleam/list

fn list_length(l: List(a)) -> Int {
  list.length(l)
}
