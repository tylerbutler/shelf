---
title: Common Patterns
description: Recipes for batch operations, folding, deletion, and exports across set, bag, and duplicate bag tables.
---

This page collects recipes for the operations you'll reach for most often
across `set`, `bag`, and `duplicate_bag` tables. Each example assumes a
table value `t` opened earlier with the appropriate decoders.

## Batch insert

`insert_list` writes many entries in one call, which is cheaper than a
loop of `insert` because the underlying ETS/DETS write happens in a
single batch.

```gleam
let assert Ok(Nil) = set.insert_list(into: t, entries: [
  #("alice", 42),
  #("bob", 99),
  #("charlie", 7),
])
```

The same shape works for `bag.insert_list` and `duplicate_bag.insert_list`.

## Folding

`fold` walks every entry without materialising the table as a list. Use
it for aggregates (counts, sums, max-by-something).

```gleam
let assert Ok(total) = set.fold(over: t, from: 0, with: fn(sum, _key, val) {
  sum + val
})
```

For bag and duplicate-bag tables, the same `fold` is called once per
`#(key, value)` pair.

## Counting and exporting

```gleam
// Count entries
let assert Ok(n) = set.size(of: t)

// Export all data (allocates a list — fine for small tables, expensive for large ones)
let assert Ok(entries) = set.to_list(from: t)
```

Prefer `size`/`fold` over `to_list` when you only need a count or
aggregate — `to_list` has to allocate the entire result list.

## Deletion

```gleam
let assert Ok(Nil) = set.delete_key(from: t, key: "alice")
let assert Ok(Nil) = set.delete_all(from: t)
```

`delete_object` behaves differently depending on the table type:

- **Bag / Duplicate Bag**: removes a specific `#(key, value)` pair while
  keeping other values for the same key.
- **Set**: acts as a *compare-and-delete* — only deletes if both the key
  and value match the stored entry. This is useful for optimistic
  concurrency.

```gleam
// Bag: removes only "red", keeps other values for "color"
let assert Ok(Nil) = bag.delete_object(from: t, key: "color", value: "red")

// Set: only deletes if the stored value for "key" matches "value"
let assert Ok(Nil) = set.delete_object(from: t, key: "key", value: "value")
```

## Atomic counters

`update_counter` performs a lock-free atomic add inside ETS. It avoids
the round-trip overhead of read-modify-write through an actor when many
producers share a counter.

```gleam
let assert Ok(Nil) = set.insert(into: t, key: "page_views", value: 0)
let assert Ok(1) = set.update_counter(in: t, key: "page_views", increment: 1)
let assert Ok(11) = set.update_counter(in: t, key: "page_views", increment: 10)
```

The increment can be negative. The stored value must already be an
integer.

## Safe resource management with `with_table`

`with_table` opens a table, runs your callback, and guarantees the table
is closed (and the final `save` attempted) even if the callback panics or
returns an error.

```gleam
let assert Ok(Nil) = {
  use table <- set.with_table(
    name: "cache",
    path: "cache.dets",
    base_directory: "/app/data",
    key: decode.string,
    value: decode.string,
  )
  set.insert(into: table, key: "key", value: "value")
}
```
