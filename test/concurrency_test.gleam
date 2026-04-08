import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import shelf/set
import startest.{describe, it}
import startest/expect
import test_helpers

pub fn concurrency_tests() {
  describe("concurrency", [
    describe("concurrent reads", [
      it("multiple processes can read simultaneously", fn() {
        let path = "/tmp/shelf_conc_read.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "conc_read",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        // Insert test data
        let assert Ok(Nil) = set.insert(table, "a", 1)
        let assert Ok(Nil) = set.insert(table, "b", 2)
        let assert Ok(Nil) = set.insert(table, "c", 3)

        // Spawn 10 processes that all read concurrently
        let subject = process.new_subject()
        int.range(10, 0, [], list.prepend)
        |> list.each(fn(_i) {
          process.spawn(fn() {
            let r1 = set.lookup(table, "a")
            let r2 = set.lookup(table, "b")
            let r3 = set.lookup(table, "c")
            process.send(subject, #(r1, r2, r3))
          })
        })

        // Collect all results
        int.range(10, 0, [], list.prepend)
        |> list.each(fn(_i) {
          let assert Ok(#(r1, r2, r3)) = process.receive(subject, 5000)
          expect.to_equal(r1, Ok(1))
          expect.to_equal(r2, Ok(2))
          expect.to_equal(r3, Ok(3))
        })

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("concurrent writes to different keys", [
      it("rapid owner-process writes to different keys all succeed", fn() {
        let path = "/tmp/shelf_conc_write_diff.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "conc_write_diff",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        // Rapidly write many different keys
        let count = 100
        int.range(count, 0, [], list.prepend)
        |> list.each(fn(i) {
          let key = "key_" <> int.to_string(i)
          let assert Ok(Nil) = set.insert(table, key, i)
          Nil
        })

        // Verify all keys were written correctly
        int.range(count, 0, [], list.prepend)
        |> list.each(fn(i) {
          let key = "key_" <> int.to_string(i)
          expect.to_equal(set.lookup(table, key), Ok(i))
        })

        // Verify size
        let assert Ok(size) = set.size(table)
        expect.to_equal(size, count)

        // Spawn readers to verify data concurrently
        let subject = process.new_subject()
        int.range(10, 0, [], list.prepend)
        |> list.each(fn(i) {
          process.spawn(fn() {
            let key = "key_" <> int.to_string(i * 10)
            let result = set.lookup(table, key)
            process.send(subject, #(key, result))
          })
        })

        int.range(10, 0, [], list.prepend)
        |> list.each(fn(i) {
          let assert Ok(#(_key, Ok(val))) = process.receive(subject, 5000)
          expect.to_be_true(val >= 1 && val <= count)
          // Suppress unused variable warning
          let _ = i
          Nil
        })

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
    describe("concurrent writes to same key", [
      it("rapid owner-process overwrites to same key: last write wins", fn() {
        let path = "/tmp/shelf_conc_write_same.dets"
        test_helpers.cleanup(path)
        let assert Ok(table) =
          set.open(
            name: "conc_write_same",
            path: path,
            base_directory: "/tmp",
            key: decode.string,
            value: decode.int,
          )

        // Rapidly overwrite the same key many times
        let count = 100
        int.range(count, 0, [], list.prepend)
        |> list.each(fn(i) {
          let assert Ok(Nil) = set.insert(table, "shared", i)
          Nil
        })

        // Last write should win
        let assert Ok(value) = set.lookup(table, "shared")
        expect.to_equal(value, count)

        // Table should still be fully functional
        let assert Ok(Nil) = set.insert(table, "after", 999)
        expect.to_equal(set.lookup(table, "after"), Ok(999))

        // Concurrent reads should see consistent state
        let subject = process.new_subject()
        int.range(5, 0, [], list.prepend)
        |> list.each(fn(_i) {
          process.spawn(fn() {
            let result = set.lookup(table, "shared")
            process.send(subject, result)
          })
        })

        int.range(5, 0, [], list.prepend)
        |> list.each(fn(_i) {
          let assert Ok(Ok(val)) = process.receive(subject, 5000)
          expect.to_equal(val, count)
        })

        let assert Ok(Nil) = set.close(table)
        test_helpers.cleanup(path)
        Nil
      }),
    ]),
  ])
}
