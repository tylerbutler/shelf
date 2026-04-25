/// Schema migration example: how to evolve key/value types between
/// application versions without losing existing data.
///
/// **Scenario**: an older version of the app stored sessions as plain
/// `String` user IDs. The new version wants to store them as
/// `#(String, Int)` pairs (user ID + creation timestamp). Opening the
/// new code against the old DETS file would fail with
/// `Error(TypeMismatch(...))` because the new value decoder rejects
/// the old data.
///
/// The procedure walks through the canonical 6-step migration:
///
///   1. Open the OLD DETS file as a temporary shelf table with the OLD
///      decoders so existing entries pass validation.
///   2. Read every entry with `to_list` (or `fold` for very large tables).
///   3. Transform the value into the new shape.
///   4. Write the transformed entries to a NEW path with the NEW decoders.
///   5. Atomically replace the old DETS file with the new one
///      (`simplifile.rename` is a POSIX rename on the same filesystem).
///   6. Reopen the (now-migrated) file with the new decoders for normal use.
///
/// See https://shelf.tylerbutler.com/advanced/schema-migration/ for the
/// prose version.
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import shelf/set
import simplifile

const data_dir = "/tmp"

const live_path = "shelf_examples_migration.dets"

const new_path = "shelf_examples_migration.new.dets"

pub fn main() {
  // Reset previous runs.
  let _ = simplifile.delete(data_dir <> "/" <> live_path)
  let _ = simplifile.delete(data_dir <> "/" <> new_path)

  seed_v1_file()
  io.println("✓ Seeded a v1 DETS file at " <> data_dir <> "/" <> live_path)

  migrate()
  io.println("✓ Migration complete")

  reopen_and_print()

  // Cleanup.
  let _ = simplifile.delete(data_dir <> "/" <> live_path)
  io.println("✓ Cleaned up example files")
}

// --- Setup: pretend a previous version of the app left a DETS file
// --- behind whose values are plain strings. ----------------------------

fn seed_v1_file() {
  let assert Ok(legacy) =
    set.open(
      name: "sessions_v1",
      path: live_path,
      base_directory: data_dir,
      key: decode.string,
      value: decode.string,
    )
  let assert Ok(Nil) =
    set.insert_list(into: legacy, entries: [
      #("alice", "u-1001"),
      #("bob", "u-1002"),
      #("carol", "u-1003"),
    ])
  let assert Ok(Nil) = set.close(legacy)
  Nil
}

// --- The 6-step migration. --------------------------------------------

fn migrate() {
  // Step 1: open OLD file with OLD decoders (so existing entries pass).
  let assert Ok(old_table) =
    set.open(
      name: "sessions_v1_migration",
      path: live_path,
      base_directory: data_dir,
      key: decode.string,
      value: decode.string,
    )

  // Step 2: read every entry. Use `fold` instead of `to_list` for
  //         very large tables to avoid materialising the whole list.
  let assert Ok(old_entries) = set.to_list(from: old_table)

  // Close the source before we touch the file on disk.
  let assert Ok(Nil) = set.close(old_table)

  // Step 3: transform values into the new shape `#(String, Int)`.
  //         No real timestamps on disk — use 0 for legacy rows.
  let new_entries =
    list.map(old_entries, fn(entry) {
      let #(name, user_id) = entry
      #(name, #(user_id, 0))
    })

  // Step 4: write to a temporary NEW path with the NEW decoders.
  let assert Ok(new_table) =
    set.open(
      name: "sessions_v2_migration",
      path: new_path,
      base_directory: data_dir,
      key: decode.string,
      value: new_value_decoder(),
    )
  let assert Ok(Nil) = set.insert_list(into: new_table, entries: new_entries)
  let assert Ok(Nil) = set.close(new_table)

  // Step 5: atomically replace the OLD file with the NEW file.
  //         simplifile.rename is a POSIX rename when source and
  //         destination are on the same filesystem — atomic from the
  //         perspective of any future open() at `live_path`.
  let assert Ok(Nil) =
    simplifile.rename(data_dir <> "/" <> new_path, data_dir <> "/" <> live_path)
  Nil
}

// Step 6: open the migrated file with the NEW decoders for normal use.
fn reopen_and_print() {
  let assert Ok(table) =
    set.open(
      name: "sessions_v2",
      path: live_path,
      base_directory: data_dir,
      key: decode.string,
      value: new_value_decoder(),
    )
  let assert Ok(entries) = set.to_list(from: table)
  io.println("  migrated entries:")
  list.each(entries, fn(entry) {
    let #(name, value) = entry
    let #(user_id, created_at) = value
    io.println(
      "    "
      <> name
      <> " -> user_id="
      <> user_id
      <> " created_at="
      <> int.to_string(created_at),
    )
  })
  let assert Ok(Nil) = set.close(table)
  Nil
}

fn new_value_decoder() -> decode.Decoder(#(String, Int)) {
  use user_id <- decode.field(0, decode.string)
  use created_at <- decode.field(1, decode.int)
  decode.success(#(user_id, created_at))
}
