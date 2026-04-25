---
title: Schema Migration
description: A 6-step procedure for evolving the key/value types in a shelf table without losing data.
---

When you change the key or value types your code uses for a shelf table
between application versions, the next `open()` against the existing
DETS file fails with `Error(TypeMismatch(...))` — the new decoders
reject the on-disk entries.

This page documents the canonical migration procedure. A runnable
implementation lives at
[`examples/src/schema_migration.gleam`](https://github.com/tylerbutler/shelf/blob/main/examples/src/schema_migration.gleam).

## When to migrate vs. when to rebuild

If the data is regenerable (a cache, a derived index), the simplest
"migration" is to delete the DETS file and let your app rebuild it on
next start. Only run a migration when the data is the source of truth or
recomputing it would be expensive.

## The procedure

Most schema migrations follow the same six steps:

### 1. Open the OLD file with the OLD decoders

Open the existing DETS file as a temporary shelf table using the
*previous* version's decoders, so existing entries pass validation.

```gleam
let assert Ok(old_table) =
  set.open(
    name: "sessions_v1_migration",
    path: "sessions.dets",
    base_directory: "/app/data",
    key: decode.string,
    value: decode.string, // old decoder
  )
```

### 2. Read every entry

Use `to_list` for tables that fit comfortably in memory, or `fold` for
very large tables (folding streams entries one at a time without
materialising the whole list).

```gleam
let assert Ok(old_entries) = set.to_list(from: old_table)
let assert Ok(Nil) = set.close(old_table)
```

Close the source table before touching the file on disk in step 5.

### 3. Transform values into the new shape

Pure data transformation in Gleam — no shelf calls.

```gleam
let new_entries =
  list.map(old_entries, fn(entry) {
    let #(name, user_id) = entry
    #(name, #(user_id, 0)) // legacy rows get timestamp 0
  })
```

### 4. Write to a NEW path with the NEW decoders

Open a fresh DETS file at a *different* path with the new decoders, then
insert the transformed entries. Using a separate path means a crash
during this step leaves the original file untouched.

```gleam
let assert Ok(new_table) =
  set.open(
    name: "sessions_v2_migration",
    path: "sessions.new.dets",
    base_directory: "/app/data",
    key: decode.string,
    value: new_value_decoder(),
  )
let assert Ok(Nil) = set.insert_list(into: new_table, entries: new_entries)
let assert Ok(Nil) = set.close(new_table)
```

### 5. Atomically replace the OLD file with the NEW one

Use a POSIX rename so the swap is atomic: any process that next opens
the live path sees either the old file or the new file, never a
half-written one.

```gleam
let assert Ok(Nil) =
  simplifile.rename(
    "/app/data/sessions.new.dets",
    "/app/data/sessions.dets",
  )
```

The rename must happen on the same filesystem to be atomic.

### 6. Reopen normally with the NEW decoders

The migration is complete. Open the live path the way the rest of your
app expects:

```gleam
let assert Ok(table) =
  set.open(
    name: "sessions",
    path: "sessions.dets",
    base_directory: "/app/data",
    key: decode.string,
    value: new_value_decoder(),
  )
```

## Frequently asked details

### Does the new file need to live at the same path as the old one?

No, but it usually should. The atom that shelf assigns to a path is
derived from the path string, so reopening at the same path keeps the
internal mapping stable across the migration. If you choose to keep the
new file at a different path, update every `open()` call site that
referenced the old path.

### Should I delete the old file first?

No — that would create a window where the data doesn't exist on disk.
The point of the temp-file + rename pattern is that the live path
*always* points at a complete, valid DETS file: either the old one or
the new one.

### How do I call `dets:open_file` directly from Gleam?

You don't need to. shelf's `open()` already wraps `dets:open_file` and
adds decoder-validated loading on top. For migrations, the recommended
pattern is to use shelf with two different decoders (one per version)
rather than dropping into raw Erlang.

### Are there cleanup steps after the rename?

If the migration succeeded, the old DETS file no longer exists (the
rename overwrote it) and nothing further is required. If the migration
fails partway, delete the temp `*.new.dets` file before retrying so the
next attempt starts from a clean slate. shelf's internal atom registry
and guardian process watch process exits, not file paths, so they do
not need manual cleanup between migrations.

### What about a "migration table" pattern?

The procedure above effectively *is* the temporary-table pattern: the
table opened in step 4 is a one-shot migration table that exists only
for the duration of the rewrite. There is no separate API for it.
