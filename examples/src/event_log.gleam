/// Page view event log — demonstrates shelf's PDuplicateBag table type.
///
/// A duplicate bag preserves *all* inserted key-value pairs, even exact
/// duplicates (same key AND same value). This makes it perfect for event
/// logs where the same event can happen multiple times.
///
/// Scenario: We record page view events where the key is a URL path and
/// the value is a Unix timestamp. Two views of "/home" at time 1000 are
/// two distinct rows — unlike a regular bag which would deduplicate them.
///
import gleam/int
import gleam/io
import gleam/list
import shelf/duplicate_bag

pub fn main() {
  // ── 1. Open a duplicate_bag table ─────────────────────────────────────
  io.println("=== Page View Event Log (PDuplicateBag) ===\n")

  let assert Ok(table) =
    duplicate_bag.open(
      name: "event_log",
      path: "/tmp/shelf_examples_event_log.dets",
    )

  // ── 2. Insert page view events ────────────────────────────────────────
  // Some events are exact duplicates — same page AND same timestamp.
  // A duplicate_bag preserves every single insert.
  let assert Ok(Nil) =
    duplicate_bag.insert(into: table, key: "/home", value: 1_718_000_000)
  let assert Ok(Nil) =
    duplicate_bag.insert(into: table, key: "/home", value: 1_718_000_030)
  // Exact duplicate — same path, same timestamp (e.g. two users hit the
  // page at the same second). A bag would collapse these; a duplicate_bag
  // keeps both.
  let assert Ok(Nil) =
    duplicate_bag.insert(into: table, key: "/home", value: 1_718_000_030)

  let assert Ok(Nil) =
    duplicate_bag.insert(into: table, key: "/about", value: 1_718_000_010)
  let assert Ok(Nil) =
    duplicate_bag.insert(into: table, key: "/about", value: 1_718_000_045)

  // Batch insert several events at once
  let assert Ok(Nil) =
    duplicate_bag.insert_list(into: table, entries: [
      #("/blog/1", 1_718_000_005),
      #("/blog/1", 1_718_000_020),
      #("/blog/1", 1_718_000_020),
      #("/contact", 1_718_000_050),
    ])

  io.println("Inserted page view events (with intentional duplicates).\n")

  // ── 3. Look up events for a specific page ─────────────────────────────
  // Notice the duplicated timestamp 1_718_000_030 appears twice — that's
  // the key difference from a regular bag table.
  let assert Ok(home_views) = duplicate_bag.lookup(from: table, key: "/home")
  io.println(
    "/home views ("
    <> int.to_string(list.length(home_views))
    <> " events, including duplicates):",
  )
  list.each(home_views, fn(ts) { io.println("  " <> int.to_string(ts)) })

  let assert Ok(blog_views) = duplicate_bag.lookup(from: table, key: "/blog/1")
  io.println(
    "\n/blog/1 views (" <> int.to_string(list.length(blog_views)) <> " events):",
  )
  list.each(blog_views, fn(ts) { io.println("  " <> int.to_string(ts)) })

  // ── 4. Count total events with size ───────────────────────────────────
  let assert Ok(total) = duplicate_bag.size(of: table)
  io.println("\nTotal events in log: " <> int.to_string(total))

  // ── 5. Fold to count events per page ──────────────────────────────────
  // Accumulate a list of #(page, count) pairs. For each event, either
  // increment the count for that page or add a new entry.
  let assert Ok(page_counts) =
    duplicate_bag.fold(over: table, from: [], with: fn(acc, page, _timestamp) {
      increment_count(acc, page)
    })

  io.println("\nEvents per page:")
  list.each(page_counts, fn(entry) {
    io.println("  " <> entry.0 <> ": " <> int.to_string(entry.1))
  })

  // ── 6. Export all events with to_list ─────────────────────────────────
  let assert Ok(all_events) = duplicate_bag.to_list(from: table)
  io.println(
    "\nAll events (" <> int.to_string(list.length(all_events)) <> " total):",
  )
  list.each(all_events, fn(event) {
    io.println("  " <> event.0 <> " @ " <> int.to_string(event.1))
  })

  // ── 7. Delete events for one page ─────────────────────────────────────
  io.println("\nDeleting all /contact events...")
  let assert Ok(Nil) = duplicate_bag.delete_key(from: table, key: "/contact")

  let assert Ok(after_delete) = duplicate_bag.size(of: table)
  io.println("Events remaining: " <> int.to_string(after_delete))

  // Also demonstrate delete_object — remove one specific duplicate
  io.println("Deleting one /blog/1 @ 1718000020 event...")
  let assert Ok(Nil) =
    duplicate_bag.delete_object(
      from: table,
      key: "/blog/1",
      value: 1_718_000_020,
    )
  let assert Ok(blog_after) = duplicate_bag.lookup(from: table, key: "/blog/1")
  io.println(
    "/blog/1 events remaining: " <> int.to_string(list.length(blog_after)),
  )

  // ── 8. Save and close ─────────────────────────────────────────────────
  let assert Ok(Nil) = duplicate_bag.save(table)
  io.println("\nData saved to disk.")

  let assert Ok(Nil) = duplicate_bag.close(table)
  io.println("Table closed. Done!")
}

/// Helper: increment the count for `page` in a list of #(page, count) pairs.
/// If the page isn't in the list yet, add it with count 1.
fn increment_count(
  counts: List(#(String, Int)),
  page: String,
) -> List(#(String, Int)) {
  case counts {
    [] -> [#(page, 1)]
    [#(p, n), ..rest] if p == page -> [#(p, n + 1), ..rest]
    [first, ..rest] -> [first, ..increment_count(rest, page)]
  }
}
