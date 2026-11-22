---
title: Limitations
description: Known limitations of shelf and its underlying storage engines.
---

Most of shelf's limits come from ETS and DETS, the OTP storage engines it wraps. The rest come from the choices shelf makes to keep one table per file and one writer per table.

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

shelf uses unnamed ETS tables internally, so table names are only labels and do not need to be unique. The file is what must be unique: within one VM, each canonical path and filesystem identity can have one live shelf table. Opening a second table through the same path, a hard link, or a filesystem-supported case or Unicode alias returns `Error(NameConflict)`. Reservations remain in place during save.

Use distinct file paths for each table:

```gleam
// These are fine — different file paths
set.open(name: "sessions", path: "sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
set.open(name: "cache", path: "cache.dets", base_directory: "/app/data", key: decode.string, value: decode.string)

// This would conflict if "sessions.dets" is already open
set.open(name: "other_sessions", path: "sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)
```

### Filesystem identity

To recognize the same file under two names, shelf needs reliable device and nonzero inode values. If the filesystem cannot provide them, opening returns `Error(FileError(reason))` without loading entries or returning a table handle. Use a filesystem that provides these values.

These reservations work inside one VM only. They do not lock files against other VMs or prevent concurrent external path replacement, so use trusted directories and contents.

### Hard links and save

Save replaces the file at the original path. Other hard links continue to name the old file. After a successful save, you can open that distinct file as a separate table.

## Process Ownership

ETS tables are owned by the process that calls `open()`. shelf creates ETS tables as `protected`, which determines what each process can do:

- **Reads** (`lookup`, `member`, `to_list`, `fold`, `size`) work from **any** process.
- **Writes and lifecycle** (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`, `close`) are restricted to the **owner** process. Non-owner attempts return `Error(NotOwner)`.

If you need cross-process writes, wrap the table in a supervised actor/server that owns the table and forwards mutation requests.

### Crash Behavior

If the owning process crashes or exits, the ETS table is automatically deleted — any unsaved data is lost. The DETS file on disk remains intact. When the application restarts and calls `open()` again, data is reloaded from the DETS file.

To limit the loss:
- In long-running applications, open tables in a supervised process (e.g., an OTP GenServer or Gleam actor), so a restart reopens the table
- In WriteBack mode, save on a schedule that matches how much you can lose
- Use WriteThrough mode for critical data, so each change reaches DETS before the write returns
