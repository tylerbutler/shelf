# Shelf Examples

Sample applications demonstrating [shelf](https://github.com/tylerbutler/shelf)'s capabilities. Each example is a standalone module that exercises a different part of the API.

These examples also serve as compile-time regression tests — breaking API changes in shelf will cause build failures here.

## Running

```bash
# Type-check all examples (used in CI)
cd examples && gleam check

# Build all examples
cd examples && gleam build

# Run a specific example
cd examples && gleam run -m key_value_cache
```

## Examples

| Module | Table Type | Key Concepts |
|--------|-----------|--------------|
| [`key_value_cache`](src/key_value_cache.gleam) | `PSet` | Open, insert, lookup, batch insert, delete, size, to_list, save, close |
| [`user_sessions`](src/user_sessions.gleam) | `PSet` | WriteThrough mode, config builder, insert_new, member, error handling |
| [`tag_index`](src/tag_index.gleam) | `PBag` | Multiple values per key, deduplication, delete_object, delete_key |
| [`event_log`](src/event_log.gleam) | `PDuplicateBag` | Duplicate preservation, fold, size, to_list, delete_object |
| [`hit_counter`](src/hit_counter.gleam) | `PSet` | Atomic counters (update_counter), increment/decrement, fold aggregation |
| [`safe_resource`](src/safe_resource.gleam) | `PSet` | with_table auto-close, save/reload checkpoints, sync |
| [`schema_migration`](src/schema_migration.gleam) | `PSet` | Evolving the value type between app versions: temp shelf table + atomic file rename |

### key_value_cache

A simple string key-value cache using `PSet`. Demonstrates the core CRUD workflow: open a table, insert entries individually and in batches, look up values, delete keys, and persist with save/close.

### user_sessions

A user session store using `PSet` with **WriteThrough** mode for immediate persistence. Shows the config builder pattern, `insert_new` for conflict detection (`KeyAlreadyPresent` error), `member` checks, and pattern matching on `ShelfError` variants.

### tag_index

A tag-to-article index using `PBag` where each tag maps to multiple article IDs. Demonstrates bag-specific behavior: multiple distinct values per key, automatic deduplication of identical pairs, and selective deletion with `delete_object` vs `delete_key`.

### event_log

A page view event log using `PDuplicateBag` where duplicate entries are meaningful. Shows how duplicate bags preserve identical key-value pairs (unlike bags), plus `fold` for per-page aggregation and `size` for total event counts.

### hit_counter

A page hit counter using `PSet` atomic counters. Demonstrates `update_counter` for lock-free increments/decrements, counter initialization, and `fold` to compute totals across all counters.

### safe_resource

Demonstrates two resource management patterns:
1. **`with_table`** — automatic open/close via callback, guaranteed cleanup
2. **Manual save/reload** — checkpoint data with `save()`, undo unsaved changes with `reload()`, and flush to disk with `sync()`

### schema_migration

A worked end-to-end migration that walks through the canonical 6-step procedure: open the old DETS file with the previous decoders, transform every entry to the new value shape (`String` → `#(String, Int)`), write the result to a temporary path, atomically `rename` it over the live file, then reopen with the new decoders. Mirrors the procedure documented at [Schema Migration](https://shelf.tylerbutler.com/advanced/schema-migration/).
