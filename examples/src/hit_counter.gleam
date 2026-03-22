/// Hit Counter — a shelf example demonstrating atomic counters with PSet.
///
/// Uses `update_counter` to atomically increment integer values in an
/// ETS-backed persistent set table. This is the recommended pattern for
/// counters, rate limiters, and similar "increment a value by key" use cases.
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/string
import shelf/set

pub fn main() {
  // ── 1. Open a persistent set table ────────────────────────────────
  // Keys are page paths (String), values are hit counts (Int).
  let assert Ok(counter) =
    set.open(
      name: "hit_counter",
      path: "/tmp/shelf_examples_hit_counter.dets",
      key: decode.string,
      value: decode.int,
    )

  // ── 2. Initialize counters for several pages ──────────────────────
  // Setting each page's count to 0 so every page has a known starting value.
  let assert Ok(Nil) = set.insert(into: counter, key: "/", value: 0)
  let assert Ok(Nil) = set.insert(into: counter, key: "/about", value: 0)
  let assert Ok(Nil) = set.insert(into: counter, key: "/blog", value: 0)
  let assert Ok(Nil) =
    set.insert(into: counter, key: "/blog/gleam-rocks", value: 0)

  io.println("✓ Initialized counters for 4 pages")

  // ── 3. Simulate page hits with update_counter ─────────────────────
  // `update_counter` atomically increments the integer value for a key
  // and returns the new value — no read-modify-write race conditions.
  let assert Ok(_) = set.update_counter(in: counter, key: "/", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/", increment: 1)

  let assert Ok(_) =
    set.update_counter(in: counter, key: "/about", increment: 1)

  let assert Ok(_) = set.update_counter(in: counter, key: "/blog", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/blog", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/blog", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/blog", increment: 1)
  let assert Ok(_) = set.update_counter(in: counter, key: "/blog", increment: 1)

  let assert Ok(_) =
    set.update_counter(in: counter, key: "/blog/gleam-rocks", increment: 1)
  let assert Ok(_) =
    set.update_counter(in: counter, key: "/blog/gleam-rocks", increment: 1)

  io.println("✓ Simulated page hits")

  // ── 4. update_counter returns the new value after increment ───────
  let assert Ok(new_count) =
    set.update_counter(in: counter, key: "/", increment: 1)
  io.println(
    "  / after one more hit: " <> int.to_string(new_count) <> " (expected 4)",
  )

  // ── 5. Negative increment acts as a decrement ─────────────────────
  let assert Ok(decremented) =
    set.update_counter(in: counter, key: "/about", increment: -1)
  io.println(
    "  /about after decrement: "
    <> int.to_string(decremented)
    <> " (expected 0)",
  )

  // ── 6. Look up individual counter values ──────────────────────────
  let assert Ok(blog_hits) = set.lookup(from: counter, key: "/blog")
  io.println("  /blog hits: " <> int.to_string(blog_hits))

  let assert Ok(post_hits) = set.lookup(from: counter, key: "/blog/gleam-rocks")
  io.println("  /blog/gleam-rocks hits: " <> int.to_string(post_hits))

  // ── 7. Fold to compute total hits across all pages ────────────────
  let assert Ok(total) =
    set.fold(over: counter, from: 0, with: fn(sum, _page, hits) { sum + hits })
  io.println("\n  Total hits across all pages: " <> int.to_string(total))

  // ── 8. Print a report of all page hits ────────────────────────────
  let assert Ok(entries) = set.to_list(from: counter)
  io.println("\n── Hit Counter Report ──")
  print_entries(entries)

  // ── 9. Save and close ─────────────────────────────────────────────
  // save() flushes ETS → DETS so data survives restarts.
  // close() calls save() internally then releases both tables.
  let assert Ok(Nil) = set.save(counter)
  io.println("\n✓ Saved to disk")

  let assert Ok(Nil) = set.close(counter)
  io.println(
    "✓ Closed — data persisted at /tmp/shelf_examples_hit_counter.dets",
  )
}

/// Recursively prints each page and its hit count.
fn print_entries(entries: List(#(String, Int))) -> Nil {
  case entries {
    [] -> Nil
    [#(page, hits), ..rest] -> {
      io.println(
        "  " <> string.pad_end(page, to: 20, with: " ") <> int.to_string(hits),
      )
      print_entries(rest)
    }
  }
}
