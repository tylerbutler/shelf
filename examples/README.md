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
cd examples && gleam run -m shelf_examples/key_value_cache
```

## Examples

| Module | Table Type | Key Concepts |
|--------|-----------|--------------|
| [`key_value_cache`](src/shelf_examples/key_value_cache.gleam) | `PersistentSet` | Open, insert, lookup, batch insert, delete, size, to_list, save, close |
| [`user_session`](src/shelf_examples/user_session.gleam) | `PersistentSet` | WriteThrough mode, config builder, insert_new, member, error handling |
| [`tag_index`](src/shelf_examples/tag_index.gleam) | `PersistentBag` | Multiple values per key, deduplication, delete_object, delete_key |
| [`event_log`](src/shelf_examples/event_log.gleam) | `PersistentDuplicateBag` | Duplicate preservation, fold, size, to_list, delete_object |
| [`hit_counter`](src/shelf_examples/hit_counter.gleam) | `PersistentSet` | Atomic counters (update_counter), increment/decrement, fold aggregation |
| [`safe_resource`](src/shelf_examples/safe_resource.gleam) | `PersistentSet` | with_table auto-close, save/reload checkpoints, sync |
| [`schema_migration`](src/shelf_examples/schema_migration.gleam) | `PersistentSet` | Evolving the value type between app versions: temp shelf table + atomic file rename |

### key_value_cache

A simple string key-value cache using `PersistentSet`. Demonstrates the core CRUD workflow: open a table, insert entries individually and in batches, look up values, delete keys, and persist with save/close.

### user_session

A user session store using `PersistentSet` with **WriteThrough** mode for immediate persistence. Shows the config builder pattern, `insert_new` for conflict detection (`KeyAlreadyPresent` error), `member` checks, and pattern matching on `ShelfError` variants.

Each run resets only the `session_abc123` demo key. Other stored entries remain.
Run it with `cd examples && gleam run -m shelf_examples/user_session`.

### tag_index

A tag-to-article index using `PersistentBag` where each tag maps to multiple article IDs. Demonstrates bag-specific behavior: multiple distinct values per key, automatic deduplication of identical pairs, and selective deletion with `delete_object` vs `delete_key`.

### event_log

A page view event log using `PersistentDuplicateBag` where duplicate entries are meaningful. Shows how duplicate bags preserve identical key-value pairs (unlike bags), plus `fold` for per-page aggregation and `size` for total event counts.

### hit_counter

A page hit counter using `PersistentSet` atomic counters. Demonstrates `update_counter` for lock-free increments/decrements, counter initialization, and `fold` to compute totals across all counters.

### safe_resource

Demonstrates two resource management patterns:
1. **`with_table`** — automatic open/close via callback, guaranteed cleanup
2. **Manual save/reload** — checkpoint data with `save()`, undo unsaved changes with `reload()`, and flush to disk with `sync()`

### schema_migration

A worked end-to-end migration that walks through the canonical 6-step procedure: open the old DETS file with the previous decoders, transform every entry to the new value shape (`String` → `#(String, Int)`), write the result to a temporary path, atomically `rename` it over the live file, then reopen with the new decoders. Mirrors the procedure documented at [Schema Migration](https://shelf.tylerbutler.com/advanced/schema-migration/).
