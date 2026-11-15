---
title: Write Modes
description: Choose between WriteBack and WriteThrough persistence strategies.
---

Choose when your writes reach DETS: save a batch with WriteBack, or send
each change to DETS with WriteThrough. Both modes serve reads from ETS.

## WriteBack (Default)

In WriteBack mode, writes go to ETS only. Call `save()` to snapshot the
changes to DETS. Successful close also saves the table.

```gleam
import gleam/dynamic/decode
import shelf/set

let assert Ok(table) =
  set.open(name: "sessions", path: "data/sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)

// Fast writes — ETS only
let assert Ok(Nil) = set.insert(into: table, key: "user:1", value: session_1)
let assert Ok(Nil) = set.insert(into: table, key: "user:2", value: session_2)

// Persist to disk when ready
let assert Ok(Nil) = set.save(table)
```

**Best for**: High-throughput writes where you can tolerate some data loss on crash.

:::caution[Data loss on crash]
In WriteBack mode, data written since the last `save()` is lost if the process crashes. Design your save schedule based on your durability needs — e.g., periodic timer, after every N writes, or at clean shutdown.
:::

### Discarding Unsaved Changes

Use `reload()` to discard unsaved ETS changes and restore from the last DETS snapshot:

```gleam
let assert Ok(Nil) = set.insert(into: table, key: "temp", value: "data")
// Changed our mind — discard unsaved changes
let assert Ok(Nil) = set.reload(table)
// "temp" key no longer exists
```

## WriteThrough

In WriteThrough mode, each write goes to DETS first, then ETS. If the DETS
write fails, shelf does not apply that change to ETS.

```gleam
import gleam/dynamic/decode
import shelf
import shelf/set

let config =
  shelf.config(name: "accounts", path: "data/accounts.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = set.open_config(config: config, key: decode.string, value: decode.string)

// This writes to both ETS and DETS
let assert Ok(Nil) = set.insert(into: table, key: "acct:1", value: account)
```

Use this mode when you want each change handed to DETS before the operation
returns, without saving a full-table snapshot.

### Flush DETS buffers and account for crash limits

After a WriteThrough write, the data has been handed to DETS but may still
be in DETS's in-memory write buffer. Call `sync()` to drain that buffer
into the on-disk DETS file:

```gleam
let assert Ok(Nil) = set.insert(into: table, key: "critical", value: value)
let assert Ok(Nil) = set.sync(table)
```

`sync()` does **not** call `fsync(2)` on the underlying file. For the full
layer-by-layer breakdown of what `save()` and `sync()` actually guarantee,
see the canonical [Durability story](/advanced/persistence-operations/#durability-story).

An owner-process exit removes ETS; the guardian closes DETS as part of
cleanup. A VM crash can lose writes still in DETS's buffer. Neither
WriteBack nor WriteThrough provides `fsync(2)`-level guarantees against
OS crashes or power loss. Choose another store if your application needs
those guarantees.

## Comparison

| | WriteBack | WriteThrough |
|---|-----------|-------------|
| Write speed | Fast (ETS only) | Slower (ETS + DETS) |
| On owner-process exit | Unsaved ETS changes are lost | Changes have reached DETS; cleanup closes the file |
| On VM crash | Unsaved ETS changes are lost | Buffered DETS writes may be lost |
| OS crash / power-loss guarantees | Not provided | Not provided |
| When to persist | `save()` or successful close | Each write reaches DETS; `sync()` flushes its buffer |
| `reload()` useful? | Yes — discards unsaved changes | Not typically — ETS and DETS are in sync |
| Best for | Caches, sessions, high-throughput | Accounts, config, audit logs |

## Setting Write Mode

Write mode is set at table creation via `Config`:

```gleam
import gleam/dynamic/decode
import shelf

// WriteBack (the default — no config needed)
let assert Ok(table) =
  set.open(name: "cache", path: "data/cache.dets", base_directory: "/app/data", key: decode.string, value: decode.string)

// WriteThrough (use config)
let config =
  shelf.config(name: "accounts", path: "data/accounts.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)
let assert Ok(table) =
  set.open_config(config: config, key: decode.string, value: decode.string)
```

Write mode applies to all table types — `set`, `bag`, and `duplicate_bag` all support both modes.
