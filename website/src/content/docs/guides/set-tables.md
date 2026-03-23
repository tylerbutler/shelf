---
title: Set Tables
description: Unique key-value storage with persistent set tables.
---

Set tables store one value per key — inserting with an existing key overwrites the previous value. This is the most common table type, equivalent to a persistent key-value store.

## Opening a Set Table

```gleam
import gleam/dynamic/decode
import shelf/set

let assert Ok(table) =
  set.open(name: "users", path: "data/users.dets", key: decode.string, value: decode.int)
```

If the DETS file exists, its contents are loaded into ETS automatically. If the file doesn't exist, both tables start empty.

For custom configuration (e.g., WriteThrough mode), use `open_config`:

```gleam
import gleam/dynamic/decode
import shelf
import shelf/set

let config =
  shelf.config(name: "users", path: "data/users.dets")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = set.open_config(config: config, key: decode.string, value: decode.int)
```

## Reading Data

```gleam
// Look up a single value
let assert Ok(value) = set.lookup(from: table, key: "alice")

// Check if a key exists (without fetching the value)
let assert Ok(True) = set.member(of: table, key: "alice")

// Get the number of entries
let assert Ok(count) = set.size(of: table)

// Get all entries as a list (loads entire table into memory)
let assert Ok(entries) = set.to_list(from: table)
```

### Folding

Fold over all entries to compute an aggregate. Order is unspecified.

```gleam
let assert Ok(total) =
  set.fold(over: table, from: 0, with: fn(acc, _key, value) {
    acc + value
  })
```

## Writing Data

```gleam
// Insert or overwrite
let assert Ok(Nil) = set.insert(into: table, key: "alice", value: 42)

// Insert only if key doesn't exist — returns Error(KeyAlreadyPresent) otherwise
let assert Ok(Nil) = set.insert_new(into: table, key: "bob", value: 99)

// Insert multiple entries at once
let assert Ok(Nil) = set.insert_list(into: table, entries: [
  #("charlie", 10),
  #("diana", 20),
])
```

:::note
`insert_new` is unique to set tables — bag and duplicate bag tables don't support it.
:::

## Deleting Data

```gleam
// Delete by key
let assert Ok(Nil) = set.delete_key(from: table, key: "alice")

// Delete a specific key-value pair (equivalent to delete_key for sets)
let assert Ok(Nil) = set.delete_object(from: table, key: "bob", value: 99)

// Delete all entries (keeps the table open)
let assert Ok(Nil) = set.delete_all(from: table)
```

## Atomic Counters

Set tables support atomic integer counters — useful for metrics, rate limiting, or any lock-free counting:

```gleam
let assert Ok(Nil) = set.insert(into: table, key: "page_views", value: 0)
let assert Ok(1) = set.update_counter(in: table, key: "page_views", increment: 1)
let assert Ok(11) = set.update_counter(in: table, key: "page_views", increment: 10)
let assert Ok(9) = set.update_counter(in: table, key: "page_views", increment: -2)
```

:::note
`update_counter` is unique to set tables and requires integer values.
:::

## Resource Management

Use `with_table` to ensure a table is always closed, even if an error occurs:

```gleam
let assert Ok(Nil) = {
  use table <- set.with_table("cache", "data/cache.dets", decode.string, decode.string)
  set.insert(into: table, key: "key", value: "value")
}
```

The callback must return `Result(a, ShelfError)`. The table is closed after the callback returns.
