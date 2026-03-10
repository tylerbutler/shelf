# shelf

[![Package Version](https://img.shields.io/hexpm/v/shelf)](https://hex.pm/packages/shelf)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/shelf/)

Persistent ETS tables backed by DETS — fast in-memory access with automatic disk persistence for the BEAM.

> [!IMPORTANT]
> shelf is not yet 1.0. This means:
>
> - the API is unstable
> - features and APIs may be removed in minor releases
> - quality should not be considered production-ready
>
> We welcome usage and feedback in
> the meantime! We will do our best to minimize breaking changes regardless.

Shelf combines ETS (fast, in-memory) with DETS (persistent, on-disk) to give you microsecond reads with durable storage. It implements the classic Erlang persistence pattern, wrapped in a type-safe Gleam API.

If you only need ETS or DETS individually, check out these excellent standalone wrappers:

- **[bravo](https://hex.pm/packages/bravo)** — Type-safe ETS wrapper for Gleam
- **[slate](https://hex.pm/packages/slate)** — Type-safe DETS wrapper for Gleam

Shelf coordinates both together, using Erlang's native `ets:to_dets/2` and `ets:from_dets/2` for efficient bulk transfers between the two.

## Quick Start

```sh
gleam add shelf
```

```gleam
import shelf
import shelf/set

pub fn main() {
  // Open a persistent set — loads existing data from disk
  let assert Ok(table) = set.open(name: "users", path: "data/users.dets")

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
let assert Ok(table) = set.open(name: "sessions", path: "data/sessions.dets")

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
  shelf.config(name: "accounts", path: "data/accounts.dets")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) = set.open_config(config)

// This writes to both ETS and DETS
let assert Ok(Nil) = set.insert(table, "acct:789", account)
```

## Table Types

### Set — unique keys

Each table type uses an opaque handle — `PSet(k, v)`, `PBag(k, v)`, or `PDuplicateBag(k, v)` — where "P" stands for "Persistent".

```gleam
import shelf/set

let assert Ok(t) = set.open(name: "cache", path: "cache.dets")
let assert Ok(Nil) = set.insert(t, "key", "value")       // overwrites if exists
let assert Ok(Nil) = set.insert_new(t, "key", "value2")  // Error(KeyAlreadyPresent)
let assert Ok("value") = set.lookup(t, "key")
let assert Ok(True) = set.member(of: t, key: "key")      // check existence
```

### Bag — multiple distinct values per key

```gleam
import shelf/bag

let assert Ok(t) = bag.open(name: "tags", path: "tags.dets")
let assert Ok(Nil) = bag.insert(t, "color", "red")
let assert Ok(Nil) = bag.insert(t, "color", "blue")
let assert Ok(Nil) = bag.insert(t, "color", "red")    // ignored (duplicate)
let assert Ok(["red", "blue"]) = bag.lookup(t, "color")
```

### Duplicate Bag — duplicates allowed

```gleam
import shelf/duplicate_bag

let assert Ok(t) = duplicate_bag.open(name: "events", path: "events.dets")
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
use table <- set.with_table("cache", "data/cache.dets")
set.insert(table, "key", "value")
// table is auto-closed when the callback returns
```

## Persistence Operations

| Function | Behavior |
|----------|----------|
| `save(table)` | Snapshot ETS → DETS (replaces DETS contents) |
| `reload(table)` | Discard ETS, reload from DETS |
| `sync(table)` | Flush DETS write buffer to OS |
| `close(table)` | Save + close DETS + delete ETS |

**`save` vs `sync`**: `save()` copies ETS contents into DETS — use this in WriteBack mode to persist your changes. `sync()` flushes DETS's internal write buffer to the OS filesystem — use this in WriteThrough mode when you need to guarantee durability after a write (DETS buffers writes for performance).

## Error Handling

All operations return `Result(value, ShelfError)`. The error type covers all failure modes:

| Error | Cause |
|-------|-------|
| `NotFound` | Key doesn't exist (from `lookup`) |
| `KeyAlreadyPresent` | Key exists (from `insert_new`) |
| `TableClosed` | Table has been closed or doesn't exist |
| `NameConflict` | An ETS table with this name is already open |
| `FileError(String)` | DETS file couldn't be found, created, or opened |
| `FileSizeLimitExceeded` | DETS file exceeds the 2 GB limit |
| `ErlangError(String)` | Catch-all for unexpected Erlang-level errors |

```gleam
case set.open(name: "cache", path: "data/cache.dets") {
  Ok(table) -> use_table(table)
  Error(shelf.NameConflict) -> io.println("Table already open!")
  Error(shelf.FileError(msg)) -> io.println("File error: " <> msg)
  Error(err) -> io.println("Unexpected: " <> string.inspect(err))
}
```

## Atomic Counters

```gleam
let assert Ok(t) = set.open(name: "stats", path: "stats.dets")
set.insert(t, "page_views", 0)
set.update_counter(t, "page_views", 1)   // Ok(1)
set.update_counter(t, "page_views", 10)  // Ok(11)
```

## Limitations

- **DETS file size**: 2 GB maximum per table
- **No ordered set**: DETS doesn't support `ordered_set`
- **Erlang only**: Requires the BEAM runtime (no JavaScript target)
- **Single node**: DETS is local to one node (use Mnesia for distribution)
- **Table names**: Must be unique across all ETS tables in the VM

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
