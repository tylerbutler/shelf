---
title: Set Tables
description: Unique key-value storage with persistent set tables.
---

Set tables store one value per key — inserting with an existing key overwrites the previous value. This is the most common table type, equivalent to a persistent key-value store.

Create `/app/data` before opening the table. The examples below assume a new
`users.dets` file and follow one table from insertion through close.

## Opening a Set Table

```gleam
import gleam/dynamic/decode
import shelf/set

let assert Ok(table) =
  set.open(name: "users", path: "users.dets", base_directory: "/app/data", key: decode.string, value: decode.int)
```

If the DETS file exists, its contents are loaded into ETS automatically. If the file doesn't exist, the table starts empty.

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

## Reading Data

With those entries inserted, you can read them from ETS:

```gleam
let assert Ok(42) = set.lookup(from: table, key: "alice")
let assert Ok(True) = set.member(of: table, key: "alice")
let assert Ok(count) = set.size(of: table)
let assert Ok(entries) = set.to_list(from: table)
```

`to_list` allocates a list of all entries. Use `fold` when you need an
aggregate instead. Iteration order is unspecified.

```gleam
let assert Ok(total) =
  set.fold(over: table, from: 0, with: fn(acc, _key, value) {
    acc + value
  })
```

## Deleting Data

```gleam
// Delete by key
let assert Ok(Nil) = set.delete_key(from: table, key: "alice")

// Compare-and-delete: only deletes if the stored value matches.
// If "bob" is not currently 99, nothing is removed — useful for
// optimistic concurrency where you want to avoid clobbering a
// concurrent update.
let assert Ok(Nil) = set.delete_object(from: table, key: "bob", value: 99)

// Delete all entries (keeps the table open)
let assert Ok(Nil) = set.delete_all(from: table)
```

## Atomic Counters

The owner can increment integer values with `update_counter`:

```gleam
let assert Ok(Nil) = set.insert(into: table, key: "page_views", value: 0)
let assert Ok(1) = set.update_counter(in: table, key: "page_views", increment: 1)
let assert Ok(11) = set.update_counter(in: table, key: "page_views", increment: 10)
let assert Ok(9) = set.update_counter(in: table, key: "page_views", increment: -2)
```

:::note
`update_counter` is unique to set tables and requires integer values.
Other processes must send increment requests to the owner.
:::

## Save and close

These examples use WriteBack, so changes stay in ETS until you save or
close the table. Successful close saves the remaining contents and releases
the table:

```gleam
let assert Ok(Nil) = set.close(table)
```

The example deleted every entry before it added the counter, so reopening
`users.dets` gives you a table with only `page_views`. See
[write modes](/guides/write-modes/) to choose when to persist.

## Other ways to open a set

To send each write to DETS as it happens, open the table with
`open_config` and WriteThrough instead:

```gleam
import gleam/dynamic/decode
import shelf
import shelf/set

let config =
  shelf.config(name: "users", path: "users.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = set.open_config(config: config, key: decode.string, value: decode.int)
```

For a short-lived table, `with_table` opens it, runs your callback, and
closes it even if an error occurs:

```gleam
let assert Ok(Nil) = {
  use table <- set.with_table("cache", "cache.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
  set.insert(into: table, key: "key", value: "value")
}
```

The callback must return `Result(a, ShelfError)`. The table is closed after the callback returns.
