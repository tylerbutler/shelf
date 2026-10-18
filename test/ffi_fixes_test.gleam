import gleam/dynamic/decode
import shelf
import shelf/set
import test_helper

pub fn size_returns_table_closed_after_close_test() -> Nil {
  let path = "/tmp/shelf_ffi_size_closed.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "ffi_size_closed",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.close(table)
  let result = set.size(of: table)
  assert result == Error(shelf.TableClosed)
  test_helper.cleanup(path)
  Nil
}

pub fn member_returns_table_closed_after_close_test() -> Nil {
  let path = "/tmp/shelf_ffi_member_closed.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "ffi_member_closed",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.close(table)
  let result = set.member(table, "any_key")
  assert result == Error(shelf.TableClosed)
  test_helper.cleanup(path)
  Nil
}

pub fn lookup_returns_table_closed_after_close_test() -> Nil {
  let path = "/tmp/shelf_ffi_lookup_closed.dets"
  test_helper.cleanup(path)
  let assert Ok(table) =
    set.open(
      name: "ffi_lookup_closed",
      path: path,
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(Nil) = set.close(table)
  let result = set.lookup(table, "any_key")
  assert result == Error(shelf.TableClosed)
  test_helper.cleanup(path)
  Nil
}
