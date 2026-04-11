# shelf

[![Package Version](https://img.shields.io/hexpm/v/shelf)](https://hex.pm/packages/shelf)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/shelf/)

Persistent ETS tables backed by DETS — fast in-memory access with automatic disk persistence for the BEAM.

Shelf combines ETS (fast, in-memory) with DETS (persistent, on-disk) to give you microsecond reads with durable storage. It implements the classic Erlang persistence pattern, wrapped in a type-safe Gleam API.

If you only need ETS or DETS individually, check out these excellent standalone wrappers:

- **[bravo](https://hex.pm/packages/bravo)** — Type-safe ETS wrapper for Gleam
- **[slate](https://hex.pm/packages/slate)** — Type-safe DETS wrapper for Gleam

Shelf coordinates both together, using Erlang's native `ets:to_dets/2` for efficient bulk saves from memory to disk.

## Quick Start

```sh
gleam add shelf
```

```gleam
import gleam/dynamic/decode
import shelf
import shelf/set

pub fn main() {
  // Open a persistent set — loads existing data from disk
  // Decoders validate data loaded from the DETS file
  let assert Ok(table) =
    set.open(name: "users", path: "data/users.dets",
      base_directory: "/app/data",
      key: decode.string, value: decode.int)

  // Fast writes (to ETS)
  let assert Ok(Nil) = set.insert(table, "alice", 42)
  let assert Ok(Nil) = set.insert(table, "bob", 99)

  // Fast reads (from ETS)
  let assert Ok(42) = set.lookup(table, "alice")

  // Persist to disk when ready
  let assert Ok(Nil) = set.save(table)

  // Close auto-saves
  let assert Ok(Nil) = set.close(table)
}
```

On next startup, `set.open` automatically loads the saved data back into ETS.

## How It Works

```
┌─────────────────────────────────────┐
│           Your Application          │
├─────────────────────────────────────┤
│         shelf (this library)        │
├──────────────────┬──────────────────┤
│    ETS (memory)  │   DETS (disk)    │
│  • μs reads      │  • persistence   │
│  • μs writes     │  • survives      │
│  • in-process    │    restarts      │
└──────────────────┴──────────────────┘
```

**Reads** always go to ETS — consistent microsecond latency regardless of table size.

**Writes** go to ETS immediately. When they hit DETS depends on the write mode:

| Write Mode | Behavior | Use Case |
|-----------|----------|----------|
| `WriteBack` (default) | ETS only; call `save()` to persist | High-throughput, periodic snapshots |
| `WriteThrough` | Both ETS and DETS on every write | Maximum durability |

## Write Modes

### WriteBack (default)

Writes go to ETS only. You control when to persist:

```gleam
let assert Ok(table) =
  set.open(name: "sessions", path: "data/sessions.dets",
    base_directory: "/app/data",
    key: decode.string, value: session_decoder)

// These are ETS-only (fast)
let assert Ok(Nil) = set.insert(table, "user:123", session)
let assert Ok(Nil) = set.insert(table, "user:456", session)

// Persist when ready (e.g., on a timer, after N writes)
let assert Ok(Nil) = set.save(table)

// Undo unsaved changes
let assert Ok(Nil) = set.reload(table)
```

> **Note**: In WriteBack mode, data written since the last `save()` is lost if the process crashes.
> Design your save schedule accordingly (e.g., periodic timer, after N writes, or at clean shutdown).

### WriteThrough

Every write persists immediately:

```gleam
let config =
  shelf.config(name: "accounts", path: "data/accounts.dets",
    base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) =
  set.open_config(config: config,
    key: decode.string, value: account_decoder)

// This writes to both ETS and DETS
let assert Ok(Nil) = set.insert(table, "acct:789", account)
```

## Table Types

### Set — unique keys

Each table type uses an opaque handle — `PSet(k, v)`, `PBag(k, v)`, or `PDuplicateBag(k, v)` — where "P" stands for "Persistent".

```gleam
import shelf
import shelf/set

let assert Ok(t) =
  set.open(name: "cache", path: "cache.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = set.insert(t, "key", "value")       // overwrites if exists
let assert Error(shelf.KeyAlreadyPresent) = set.insert_new(t, "key", "value2")
let assert Ok("value") = set.lookup(t, "key")
let assert Ok(True) = set.member(of: t, key: "key")      // check existence
```

### Bag — multiple distinct values per key

```gleam
import shelf/bag

let assert Ok(t) =
  bag.open(name: "tags", path: "tags.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = bag.insert(t, "color", "red")
let assert Ok(Nil) = bag.insert(t, "color", "blue")
let assert Ok(Nil) = bag.insert(t, "color", "red")    // ignored (duplicate)
let assert Ok(["red", "blue"]) = bag.lookup(t, "color")
```

### Duplicate Bag — duplicates allowed

```gleam
import shelf/duplicate_bag

let assert Ok(t) =
  duplicate_bag.open(name: "events", path: "events.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = duplicate_bag.insert(t, "click", "btn")
let assert Ok(Nil) = duplicate_bag.insert(t, "click", "btn")  // kept!
let assert Ok(["btn", "btn"]) = duplicate_bag.lookup(t, "click")
```

### API Comparison

Not all operations are available on every table type:

| Operation | Set | Bag | Duplicate Bag |
|-----------|-----|-----|---------------|
| `insert` | ✅ | ✅ | ✅ |
| `insert_list` | ✅ | ✅ | ✅ |
| `insert_new` | ✅ | — | — |
| `lookup` | single value | `List(v)` | `List(v)` |
| `member` | ✅ | ✅ | ✅ |
| `delete_key` | ✅ | ✅ | ✅ |
| `delete_object` | ✅ | ✅ | ✅ |
| `delete_all` | ✅ | ✅ | ✅ |
| `update_counter` | ✅ | — | — |
| `fold` | ✅ | ✅ | ✅ |
| `size` | ✅ | ✅ | ✅ |
| `to_list` | ✅ | ✅ | ✅ |

## Safe Resource Management

Use `with_table` to ensure tables are always closed:

```gleam
use table <- set.with_table("cache", "data/cache.dets",
  base_directory: "/app/data",
  key: decode.string, value: decode.string)
set.insert(table, "key", "value")
// table is auto-closed when the callback returns
```

## Persistence Operations

| Function | Behavior |
|----------|----------|
| `save(table)` | Atomic snapshot ETS → DETS (writes to temp file, then renames for crash safety) |
| `reload(table)` | Discard ETS, reload from DETS |
| `sync(table)` | Flush DETS write buffer to OS |
| `close(table)` | Save + close DETS + delete ETS |

**`save` vs `sync`**: `save()` atomically copies ETS contents into DETS using a temp-file-plus-rename strategy for crash safety — use this in WriteBack mode to persist your changes. `sync()` flushes DETS's internal write buffer to the OS filesystem — use this in WriteThrough mode when you need to guarantee durability after a write (DETS buffers writes for performance).

## Type Safety

All data loaded from DETS is validated through `gleam/dynamic/decode` decoders when a table is opened. This ensures types match your expectations, even when the DETS file was written by a previous session or a different version of your application.

```gleam
import gleam/dynamic/decode

// Decoders are required when opening any table
let assert Ok(t) =
  set.open(name: "users", path: "users.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.int)
```

Within a running session, Gleam's type system guarantees correctness — decoders only validate the DETS→ETS boundary at open time. The `save()` path is unaffected and still uses Erlang's efficient `ets:to_dets/2` bulk transfer.

> **Performance note**: Loading from DETS (on `open` and `reload`) decodes and inserts entries one at a time via streaming (`dets:foldl`), keeping peak memory at ~1× table size. This is a one-time startup cost — all subsequent reads and writes remain at raw ETS speed.

### Schema Migration

If you change the key or value types between application versions, `open()` returns `Error(TypeMismatch(...))` because existing DETS data fails the new decoders.

Strategies for handling schema changes:
1. **Delete and rebuild**: Delete the DETS file and repopulate from your source of truth
2. **Manual migration**: Write a one-time script that reads the old DETS file directly (via Erlang's `dets` module), transforms the data, and writes it back in the new format

## Error Handling

All operations return `Result(value, ShelfError)`. The error type covers all failure modes:

| Error | Cause |
|-------|-------|
| `NotFound` | Key doesn't exist (from `lookup`) |
| `KeyAlreadyPresent` | Key exists (from `insert_new`) |
| `TableClosed` | Table has been closed or doesn't exist |
| `NotOwner` | The calling process is not the table owner (see [Process Ownership](#process-ownership)) |
| `NameConflict` | A DETS file at this path is already open by another shelf table |
| `InvalidPath(String)` | File path escapes the base directory or contains unsafe characters |
| `FileError(String)` | DETS file couldn't be found, created, or opened |
| `FileSizeLimitExceeded` | DETS file exceeds the 2 GB limit |
| `TypeMismatch(List(DecodeError))` | Data loaded from DETS failed decoder validation |
| `ErlangError(String)` | Catch-all for unexpected Erlang-level errors |

```gleam
case set.open(name: "cache", path: "data/cache.dets",
  base_directory: "/app/data",
  key: decode.string, value: decode.string)
{
  Ok(table) -> use_table(table)
  Error(shelf.TypeMismatch(_errors)) -> io.println("DETS data doesn't match expected types!")
  Error(shelf.NameConflict) -> io.println("DETS file already open!")
  Error(shelf.InvalidPath(msg)) -> io.println("Invalid path: " <> msg)
  Error(shelf.FileError(msg)) -> io.println("File error: " <> msg)
  Error(err) -> io.println("Unexpected: " <> string.inspect(err))
}
```

## Atomic Counters

```gleam
let assert Ok(t) =
  set.open(name: "stats", path: "stats.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.int)
set.insert(t, "page_views", 0)
set.update_counter(t, "page_views", 1)   // Ok(1)
set.update_counter(t, "page_views", 10)  // Ok(11)
```

## Common Operations

### Batch Insert

```gleam
let assert Ok(Nil) = set.insert_list(into: t, entries: [
  #("alice", 42),
  #("bob", 99),
  #("charlie", 7),
])
```

### Delete

```gleam
let assert Ok(Nil) = set.delete_key(from: t, key: "alice")
let assert Ok(Nil) = set.delete_all(from: t)
```

`delete_object` behaves differently depending on the table type:

- **Bag / Duplicate Bag**: Removes a specific value while keeping other values for the same key.
- **Set**: Acts as a compare-and-delete — only deletes if both the key and value match the stored entry.

```gleam
// Bag: removes only "red", keeps other values for "color"
let assert Ok(Nil) = bag.delete_object(from: t, key: "color", value: "red")

// Set: only deletes if the stored value for "key" matches "value"
let assert Ok(Nil) = set.delete_object(from: t, key: "key", value: "value")
```

### Fold, Size, and Export

```gleam
// Count entries
let assert Ok(n) = set.size(of: t)

// Fold to compute aggregates
let assert Ok(total) = set.fold(over: t, from: 0, with: fn(sum, _key, val) {
  sum + val
})

// Export all data (careful — loads entire table into memory)
let assert Ok(entries) = set.to_list(from: t)
```

## Limitations

- **DETS file size**: 2 GB maximum per table
- **No ordered set**: DETS doesn't support `ordered_set`
- **Erlang only**: Requires the BEAM runtime (no JavaScript target)
- **Single node**: DETS is local to one node (use Mnesia for distribution)
- **Table names**: Names do not need to be globally unique — shelf uses unnamed ETS tables internally. However, DETS file paths must not conflict with other open tables.
- **Process ownership**: ETS tables are owned by the process that created them. If that process exits, the ETS table is deleted and unsaved data is lost. The DETS file on disk is preserved and reloaded on the next `open()`. In long-running applications, ensure the process that opens tables is supervised.
- **DETS atoms**: DETS requires atom-based table names. Shelf uses a hash-based pool to bound the number of atoms created, so atom exhaustion is not a concern in normal usage.
- **Opening large tables**: When opening a table, DETS entries are decoded and inserted one at a time via streaming (`dets:foldl`), reducing peak memory usage from ~3× table size to ~1×. This makes large table support practical, though startup time still scales linearly with table size.

## Security

All DETS file paths are validated against the provided `base_directory` to prevent path traversal attacks. Paths containing `..` segments or other unsafe patterns that would escape the base directory are rejected with an `InvalidPath` error.

## Process Ownership

ETS tables are owned by the process that calls `open()`. This determines what each process can do:

- **Reads** (`lookup`, `member`, `to_list`, `fold`, `size`) work from **any** process — ETS tables are created as `protected`.
- **Writes and lifecycle** (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`, `close`) are restricted to the **owner** process. Non-owner attempts return `Error(NotOwner)`.

If you need cross-process writes, wrap the table in a supervised actor/server that owns the table and forwards mutation requests.

### Crash Behavior

If the owning process crashes, the ETS table is deleted and unsaved data is lost. The DETS file is preserved — the next `open()` call reloads it.

For long-running applications:
- Open tables in a supervised process (e.g., an OTP GenServer or Gleam actor)
- Consider periodic `save()` calls for WriteBack mode
- Use WriteThrough mode for data that cannot tolerate loss

### Write Safety

Within the owner process, all shelf operations are individual ETS/DETS calls — there is no built-in transaction support. If you need atomic multi-key updates, coordinate through a single process (e.g., a GenServer).

For set tables, concurrent reads from other processes while the owner writes to *different* keys are safe. Writes to the *same* key result in last-writer-wins (no corruption, but potential data loss from the reader's perspective). Bag and duplicate bag tables follow the same model.

## See Also

- **[bravo](https://hex.pm/packages/bravo)** — Use ETS directly when you don't need disk persistence
- **[slate](https://hex.pm/packages/slate)** — Use DETS directly when you don't need in-memory speed
- **[Erlang ETS docs](https://www.erlang.org/doc/apps/stdlib/ets.html)** — Underlying ETS documentation
- **[Erlang DETS docs](https://www.erlang.org/doc/apps/stdlib/dets.html)** — Underlying DETS documentation

## Development

```sh
gleam test    # Run the test suite
gleam build   # Build the package
gleam format  # Format source code
```

Further documentation can be found at <https://hexdocs.pm/shelf>.
