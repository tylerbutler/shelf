/// Tag Index — demonstrates shelf's PBag (persistent bag table).
///
/// A bag table allows multiple distinct values per key. Duplicate key-value
/// pairs are silently ignored, but the same key can map to many different
/// values. This makes bags ideal for inverted indexes, tagging systems, and
/// any one-to-many relationship.
///
/// Scenario: We maintain a tag→article index where each tag (String) maps
/// to one or more article IDs (Int).
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/string
import shelf/bag

pub fn main() {
  // --- 1. Open a persistent bag table ---
  // The table is backed by an ETS bag in memory and a DETS file on disk.
  let assert Ok(tags) =
    bag.open(
      name: "tag_index",
      path: "shelf_examples_tag_index.dets",
      base_directory: "/tmp",
      key: decode.string,
      value: decode.int,
    )

  // --- 2. Insert tag → article mappings ---
  // A bag allows the same key to appear with different values.
  // "gleam" → articles 1 and 2, "erlang" → articles 2 and 3, etc.
  let assert Ok(Nil) = bag.insert(into: tags, key: "gleam", value: 1)
  let assert Ok(Nil) = bag.insert(into: tags, key: "gleam", value: 2)
  let assert Ok(Nil) = bag.insert(into: tags, key: "erlang", value: 2)
  let assert Ok(Nil) = bag.insert(into: tags, key: "erlang", value: 3)
  let assert Ok(Nil) = bag.insert(into: tags, key: "beam", value: 1)
  let assert Ok(Nil) = bag.insert(into: tags, key: "beam", value: 2)
  let assert Ok(Nil) = bag.insert(into: tags, key: "beam", value: 3)

  io.println("Inserted 7 tag-article pairs across 3 tags.")

  // --- 3. Lookup all articles for a tag ---
  // Unlike a set (which returns a single value), a bag returns a List of
  // all values associated with the key.
  let assert Ok(gleam_articles) = bag.lookup(from: tags, key: "gleam")
  io.println("Articles tagged 'gleam': " <> format_int_list(gleam_articles))

  // --- 4. Demonstrate deduplication ---
  // Inserting the same key-value pair again is a no-op in a bag.
  // (A duplicate_bag would keep both copies.)
  let assert Ok(Nil) = bag.insert(into: tags, key: "gleam", value: 1)
  let assert Ok(gleam_articles_after) = bag.lookup(from: tags, key: "gleam")
  io.println(
    "After re-inserting 'gleam'→1: " <> format_int_list(gleam_articles_after),
  )
  io.println("Same entries — duplicates are ignored in a bag.")

  // --- 5. Remove a specific tag-article pair with delete_object ---
  // This removes only the exact key-value pair, leaving other values for
  // the same key intact.
  let assert Ok(Nil) = bag.delete_object(from: tags, key: "beam", value: 3)
  let assert Ok(beam_articles) = bag.lookup(from: tags, key: "beam")
  io.println("After removing 'beam'→3: " <> format_int_list(beam_articles))

  // --- 6. Remove all articles for a tag with delete_key ---
  // This removes every value associated with the key.
  let assert Ok(Nil) = bag.delete_key(from: tags, key: "erlang")
  let assert Ok(erlang_articles) = bag.lookup(from: tags, key: "erlang")
  io.println(
    "After deleting all 'erlang' entries: " <> format_int_list(erlang_articles),
  )

  // --- 7. Check membership after deletion ---
  let assert Ok(has_erlang) = bag.member(of: tags, key: "erlang")
  let assert Ok(has_gleam) = bag.member(of: tags, key: "gleam")
  io.println(
    "Has 'erlang' tag? "
    <> string.inspect(has_erlang)
    <> "  Has 'gleam' tag? "
    <> string.inspect(has_gleam),
  )

  // --- 8. Show total number of tag-article pairs ---
  let assert Ok(total) = bag.size(of: tags)
  io.println("Total tag-article pairs remaining: " <> int.to_string(total))

  // Dump everything for inspection
  let assert Ok(all_entries) = bag.to_list(from: tags)
  io.println("All entries:")
  io.println(string.inspect(all_entries))

  // --- 9. Save and close ---
  // save/1 flushes the ETS contents to the DETS file on disk.
  // close/1 calls save and then tears down both tables.
  let assert Ok(Nil) = bag.save(tags)
  io.println("Saved to disk.")
  let assert Ok(Nil) = bag.close(tags)
  io.println("Table closed. Done!")
}

/// Format a list of integers as a bracketed, comma-separated string.
fn format_int_list(ids: List(Int)) -> String {
  "[" <> string.join(ids |> list_map_to_string(), ", ") <> "]"
}

fn list_map_to_string(ids: List(Int)) -> List(String) {
  case ids {
    [] -> []
    [first, ..rest] -> [int.to_string(first), ..list_map_to_string(rest)]
  }
}
