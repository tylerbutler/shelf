---
title: Write Modes
description: Choose between WriteBack and WriteThrough persistence strategies.
---

shelf supports two write modes that control when data is persisted to disk. Choose the mode that matches your durability and performance requirements.

## WriteBack (Default)

In WriteBack mode, writes go to ETS (memory) only. Data is persisted to DETS (disk) when you explicitly call `save()`, or automatically when the table is closed.

```gleam
import gleam/dynamic/decode
import shelf/set

let assert Ok(table) =
  set.open(name: "sessions", path: "data/sessions.dets", base_directory: "/app/data", key: decode.string, value: decode.string)

// Fast writes — ETS only
let assert Ok(Nil) = set.insert(table, "user:1", session_1)
let assert Ok(Nil) = set.insert(table, "user:2", session_2)

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
let assert Ok(Nil) = set.insert(table, "temp", "data")
// Changed our mind — discard unsaved changes
let assert Ok(Nil) = set.reload(table)
// "temp" key no longer exists
```

## WriteThrough

In WriteThrough mode, every write persists to both ETS and DETS immediately. Reads are still served from ETS (fast).

```gleam
import gleam/dynamic/decode
import shelf
import shelf/set

let config =
  shelf.config(name: "accounts", path: "data/accounts.dets", base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = set.open_config(config: config, key: decode.string, value: decode.string)

// This writes to both ETS and DETS
let assert Ok(Nil) = set.insert(table, "acct:1", account)
```

**Best for**: Data that must survive crashes with no loss — financial records, user accounts, configuration.

### Guaranteeing Durability

DETS buffers writes internally for performance. After a WriteThrough write, the data is in DETS but may still be in the OS write buffer. Use `sync()` to force the DETS buffer to the filesystem:

```gleam
let assert Ok(Nil) = set.insert(table, "critical", value)
let assert Ok(Nil) = set.sync(table)
// Data is now on disk
```

## Comparison

| | WriteBack | WriteThrough |
|---|-----------|-------------|
| Write speed | Fast (ETS only) | Slower (ETS + DETS) |
| Data loss on crash | Since last `save()` | None (after `sync()`) |
| When to persist | Manual `save()` call | Automatic on every write |
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
