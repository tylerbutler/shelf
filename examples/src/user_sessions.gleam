//// User Session Store Example
////
//// Demonstrates shelf's PSet with WriteThrough mode for a user session
//// store where every write is immediately persisted to disk — no
//// explicit `save()` call needed.
////
//// Key concepts shown:
////   - Config builder pattern with WriteThrough mode
////   - insert_new (fails if key exists) vs insert (upsert)
////   - member checks
////   - Error handling with case expressions
////   - Graceful handling of KeyAlreadyPresent and NotFound errors

import gleam/dynamic/decode
import gleam/io
import gleam/string
import shelf
import shelf/set

pub fn main() {
  let path = "shelf_examples_user_sessions.dets"

  // --- 1. Build configuration with WriteThrough mode ---
  // The builder pattern lets you start with defaults and override what you need.
  // WriteThrough means every write is immediately persisted to the DETS file,
  // so there's no need to call save() manually.
  let config =
    shelf.config("user_sessions", path, base_directory: "/tmp")
    |> shelf.write_mode(shelf.WriteThrough)

  // --- 2. Open the persistent set table ---
  let assert Ok(sessions) =
    set.open_config(config: config, key: decode.string, value: decode.string)
  io.println("✓ Opened user_sessions table with WriteThrough mode")

  // --- 3. Insert a new session (succeeds because the key is fresh) ---
  let assert Ok(Nil) =
    set.insert_new(into: sessions, key: "session_abc123", value: "alice")
  io.println("✓ Inserted session for alice")

  // --- 4. Try insert_new with the same key — demonstrates KeyAlreadyPresent ---
  // insert_new refuses to overwrite existing keys, which is useful for
  // guaranteeing uniqueness (e.g. session tokens must be unique).
  case set.insert_new(into: sessions, key: "session_abc123", value: "bob") {
    Ok(Nil) -> io.println("  Inserted (unexpected!)")
    Error(shelf.KeyAlreadyPresent) ->
      io.println(
        "✓ insert_new correctly rejected duplicate key \"session_abc123\"",
      )
    Error(other) -> io.println("  Unexpected error: " <> string.inspect(other))
  }

  // --- 5. Check membership ---
  let assert Ok(exists) = set.member(of: sessions, key: "session_abc123")
  case exists {
    True -> io.println("✓ session_abc123 exists in the table")
    False -> io.println("  session_abc123 not found (unexpected!)")
  }

  // --- 6. Look up an existing session ---
  let assert Ok(user) = set.lookup(from: sessions, key: "session_abc123")
  io.println("✓ Looked up session_abc123 → user: " <> user)

  // --- 7. Look up a non-existent key — demonstrates NotFound error ---
  case set.lookup(from: sessions, key: "session_nonexistent") {
    Ok(value) -> io.println("  Found: " <> string.inspect(value))
    Error(shelf.NotFound) ->
      io.println("✓ Correctly got NotFound for missing session")
    Error(other) -> io.println("  Unexpected error: " <> string.inspect(other))
  }

  // --- 8. Overwrite with regular insert (upsert semantics) ---
  // Unlike insert_new, regular insert always succeeds and overwrites
  // any existing value for the given key.
  let assert Ok(Nil) =
    set.insert(into: sessions, key: "session_abc123", value: "alice_renewed")
  io.println("✓ Overwrote session_abc123 with renewed session")

  // Verify the overwrite
  let assert Ok(updated_user) =
    set.lookup(from: sessions, key: "session_abc123")
  io.println("✓ Verified updated value: " <> updated_user)

  // --- 9. Close the table ---
  let assert Ok(Nil) = set.close(sessions)
  io.println("✓ Closed user_sessions table")

  // Note: Because we used WriteThrough mode, every insert above was
  // immediately persisted to disk. There's no need for an explicit
  // save() call before closing — all data is already safely on disk.
  io.println("")
  io.println("Done! WriteThrough mode ensured all writes were persisted")
  io.println("immediately — no explicit save() was needed.")
}
