---
title: Bag Tables
description: Multiple distinct values per key with persistent bag tables.
---

Bag tables store multiple values per key, but silently ignore duplicate key-value pairs. Use bags when you need to associate several distinct values with a single key — like tags, categories, or group memberships.

Create `/app/data` before opening the table. The examples assume a new
`tags.dets` file and follow one table from insertion through close.

## Opening a Bag Table

```gleam
import gleam/dynamic/decode
import shelf/bag

let assert Ok(table) =
  bag.open(name: "tags", path: "tags.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
```

For WriteThrough, open the table with `open_config` instead:

```gleam
import gleam/dynamic/decode
import shelf
import shelf/bag

let config =
  shelf.config(name: "tags", path: "tags.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = bag.open_config(config: config, key: decode.string, value: decode.string)
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

## Reading Data

Read the values you inserted from ETS:

```gleam
// Contains "red" and "blue", with no repeated "red".
let assert Ok(colors) = bag.lookup(from: table, key: "color")
let assert Ok(True) = bag.member(of: table, key: "color")

// Counts objects, not unique keys.
let assert Ok(count) = bag.size(of: table)
let assert Ok(entries) = bag.to_list(from: table)
```

Use `fold` to process each pair without first creating a list of the table:

```gleam
let assert Ok(all_values) =
  bag.fold(over: table, from: [], with: fn(acc, _key, value) {
    [value, ..acc]
  })
```

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

## Save and close

These examples use WriteBack, so changes stay in ETS until you save or
close the table. Successful close saves the remaining contents:

```gleam
let assert Ok(Nil) = bag.close(table)
```

Since the example deleted all entries, reopening this file gives you an
empty table. See [write modes](/guides/write-modes/) to choose when to persist.

## Bag vs Set

| Behavior | Set | Bag |
|----------|-----|-----|
| Values per key | One (overwrites) | Many (distinct only) |
| `lookup` returns | Single value | `List(v)` |
| Duplicate pairs | Overwrites | Silently ignored |
| `insert_new` | ✅ | — |
| `update_counter` | ✅ | — |
