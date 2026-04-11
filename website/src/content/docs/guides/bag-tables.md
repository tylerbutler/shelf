---
title: Bag Tables
description: Multiple distinct values per key with persistent bag tables.
---

Bag tables store multiple values per key, but silently ignore duplicate key-value pairs. Use bags when you need to associate several distinct values with a single key — like tags, categories, or group memberships.

## Opening a Bag Table

```gleam
import gleam/dynamic/decode
import shelf/bag

let assert Ok(table) =
  bag.open(name: "tags", path: "data/tags.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
```

For custom configuration, use `open_config`:

```gleam
import gleam/dynamic/decode
import shelf
import shelf/bag

let config =
  shelf.config(name: "tags", path: "data/tags.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = bag.open_config(config: config, key: decode.string, value: decode.string)
```

## Reading Data

```gleam
// Look up all values for a key (returns a list)
let assert Ok(colors) = bag.lookup(from: table, key: "color")
// colors: ["red", "blue"]

// Check if a key exists
let assert Ok(True) = bag.member(of: table, key: "color")

// Get the total number of objects (not unique keys)
let assert Ok(count) = bag.size(of: table)

// Get all entries
let assert Ok(entries) = bag.to_list(from: table)
```

### Folding

```gleam
let assert Ok(all_values) =
  bag.fold(over: table, from: [], with: fn(acc, _key, value) {
    [value, ..acc]
  })
```

## Writing Data

```gleam
// Insert a key-value pair
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "red")
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "blue")

// Duplicate key-value pairs are silently ignored
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "red")
// "color" still has ["red", "blue"]

// Insert multiple entries at once
let assert Ok(Nil) = bag.insert_list(into: table, entries: [
  #("shape", "circle"),
  #("shape", "square"),
])
```

:::note
Unlike set tables, bag tables do **not** support `insert_new` or `update_counter`.
:::

## Deleting Data

```gleam
// Delete all values for a key
let assert Ok(Nil) = bag.delete_key(from: table, key: "color")

// Delete a specific key-value pair (other values for the same key are kept)
let assert Ok(Nil) = bag.delete_object(from: table, key: "shape", value: "circle")
// "shape" still has ["square"]

// Delete all entries
let assert Ok(Nil) = bag.delete_all(from: table)
```

## Bag vs Set

| Behavior | Set | Bag |
|----------|-----|-----|
| Values per key | One (overwrites) | Many (distinct only) |
| `lookup` returns | Single value | `List(v)` |
| Duplicate pairs | Overwrites | Silently ignored |
| `insert_new` | ✅ | — |
| `update_counter` | ✅ | — |
