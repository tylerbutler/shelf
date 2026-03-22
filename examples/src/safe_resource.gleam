/// Safe Resource Management — demonstrates shelf's resource-safety patterns.
///
/// This example covers two approaches to managing persistent tables:
///
/// 1. **with_table** — automatic open/close via a callback. The table is
///    guaranteed to close even if the callback returns an error.
/// 2. **Manual save/reload cycle** — checkpoint your data with save(),
///    then undo unsaved changes with reload(). Finish with sync() to
///    ensure the DETS write buffer is flushed to the OS.
import gleam/io
import gleam/string
import shelf/set

pub fn main() {
  pattern_1_with_table()
  io.println("")
  pattern_2_save_reload()
}

// ── Pattern 1: with_table (auto-close) ─────────────────────────────────

fn pattern_1_with_table() {
  io.println("=== Pattern 1: with_table (auto-close) ===")
  io.println("")

  // with_table opens the table, runs your callback, and closes the table
  // automatically — even if the callback fails. The return value of the
  // callback is forwarded as the overall result.
  let assert Ok(greeting) =
    set.with_table("safe_auto", "/tmp/shelf_examples_safe_auto.dets", fn(table) {
      // Inside the callback the table is open and ready to use.
      let assert Ok(Nil) =
        set.insert(into: table, key: "language", value: "Gleam")
      let assert Ok(Nil) =
        set.insert(into: table, key: "runtime", value: "BEAM")
      io.println("  Inserted 'language' and 'runtime'")

      // Look up a value and build a result to return.
      let assert Ok(lang) = set.lookup(from: table, key: "language")
      let message = "Hello from " <> lang <> "!"
      io.println("  Looked up language → " <> lang)

      // The callback's Ok value becomes with_table's Ok value.
      Ok(message)
    })

  // The table is now closed — we only have the returned value.
  io.println("  Table auto-closed.")
  io.println("  Returned: " <> greeting)
}

// ── Pattern 2: Manual save/reload cycle (checkpoint & undo) ─────────────

fn pattern_2_save_reload() {
  io.println("=== Pattern 2: save/reload (checkpoint & undo) ===")
  io.println("")

  // --- Step 1: Open the table manually ---
  let assert Ok(table) =
    set.open(name: "safe_manual", path: "/tmp/shelf_examples_safe_manual.dets")
  io.println("  Opened table 'safe_manual'")

  // --- Step 2: Insert initial data and checkpoint with save ---
  let assert Ok(Nil) = set.insert(into: table, key: "color", value: "blue")
  let assert Ok(Nil) = set.insert(into: table, key: "size", value: "large")
  let assert Ok(Nil) = set.save(table)
  io.println("  Inserted 'color'='blue', 'size'='large' → saved (checkpoint)")

  // --- Step 3: Make more changes (unsaved) ---
  let assert Ok(Nil) = set.insert(into: table, key: "color", value: "red")
  let assert Ok(Nil) = set.insert(into: table, key: "shape", value: "circle")
  io.println("  Changed 'color' to 'red', added 'shape'='circle' (unsaved)")

  // --- Step 4: Show current state ---
  let assert Ok(current) = set.to_list(from: table)
  io.println("  Current state: " <> format_entries(current))

  // --- Step 5: Reload to discard unsaved changes ---
  // reload() replaces ETS contents with whatever was last saved to DETS.
  // This effectively "undoes" every write since the last save().
  let assert Ok(Nil) = set.reload(table)
  io.println("  Called reload → unsaved changes discarded")

  // --- Step 6: Verify the undo ---
  let assert Ok(reverted) = set.to_list(from: table)
  io.println("  State after reload: " <> format_entries(reverted))

  // The key "shape" is gone and "color" is back to "blue".
  let assert Ok(color) = set.lookup(from: table, key: "color")
  io.println("  color = " <> color <> " (back to checkpoint value)")

  // --- Step 7: Insert new data and save again ---
  let assert Ok(Nil) = set.insert(into: table, key: "shape", value: "square")
  let assert Ok(Nil) = set.save(table)
  io.println("  Inserted 'shape'='square' → saved")

  // --- Step 8: Sync to flush the DETS write buffer ---
  // sync() ensures the DETS file's OS-level write buffer is flushed.
  // Useful before a planned shutdown or when durability is critical.
  let assert Ok(Nil) = set.sync(table)
  io.println("  Called sync → DETS buffer flushed to disk")

  // --- Step 9: Close ---
  let assert Ok(Nil) = set.close(table)
  io.println("  Table closed.")

  io.println("")
  io.println("Done! Both patterns demonstrated safe resource management.")
}

/// Format a list of key-value pairs for display.
fn format_entries(entries: List(#(String, String))) -> String {
  let parts = do_format_entries(entries)
  "[" <> string.join(parts, ", ") <> "]"
}

fn do_format_entries(entries: List(#(String, String))) -> List(String) {
  case entries {
    [] -> []
    [#(k, v), ..rest] -> [k <> "=" <> v, ..do_format_entries(rest)]
  }
}
