import gleam/dynamic/decode
import shelf
import shelf/set
import test_helper

@external(erlang, "close_test_ffi", "simulate_external_dets_close")
fn simulate_external_dets_close(path: String) -> Nil

@external(erlang, "close_test_ffi", "cleanup_after_failed_close")
fn cleanup_after_failed_close(path: String, name: String) -> Nil

pub fn returns_table_closed_and_tears_down_state_for_terminal_failures_test() -> Nil {
  let path = "/tmp/shelf_close_err.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "close_err",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "k", "v")

  simulate_external_dets_close(path)

  assert set.close(table) == Error(shelf.TableClosed)
  assert set.lookup(table, "k") == Error(shelf.TableClosed)

  cleanup_after_failed_close(path, "close_err")
  Nil
}

pub fn preserves_ets_data_on_retryable_save_failures_test() -> Nil {
  let directory = "/tmp/shelf_close_preserve"
  let path = "/tmp/shelf_close_preserve/table.dets"
  test_helper.prepare_retry_directory(directory, path)
  let assert Ok(table) =
    set.open(
      name: "close_preserve",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key1", "value1")

  test_helper.make_directory_read_only(directory)

  let assert Error(_) = set.close(table)
  let assert Ok("value1") = set.lookup(table, "key1")
  test_helper.make_directory_writable(directory)
  let assert Ok(Nil) = set.close(table)

  test_helper.cleanup_retry_directory(directory, path)
  Nil
}

pub fn allows_retrying_close_after_a_retryable_save_failure_test() -> Nil {
  let directory = "/tmp/shelf_close_usable"
  let path = "/tmp/shelf_close_usable/table.dets"
  test_helper.prepare_retry_directory(directory, path)
  let assert Ok(table) =
    set.open(
      name: "close_usable",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "a", "1")

  test_helper.make_directory_read_only(directory)

  let assert Error(_) = set.close(table)
  let assert Ok("1") = set.lookup(table, "a")
  let assert Ok(Nil) = set.insert(table, "b", "2")
  let assert Ok("2") = set.lookup(table, "b")
  test_helper.make_directory_writable(directory)
  let assert Ok(Nil) = set.close(table)

  test_helper.cleanup_retry_directory(directory, path)
  Nil
}

pub fn preserves_state_in_write_through_mode_test() -> Nil {
  let directory = "/tmp/shelf_close_wt"
  let path = "/tmp/shelf_close_wt/table.dets"
  test_helper.prepare_retry_directory(directory, path)

  let config =
    shelf.config(name: "close_wt", path: path, base_directory: "/tmp")
    |> shelf.write_mode(shelf.WriteThrough)
  let assert Ok(table) =
    set.open_config(config, key: decode.string, value: decode.string)
  let assert Ok(Nil) = set.insert(table, "x", "y")

  test_helper.make_directory_read_only(directory)

  let assert Error(_) = set.close(table)
  let assert Ok("y") = set.lookup(table, "x")
  test_helper.make_directory_writable(directory)
  let assert Ok(Nil) = set.close(table)

  test_helper.cleanup_retry_directory(directory, path)
  Nil
}
