---
title: Duplicate Bag Tables
description: Persistent tables that allow duplicate key-value pairs.
---

Duplicate bag tables are like bag tables, but they preserve duplicate key-value pairs. Use these when you need to record every occurrence — event logs, audit trails, or time-series data.

## Opening a Duplicate Bag Table

```gleam
import gleam/dynamic/decode
import shelf/duplicate_bag

let assert Ok(table) =
  duplicate_bag.open(
    name: "events",
    path: "data/events.dets",
    base_directory: "/app/data",
    key: decode.string,
    value: decode.string,
  )
```

For custom configuration, use `open_config`:

```gleam
import gleam/dynamic/decode
import shelf
import shelf/duplicate_bag

let config =
  shelf.config(name: "events", path: "data/events.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) =
  duplicate_bag.open_config(config: config, key: decode.string, value: decode.string)
```

## Reading Data

```gleam
// Look up all values for a key (returns a list, including duplicates)
let assert Ok(clicks) = duplicate_bag.lookup(from: table, key: "click")
// clicks: ["btn_1", "btn_1", "btn_2"]

// Check if a key exists
let assert Ok(True) = duplicate_bag.member(of: table, key: "click")

// Get the total number of objects (counts duplicates)
let assert Ok(count) = duplicate_bag.size(of: table)

// Get all entries
let assert Ok(entries) = duplicate_bag.to_list(from: table)
```

### Folding

```gleam
let assert Ok(click_count) =
  duplicate_bag.fold(over: table, from: 0, with: fn(acc, key, _value) {
    case key == "click" {
      True -> acc + 1
      False -> acc
    }
  })
```

## Writing Data

```gleam
// Insert a key-value pair
let assert Ok(Nil) = duplicate_bag.insert(into: table, key: "click", value: "btn_1")

// Duplicates are preserved!
let assert Ok(Nil) = duplicate_bag.insert(into: table, key: "click", value: "btn_1")
// "click" now has ["btn_1", "btn_1"]

// Insert multiple entries at once
let assert Ok(Nil) = duplicate_bag.insert_list(into: table, entries: [
  #("hover", "menu"),
  #("hover", "menu"),
])
```

:::note
Like bag tables, duplicate bag tables do **not** support `insert_new` or `update_counter`.
:::

## Deleting Data

```gleam
// Delete all values for a key
let assert Ok(Nil) = duplicate_bag.delete_key(from: table, key: "click")

// Delete every occurrence of this exact key-value pair
let assert Ok(Nil) = duplicate_bag.delete_object(from: table, key: "hover", value: "menu")

// Delete all entries
let assert Ok(Nil) = duplicate_bag.delete_all(from: table)
```

## Bag vs Duplicate Bag

| Behavior | Bag | Duplicate Bag |
|----------|-----|---------------|
| Duplicate pairs | Silently ignored | Preserved |
| Use case | Distinct associations | Event logs, audit trails |
| `lookup` returns | Distinct values only | All values including duplicates |
