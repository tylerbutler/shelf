/// A simple key-value cache using shelf's PSet (persistent set table).
///
/// This example demonstrates the core shelf/set API: opening a table,
/// inserting and looking up entries, batch operations, persistence,
/// and cleanup. All reads come from ETS (microsecond latency) while
/// data is automatically persisted to a DETS file on disk.
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import shelf/set

pub fn main() {
  // --- Open the table ---
  // Creates an ETS table for fast in-memory access and a DETS file
  // at the given path for disk persistence. If the file already exists,
  // its contents are loaded into ETS automatically.
  let assert Ok(table) =
    set.open(
      name: "kv_cache",
      path: "/tmp/shelf_examples_kv_cache.dets",
      key: decode.string,
      value: decode.string,
    )
  io.println("✓ Opened table 'kv_cache'")

  // --- Insert individual entries ---
  // Each insert writes to ETS immediately. In the default WriteBack mode,
  // DETS is only updated when you call save() or close().
  let assert Ok(Nil) =
    set.insert(into: table, key: "app_name", value: "My Gleam App")
  let assert Ok(Nil) = set.insert(into: table, key: "version", value: "1.0.0")
  let assert Ok(Nil) = set.insert(into: table, key: "log_level", value: "info")
  io.println("✓ Inserted 3 config entries")

  // --- Look up a value ---
  // Reads always hit ETS — consistent microsecond latency regardless
  // of table size or whether data has been saved to disk yet.
  let assert Ok(version) = set.lookup(from: table, key: "version")
  io.println("  version = " <> version)

  // --- Batch insert multiple entries ---
  // insert_list is more efficient than individual inserts when adding
  // many entries at once.
  let assert Ok(Nil) =
    set.insert_list(into: table, entries: [
      #("database_host", "localhost"),
      #("database_port", "5432"),
      #("max_connections", "100"),
    ])
  io.println("✓ Batch-inserted 3 more entries")

  // --- Check the table size ---
  let assert Ok(count) = set.size(of: table)
  io.println("  table size = " <> int.to_string(count))

  // --- Export all entries ---
  // to_list loads the entire table into a Gleam list. Useful for
  // debugging or serialization, but be mindful of memory with large tables.
  let assert Ok(entries) = set.to_list(from: table)
  io.println("  all entries:")
  list.each(entries, fn(entry) {
    io.println("    " <> entry.0 <> " = " <> entry.1)
  })

  // --- Overwrite an existing key ---
  // In a set table, inserting with an existing key replaces the value.
  let assert Ok(Nil) = set.insert(into: table, key: "log_level", value: "debug")
  let assert Ok(updated) = set.lookup(from: table, key: "log_level")
  io.println("✓ Updated log_level: " <> updated)

  // --- Delete a key ---
  let assert Ok(Nil) = set.delete_key(from: table, key: "max_connections")
  let assert Ok(new_count) = set.size(of: table)
  io.println(
    "✓ Deleted 'max_connections', size now = " <> int.to_string(new_count),
  )

  // --- Save explicitly ---
  // In WriteBack mode, call save() to snapshot ETS contents to DETS.
  // This uses ets:to_dets/2 internally — an efficient bulk transfer
  // that atomically replaces all DETS contents.
  let assert Ok(Nil) = set.save(table)
  io.println("✓ Saved table to disk")

  // --- Close the table ---
  // close() performs a final save, closes the DETS file, and deletes
  // the ETS table. The handle must not be used after this.
  let assert Ok(Nil) = set.close(table)
  io.println("✓ Closed table")

  // Note: The DETS file at /tmp/shelf_examples_kv_cache.dets persists
  // on disk. If you re-run this example, the table will load previously
  // saved data before new inserts overwrite it. Delete the file manually
  // to start fresh:
  //
  //   rm /tmp/shelf_examples_kv_cache.dets

  io.println("")
  io.println(
    "Done! The .dets file persists at /tmp/shelf_examples_kv_cache.dets",
  )
}
