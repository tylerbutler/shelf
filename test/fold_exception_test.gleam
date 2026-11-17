import gleam/dynamic/decode
import gleam/list
import shelf
import shelf/bag
import shelf/duplicate_bag
import shelf/internal
import shelf/set

type TableKind {
  Set
  Bag
  DuplicateBag
}

type Failure {
  NativeError
  Badarg
  Throw
  Exit
}

type Marker {
  CallbackFailure(String, String, String, String)
}

type Fold =
  fn(Int, fn(Int, String, Int) -> Int) -> Result(Int, shelf.ShelfError)

@external(erlang, "fold_exception_test_ffi", "with_directory")
fn with_directory(body: fn(String) -> a) -> a

@external(erlang, "fold_exception_test_ffi", "finally")
fn finally(cleanup: fn() -> Nil, body: fn() -> a) -> a

@external(erlang, "fold_exception_test_ffi", "assert_propagates")
fn assert_propagates(
  run: fn(fn() -> Int) -> Result(Int, shelf.ShelfError),
  callback: fn() -> Int,
) -> Nil

@external(erlang, "fold_exception_test_ffi", "fail")
fn fail(failure: Failure) -> Int

@external(erlang, "fold_exception_test_ffi", "deleted_table")
fn deleted_table(body: fn(internal.EtsReference) -> a) -> a

@external(erlang, "storage_safety_test_ffi", "in_other_process")
fn in_other_process(body: fn() -> a) -> a

fn with_fold(kind: TableKind, body: fn(Fold, fn() -> Nil) -> Nil) -> Nil {
  use directory <- with_directory
  let path = directory <> "/table.dets"
  case kind {
    Set -> {
      let assert Ok(table) =
        set.open("fold", path, directory, decode.string, decode.int)
      let close = fn() { check_close(set.close(table)) }
      use <- finally(close)
      let assert Ok(Nil) = set.insert(table, "key", 7)
      body(fn(initial, callback) { set.fold(table, initial, callback) }, close)
    }
    Bag -> {
      let assert Ok(table) =
        bag.open("fold", path, directory, decode.string, decode.int)
      let close = fn() { check_close(bag.close(table)) }
      use <- finally(close)
      let assert Ok(Nil) = bag.insert(table, "key", 7)
      body(fn(initial, callback) { bag.fold(table, initial, callback) }, close)
    }
    DuplicateBag -> {
      let assert Ok(table) =
        duplicate_bag.open("fold", path, directory, decode.string, decode.int)
      let close = fn() { check_close(duplicate_bag.close(table)) }
      use <- finally(close)
      let assert Ok(Nil) = duplicate_bag.insert(table, "key", 7)
      body(
        fn(initial, callback) { duplicate_bag.fold(table, initial, callback) },
        close,
      )
    }
  }
}

fn check_close(result: Result(Nil, shelf.ShelfError)) -> Nil {
  assert result == Ok(Nil) || result == Error(shelf.TableClosed)
}

fn failed_assertion(result: Result(Int, String)) -> Int {
  let assert Ok(value) = result
  value
}

fn panic_callback() -> Int {
  panic as "original fold panic"
}

fn assertion_callback() -> Int {
  failed_assertion(Error("original fold assertion"))
}

fn check_failures(kind: TableKind) -> Nil {
  use fold, _close <- with_fold(kind)
  let run = fn(callback) {
    fold(0, fn(_accumulator, _key, _value) { callback() })
  }
  list.each([NativeError, Badarg, Throw, Exit], fn(failure) {
    assert_propagates(run, fn() { fail(failure) })
  })
  assert_propagates(run, panic_callback)
  assert_propagates(run, assertion_callback)
  assert_propagates(
    fn(callback) {
      fold(0, fn(_accumulator, _key, _value) {
        let assert Ok(value) = run(callback)
        value
      })
    },
    fn() { fail(Throw) },
  )
}

fn check_close_then_raise(kind: TableKind) -> Nil {
  let callbacks =
    list.map([NativeError, Badarg, Throw, Exit], fn(failure) {
      fn() { fail(failure) }
    })
  list.each([panic_callback, assertion_callback, ..callbacks], fn(callback) {
    use fold, close <- with_fold(kind)
    assert_propagates(
      fn(callback) { fold(0, fn(_accumulator, _key, _value) { callback() }) },
      fn() {
        close()
        callback()
      },
    )
  })
}

fn check_success_and_closed(kind: TableKind) -> Nil {
  use fold, close <- with_fold(kind)
  let sum = fn(accumulator, _key, value) { accumulator + value }
  assert fold(10, sum) == Ok(17)
  assert in_other_process(fn() { fold(10, sum) }) == Ok(17)
  // Nested invocations must not confuse the per-invocation exception tag.
  let assert Ok(7) =
    fold(0, fn(_accumulator, _key, _value) {
      let assert Ok(value) = fold(0, sum)
      value
    })
  close()
  assert fold(0, sum) == Error(shelf.TableClosed)
}

pub fn set_preserves_callback_exceptions_test() -> Nil {
  check_failures(Set)
}

pub fn bag_preserves_callback_exceptions_test() -> Nil {
  check_failures(Bag)
}

pub fn duplicate_bag_preserves_callback_exceptions_test() -> Nil {
  check_failures(DuplicateBag)
}

pub fn set_close_then_raise_test() -> Nil {
  check_close_then_raise(Set)
}

pub fn bag_close_then_raise_test() -> Nil {
  check_close_then_raise(Bag)
}

pub fn duplicate_bag_close_then_raise_test() -> Nil {
  check_close_then_raise(DuplicateBag)
}

pub fn set_success_and_closed_test() -> Nil {
  check_success_and_closed(Set)
}

pub fn bag_success_and_closed_test() -> Nil {
  check_success_and_closed(Bag)
}

pub fn duplicate_bag_success_and_closed_test() -> Nil {
  check_success_and_closed(DuplicateBag)
}

pub fn deleted_ets_returns_table_closed_test() -> Nil {
  use table <- deleted_table
  assert internal.fold(table, fn(_entry, accumulator) { accumulator }, 0)
    == Error(shelf.TableClosed)
}

pub fn marker_looking_callback_values_are_ordinary_values_test() -> Nil {
  use directory <- with_directory
  let marker = CallbackFailure("tag", "error", "reason", "stack")
  let assert Ok(table) =
    set.open(
      "fold_marker",
      directory <> "/table.dets",
      directory,
      decode.string,
      decode.int,
    )
  use <- finally(fn() { check_close(set.close(table)) })
  let assert Ok(Nil) = set.insert(table, "key", 7)
  assert set.fold(table, marker, fn(_accumulator, _key, _value) { marker })
    == Ok(marker)
}
