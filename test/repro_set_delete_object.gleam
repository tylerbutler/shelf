import gleam/dynamic/decode
import gleam/io
import shelf
import shelf/set

pub fn main() {
  let config =
    shelf.config(
      name: "test_set_del",
      path: "/tmp/test_set_del.dets",
      base_directory: "/tmp",
    )
  let _ = set.open_config(config, decode.string, decode.string)
  // Need to ensure clean state, but open reloads. Since path is new/temp, should be empty or we delete all.

  let assert Ok(table) = set.open_config(config, decode.string, decode.string)
  let assert Ok(Nil) = set.delete_all(table)

  let assert Ok(Nil) = set.insert(table, "key1", "val1")

  // Try to delete with WRONG value
  let assert Ok(Nil) = set.delete_object(table, "key1", "WRONG_VAL")

  // Check if key still exists
  case set.lookup(table, "key1") {
    Ok("val1") -> io.println("Key still exists! Value parameter WAS used.")
    Error(shelf.NotFound) ->
      io.println("Key deleted! Value parameter WAS IGNORED.")
    _ -> io.println("Unexpected result")
  }

  let assert Ok(Nil) = set.close(table)
}
