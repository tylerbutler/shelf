import gleam/dynamic/decode
import shelf
import shelf/set
import test_helpers

pub fn catches_panics_and_still_closes_the_table_test() {
  let path = "/tmp/shelf_eh_panic.dets"
  test_helpers.cleanup(path)
  // with_table with a panicking callback
  let result =
    set.with_table(
      "eh_panic",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
      fun: fn(_table) {
        // This will panic
        panic as "intentional panic for test"
      },
    )
  // Should be Error, not a panic
  let assert Error(_) = result
  // Table should be closed — we can reopen with the same ETS name
  let assert Ok(table) =
    set.open(
      name: "eh_panic",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.close(table)
  test_helpers.cleanup(path)
  Nil
}

pub fn propagates_close_error_when_callback_succeeds_test() {
  // Verify normal operation works
  let path = "/tmp/shelf_eh_normal.dets"
  test_helpers.cleanup(path)
  let assert Ok(42) =
    set.with_table(
      "eh_normal",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
      fun: fn(table) {
        let assert Ok(Nil) = set.insert(table, "key", 42)
        set.lookup(table, "key")
      },
    )
  test_helpers.cleanup(path)
  Nil
}

pub fn returns_callback_error_over_close_error_test() {
  let path = "/tmp/shelf_eh_cb_err.dets"
  test_helpers.cleanup(path)
  let result =
    set.with_table(
      "eh_cb_err",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
      fun: fn(_table) { Error(shelf.NotFound) },
    )
  assert result == Error(shelf.NotFound)
  test_helpers.cleanup(path)
  Nil
}

pub fn force_cleans_up_after_a_close_error_test() {
  let dir = "/tmp/shelf_eh_close_retry"
  let path = "/tmp/shelf_eh_close_retry/table.dets"
  test_helpers.prepare_retry_directory(dir, path)

  let result =
    set.with_table(
      "eh_close_retry",
      path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
      fun: fn(table) {
        let assert Ok(Nil) = set.insert(table, "key", "value")
        test_helpers.make_directory_read_only(dir)
        Ok("done")
      },
    )

  test_helpers.make_directory_writable(dir)
  let assert Error(_) = result

  let assert Ok(table) =
    set.open(
      name: "eh_close_retry_reopen",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  assert set.lookup(table, "key") == Error(shelf.NotFound)
  let assert Ok(Nil) = set.close(table)

  test_helpers.cleanup_retry_directory(dir, path)
  Nil
}

pub fn type_mismatch_contains_decode_error_details_test() {
  let path = "/tmp/shelf_eh_tm_detail.dets"
  test_helpers.cleanup(path)
  // Write String values
  let assert Ok(t) =
    set.open(
      name: "eh_tm_detail_1",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(t, "key", "hello")
  let assert Ok(Nil) = set.close(t)
  // Reopen expecting Int values
  let result =
    set.open(
      name: "eh_tm_detail_2",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  case result {
    Error(shelf.TypeMismatch(errors)) -> {
      // Should have non-empty decode errors
      assert errors != []
      Nil
    }
    other -> {
      // Force fail if not TypeMismatch
      assert other == Error(shelf.TypeMismatch([]))
      Nil
    }
  }
  test_helpers.cleanup(path)
  Nil
}
