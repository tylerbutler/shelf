import gleam/dynamic/decode
import gleam/list
import gleam/string
import shelf
import shelf/set
import storage_safety_test
import unitest

@external(erlang, "save_metadata_test_ffi", "is_macos")
fn is_macos() -> Bool

@external(erlang, "save_metadata_test_ffi", "identity")
fn identity(path: String) -> #(Int, Int, Int)

@external(erlang, "save_metadata_test_ffi", "with_handle")
fn with_handle(table: set.PersistentSet(k, v), fun: fn() -> a) -> a

pub fn unsupported_save_and_close_preserve_original_and_live_handle_test() -> Nil {
  use <- unitest.tag("unsupported_platform")
  // Deliberate, visible skip in the full macOS suite.
  use <- unitest.guard(!is_macos())
  use directory <- storage_safety_test.with_directory()
  let path = directory <> "/table.dets"
  let assert Ok(table) =
    set.open_config(
      shelf.config(
        "unsupported_platform",
        "table.dets",
        base_directory: directory,
      ),
      decode.string,
      decode.int,
    )
  use <- with_handle(table)
  let assert Ok(Nil) = set.sync(table)
  let original_identity = identity(path)
  let original_bytes = storage_safety_test.read_file(path)
  list.each([1, 2], fn(value) {
    let assert Ok(Nil) = set.insert(table, "key", value)
    list.each([set.save, set.close], fn(operation) {
      let assert Error(shelf.FileError(detail)) = operation(table)
      assert string.contains(detail, "native_metadata")
      assert string.contains(detail, "unsupported_platform")
      assert identity(path) == original_identity
      assert storage_safety_test.read_file(path) == original_bytes
      assert storage_safety_test.list_directory(directory) == ["table.dets"]
      assert set.lookup(table, "key") == Ok(value)
    })
    let assert Ok(Nil) = set.reload(table)
    assert set.lookup(table, "key") == Error(shelf.NotFound)
  })
}
