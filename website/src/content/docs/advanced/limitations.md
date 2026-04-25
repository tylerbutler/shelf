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

## DETS File Paths Must Be Unique

shelf uses unnamed ETS tables internally, so table names do not need to be globally unique. However, each DETS file path can only be open by one shelf table at a time. Opening a second table with the same resolved file path returns `Error(NameConflict)`.

Use distinct file paths for each table:

```gleam
// These are fine — different file paths
set.open(name: "sessions", path: "sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
set.open(name: "cache", path: "cache.dets", base_directory: "/app/data", key: decode.string, value: decode.string)

// This would conflict if "sessions.dets" is already open
set.open(name: "other_sessions", path: "sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
```

## Process Ownership

ETS tables are owned by the process that calls `open()`. shelf creates ETS tables as `protected`, which determines what each process can do:

- **Reads** (`lookup`, `member`, `to_list`, `fold`, `size`) work from **any** process.
- **Writes and lifecycle** (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`, `close`) are restricted to the **owner** process. Non-owner attempts return `Error(NotOwner)`.

If you need cross-process writes, wrap the table in a supervised actor/server that owns the table and forwards mutation requests.

### Crash Behavior

If the owning process crashes or exits, the ETS table is automatically deleted — any unsaved data is lost. The DETS file on disk remains intact. When the application restarts and calls `open()` again, data is reloaded from the DETS file.

To mitigate this:
- Use `with_table` for short-lived operations
- In long-running applications, open tables in a supervised process (e.g., an OTP GenServer or Gleam actor)
- Use WriteThrough mode for critical data to minimize the window of potential data loss

## Error Handling

All shelf operations return `Result(value, ShelfError)`. The error variants are:

| Error | Cause |
|-------|-------|
| `NotFound` | Key doesn't exist (from `lookup`) |
| `KeyAlreadyPresent` | Key exists (from `insert_new`, set tables only) |
| `TableClosed` | Table has been closed or doesn't exist |
| `NotOwner` | The calling process is not the table owner (see Process Ownership above) |
| `NameConflict` | A DETS file at this path is already open by another shelf table |
| `InvalidPath(String)` | File path escapes the base directory or contains unsafe characters |
| `FileError(String)` | DETS file couldn't be found, created, or opened |
| `FileSizeLimitExceeded` | DETS file exceeds the 2 GB limit |
| `TypeMismatch(List(DecodeError))` | Data loaded from DETS failed decoder validation |
| `ErlangError(String)` | Catch-all for unexpected Erlang-level errors |
