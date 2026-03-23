---
title: Limitations
description: Known limitations of shelf and its underlying storage engines.
---

shelf inherits limitations from its underlying storage engines (ETS and DETS). Understanding these helps you design your application correctly.

## DETS File Size: 2 GB Maximum

DETS files are limited to 2 GB. Operations that would exceed this limit return `Error(FileSizeLimitExceeded)`.

If you need more than 2 GB of persistent data, consider:
- Splitting data across multiple tables
- Using a database (PostgreSQL, SQLite) for large datasets
- Using Mnesia for distributed storage

## No Ordered Set

DETS does not support the `ordered_set` table type. Only `set`, `bag`, and `duplicate_bag` are available through shelf.

If you need ordered iteration, use `to_list()` and sort the results in your application code.

## Erlang Only

shelf requires the BEAM runtime (Erlang/OTP) and does not support the JavaScript target. This is inherent — ETS and DETS are Erlang VM features.

**Requirements**: Erlang/OTP >= 26 (recommended: 27+)

## Single Node

DETS is local to one Erlang node. Data is not replicated or distributed. For multi-node persistence, consider:
- **Mnesia** — Built-in distributed database for Erlang
- **Raft-based solutions** — For consensus-based replication

## Table Names Must Be Unique

ETS table names are VM-global atoms. If you try to open a table with a name that's already in use by another ETS table (from shelf or any other library), you'll get `Error(NameConflict)`.

Use descriptive, namespaced names to avoid collisions:

```gleam
// Good — namespaced
set.open(name: "myapp_user_sessions", path: "data/sessions.dets", key: decode.string, value: decode.string)

// Risky — generic name might collide
set.open(name: "cache", path: "data/cache.dets", key: decode.string, value: decode.string)
```

## Process Ownership

ETS tables are owned by the process that created them. If that process crashes or exits, the ETS table is automatically deleted — any unsaved data is lost. The DETS file on disk remains intact.

When the application restarts and calls `open()` again, data is reloaded from the DETS file.

To mitigate this:
- Use `with_table` for short-lived operations
- In long-running applications, ensure the process that opens tables is supervised
- Use WriteThrough mode for critical data to minimize the window of potential data loss

## Error Handling

All shelf operations return `Result(value, ShelfError)`. The error variants are:

| Error | Cause |
|-------|-------|
| `NotFound` | Key doesn't exist (from `lookup`) |
| `KeyAlreadyPresent` | Key exists (from `insert_new`, set tables only) |
| `TypeMismatch` | Data loaded from disk didn't match the expected decoder types |
| `TableClosed` | Table has been closed or doesn't exist |
| `NameConflict` | An ETS table with this name is already open |
| `FileError(String)` | DETS file couldn't be found, created, or opened |
| `FileSizeLimitExceeded` | DETS file exceeds the 2 GB limit |
| `ErlangError(String)` | Catch-all for unexpected Erlang-level errors |
