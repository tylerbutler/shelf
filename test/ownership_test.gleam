import gleam/dynamic/decode
import gleam/erlang/process
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/set
import test_helpers

pub fn set_insert_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_insert_list_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_insert_new_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_delete_key_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  // Verify data is untouched
  let assert True = set.lookup(table, "key") == Ok(1)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_delete_object_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_delete_all_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  // Verify data is untouched
  let assert True = set.lookup(table, "key") == Ok(1)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_update_counter_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  // Verify counter is untouched
  let assert True = set.lookup(table, "hits") == Ok(0)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_save_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_sync_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_close_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  // Owner can still close
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_reload_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_lookup_from_non_owner_succeeds_test() {
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
  let assert True = r1 == Ok(1)
  let assert True = r2 == Ok(True)
  let assert True = r3 == Ok(2)
  // to_list returns unspecified order, just check it has 2 entries
  let assert Ok(entries) = r4
  let assert True =
    {
      entries
      |> list_length
    }
    == 2

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn set_fold_from_non_owner_succeeds_test() {
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
  let assert True = result == Ok(30)

  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn bag_insert_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = bag.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn duplicate_bag_insert_from_non_owner_returns_not_owner_test() {
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
  let assert True = result == Error(shelf.NotOwner)

  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn operations_on_closed_table_return_table_closed_test() {
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
  let assert True = set.insert(table, "key", 1) == Error(shelf.TableClosed)
  let assert True = set.lookup(table, "key") == Error(shelf.TableClosed)

  test_helpers.cleanup(path)
  Nil
}

import gleam/list

fn list_length(l: List(a)) -> Int {
  list.length(l)
}
