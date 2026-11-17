# shelf

[![Package Version](https://img.shields.io/hexpm/v/shelf)](https://hex.pm/packages/shelf)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/shelf/)

Persistent ETS tables backed by DETS for Gleam on the BEAM.

Shelf combines in-memory ETS tables with DETS files through a type-safe Gleam API.
Reads use ETS. By default, you save changes with `save()` or on successful close;
WriteThrough sends each change to DETS before updating ETS. When you reopen a
table, your decoders validate the saved data before loading it into memory.

Use Shelf for local persistence when your data fits in memory and each DETS file
stays below 2 GB. One process owns each table and handles writes; other processes
can read it. Shelf does not provide transactions, replication, or durability
guarantees against OS crashes and power loss.

## Quick Start

```sh
gleam add shelf
mkdir -p /tmp/shelf-quick-start
```

Use this example in your application's main module, then run `gleam run`:

```gleam
import gleam/dynamic/decode
import gleam/io
import shelf/set

pub fn main() -> Nil {
  let assert Ok(table) =
    set.open(
      name: "users",
      path: "users.dets",
      base_directory: "/tmp/shelf-quick-start",
      key: decode.string,
      value: decode.int,
    )

  let assert Ok(Nil) = set.insert(into: table, key: "alice", value: 42)
  let assert Ok(Nil) = set.insert(into: table, key: "bob", value: 99)
  let assert Ok(42) = set.lookup(from: table, key: "alice")

  let assert Ok(Nil) = set.save(table)
  let assert Ok(Nil) = set.close(table)

  // Reopen and read saved values without inserting them again.
  let assert Ok(reopened) =
    set.open(
      name: "users",
      path: "users.dets",
      base_directory: "/tmp/shelf-quick-start",
      key: decode.string,
      value: decode.int,
    )
  let assert Ok(42) = set.lookup(from: reopened, key: "alice")
  let assert Ok(99) = set.lookup(from: reopened, key: "bob")
  let assert Ok(Nil) = set.close(reopened)
  io.println("Saved users loaded from DETS.")
}
```

The second table loads the saved values from DETS into fresh ETS storage.
The [website quick start](https://shelf.tylerbutler.com/quick-start/) also shows
how to check them in a separate application run.

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

**Reads** use ETS without DETS I/O after loading.

**Writes** follow the selected write mode:

| Write Mode | Behavior | Use Case |
|-----------|----------|----------|
| `WriteBack` (default) | ETS only; call `save()` to persist | High-throughput, periodic snapshots |
| `WriteThrough` | DETS first, then ETS on every write | Persist each change without a full snapshot |

## Write Modes

### WriteBack (default)

Writes go to ETS only. You control when to persist:

```gleam
let assert Ok(table) =
  set.open(name: "sessions", path: "data/sessions.dets",
    base_directory: "/app/data",
    key: decode.string, value: session_decoder)

// These are ETS-only (fast)
let assert Ok(Nil) = set.insert(into: table, key: "user:123", value: session)
let assert Ok(Nil) = set.insert(into: table, key: "user:456", value: session)

// Persist when ready (e.g., on a timer, after N writes)
let assert Ok(Nil) = set.save(table)

// Undo unsaved changes
let assert Ok(Nil) = set.reload(table)
```

> **Note**: In WriteBack mode, data written since the last `save()` is lost if the process crashes.
> Design your save schedule accordingly (e.g., periodic timer, after N writes, or at clean shutdown).

### WriteThrough

Every write goes to DETS before ETS:

```gleam
let config =
  shelf.config(name: "accounts", path: "data/accounts.dets",
    base_directory: "/app/data")
  |> shelf.write_mode(shelf.WriteThrough)

let assert Ok(table) =
  set.open_config(config: config,
    key: decode.string, value: account_decoder)

// This writes to both ETS and DETS
let assert Ok(Nil) = set.insert(into: table, key: "acct:789", value: account)
```

DETS can buffer these writes in memory. Use `sync()` to flush that buffer to
the file. Neither mode provides `fsync(2)`-level protection against OS crashes
or power loss; see [Persistence Operations](#persistence-operations).

## Table Types

### Set — unique keys

Each table type uses an opaque handle: `PersistentSet(k, v)`,
`PersistentBag(k, v)`, or `PersistentDuplicateBag(k, v)`.

```gleam
import shelf
import shelf/set

let assert Ok(table) =
  set.open(name: "cache", path: "cache.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = set.insert(into: table, key: "key", value: "value")       // overwrites if exists
let assert Error(shelf.KeyAlreadyPresent) = set.insert_new(into: table, key: "key", value: "value2")
let assert Ok("value") = set.lookup(from: table, key: "key")
let assert Ok(True) = set.member(of: table, key: "key")      // check existence
```

### Bag — multiple distinct values per key

```gleam
import shelf/bag

let assert Ok(table) =
  bag.open(name: "tags", path: "tags.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "red")
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "blue")
let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "red")    // ignored (duplicate)
let assert Ok(["red", "blue"]) = bag.lookup(from: table, key: "color")
```

### Duplicate Bag — duplicates allowed

```gleam
import shelf/duplicate_bag

let assert Ok(table) =
  duplicate_bag.open(name: "events", path: "events.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.string)
let assert Ok(Nil) = duplicate_bag.insert(into: table, key: "click", value: "btn")
let assert Ok(Nil) = duplicate_bag.insert(into: table, key: "click", value: "btn")  // kept!
let assert Ok(["btn", "btn"]) = duplicate_bag.lookup(from: table, key: "click")
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
set.insert(into: table, key: "key", value: "value")
// table is auto-closed when the callback returns
```

If the final save fails, `with_table` releases the table and returns an error.
Unsaved changes are lost. A callback error takes precedence over a close
error. Use explicit `close()` when you need to retain the handle and retry
a failed save.

## Persistence Operations

| Function | Behavior |
|----------|----------|
| `save(table)` | Atomic snapshot ETS → DETS (writes to temp file, then renames for crash safety) |
| `reload(table)` | Discard ETS, reload from DETS |
| `sync(table)` | Flush DETS write buffer to OS |
| `close(table)` | Save + close DETS + delete ETS |

**`save` vs `sync`**: `save()` snapshots ETS → DETS using a temp-file +
atomic rename (use in WriteBack to persist your changes). `sync()` drains
DETS's internal write buffer into the open DETS file (use in WriteThrough
when pending DETS writes need to be reflected in the on-disk file).

On POSIX filesystems, `save()` and `close()` preserve the DETS file's mode,
owner (uid), and group (gid). Shelf checks these values before replacing
the file. A metadata error stops the replacement and returns an error.
This does not preserve ACLs, extended attributes, or file flags; see
[file access controls](https://shelf.tylerbutler.com/advanced/persistence-operations/#file-access-controls)
before using those protections.

For the precise per-call durability guarantees and crash semantics, see
the canonical [Durability story](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story)
in the website docs.

## Type Safety

All data loaded from DETS is validated through `gleam/dynamic/decode` decoders when a table is opened. This ensures types match your expectations, even when the DETS file was written by a previous session or a different version of your application.

```gleam
import gleam/dynamic/decode

// Decoders are required when opening any table
let assert Ok(table) =
  set.open(name: "users", path: "users.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.int)
```

Within a running session, Gleam's type system guarantees correctness — decoders validate the DETS→ETS boundary on open and reload. The `save()` path is unaffected and still uses Erlang's efficient `ets:to_dets/2` bulk transfer.

> **Performance note**: The DETS → ETS load streams entries through
> `dets:foldl`, validates each entry, and inserts batches into ETS.
> Reload also keeps a scratch table and needs transfer memory. See
> [Memory cost on open and reload](https://shelf.tylerbutler.com/advanced/persistence-operations/#memory-cost-on-open-and-reload).

### Schema Migration

If you change the key or value types between application versions, `open()` returns `Error(TypeMismatch(...))` because existing DETS data fails the new decoders.

Strategies for handling schema changes:
1. **Delete and rebuild**: Delete the DETS file and repopulate from your source of truth.
2. **Run a migration**: Open the old DETS file with the *old* decoders as a temporary shelf table, transform the entries, write them to a temporary path with the *new* decoders, then atomically `rename` the new file over the old one and reopen.

The website documents the procedure at [Schema Migration](https://shelf.tylerbutler.com/advanced/schema-migration/).
Run the example in [`examples/src/shelf_examples/schema_migration.gleam`](examples/src/shelf_examples/schema_migration.gleam).

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
  Error(shelf.InvalidPath(message)) -> io.println("Invalid path: " <> message)
  Error(shelf.FileError(message)) -> io.println("File error: " <> message)
  Error(error) -> io.println("Unexpected: " <> string.inspect(error))
}
```

## Atomic Counters

```gleam
let assert Ok(table) =
  set.open(name: "stats", path: "stats.dets",
    base_directory: "/app/data",
    key: decode.string, value: decode.int)
set.insert(into: table, key: "page_views", value: 0)
set.update_counter(in: table, key: "page_views", increment: 1)   // Ok(1)
set.update_counter(in: table, key: "page_views", increment: 10)  // Ok(11)
```

## Common Operations

### Batch Insert

```gleam
let assert Ok(Nil) = set.insert_list(into: table, entries: [
  #("alice", 42),
  #("bob", 99),
  #("charlie", 7),
])
```

### Delete

```gleam
let assert Ok(Nil) = set.delete_key(from: table, key: "alice")
let assert Ok(Nil) = set.delete_all(from: table)
```

`delete_object` behaves differently depending on the table type:

- **Bag / Duplicate Bag**: Removes a specific value while keeping other values for the same key.
- **Set**: Acts as a compare-and-delete — only deletes if both the key and value match the stored entry.

```gleam
// Bag: removes only "red", keeps other values for "color"
let assert Ok(Nil) = bag.delete_object(from: table, key: "color", value: "red")

// Set: only deletes if the stored value for "key" matches "value"
let assert Ok(Nil) = set.delete_object(from: table, key: "key", value: "value")
```

### Fold, Size, and Export

```gleam
// Count entries
let assert Ok(count) = set.size(of: table)

// Fold to compute aggregates
let assert Ok(total) = set.fold(over: table, from: 0, with: fn(sum, _key, value) {
  sum + value
})

// Export all data (careful — loads entire table into memory)
let assert Ok(entries) = set.to_list(from: table)
```

## Limitations

- **DETS file size**: 2 GB maximum per table
- **No ordered set**: DETS doesn't support `ordered_set`
- **Erlang only**: Requires the BEAM runtime (no JavaScript target)
- **Single node**: DETS is local to one node (use Mnesia for distribution)
- **Table names**: Names do not need to be globally unique — shelf uses unnamed ETS tables internally. However, DETS file paths must not conflict with other open tables.
- **Exclusive paths**: Each canonical database path is reserved by one live shelf table per VM, including during save. A second open returns `NameConflict`, even in the same process. Internal DETS names are unique per-lifetime Erlang terms, not atoms derived from filenames.
- **Process ownership**: ETS tables are owned by the process that called `open()` and are created `protected`, so reads work from any process but writes/lifecycle calls are owner-only. See [Process Ownership](https://shelf.tylerbutler.com/advanced/limitations/#process-ownership).
- **Loading large tables**: Open and reload validate DETS entries in batches. Reload also needs a scratch ETS table and transfer memory. Details and limits: [Memory cost on open and reload](https://shelf.tylerbutler.com/advanced/persistence-operations/#memory-cost-on-open-and-reload).

## Security

All DETS file paths are resolved against the provided `base_directory`, including symbolic links in existing directories and at the filename itself. Paths that escape the resolved base directory are rejected with `InvalidPath`, as are null bytes, link loops, and filesystem resolution errors. In-base aliases resolve to the same canonical path and therefore share one exclusive reservation. Unicode directories and filenames are preserved, and `/` is a valid base directory. Missing components can pass validation, but opening still requires the parent directory to exist.

Use a trusted base directory and trusted contents. This check does not protect against concurrent external replacement of directories or symbolic links between validation and I/O, and does not detect hard-link aliases.

Snapshots use an exclusively created private sibling directory on the same filesystem, then rename its DETS file over the database. Save cleans up only its own temporary file and directory; an unrelated `<database>.tmp` is never used. The guardian acquires and tracks that location, cleaning it up after temporary DETS shutdown if the owner exits during save. A VM crash can still leave a private snapshot directory behind.

## Process Ownership

ETS tables are owned by the process that calls `open()`, and shelf creates them as `protected`. The website documents this in detail at [Process Ownership](https://shelf.tylerbutler.com/advanced/limitations/#process-ownership) — including the read/write split, `Error(NotOwner)` semantics, and recommended supervision patterns.

In short: reads work from any process; writes and lifecycle calls (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`, `close`) must come from the owner.

If the owning process crashes, the ETS table is deleted and unsaved data is lost. The DETS file is preserved — the next `open()` call reloads it.
Use WriteThrough to send each change to DETS, but account for its buffering and
the [durability limits](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story).

### Write Safety

Within the owner process, all shelf operations are individual ETS/DETS calls — there is no built-in transaction support. If you need atomic multi-key updates, coordinate through a single process (e.g., a GenServer).

For set tables, concurrent reads from other processes while the owner writes to *different* keys are safe. Writes to the *same* key result in last-writer-wins (no corruption, but potential data loss from the reader's perspective). Bag and duplicate bag tables follow the same model.

## See Also

- **[bravo](https://hex.pm/packages/bravo)** — Use ETS directly when you don't need disk persistence
- **[slate](https://hex.pm/packages/slate)** — Use DETS directly when you don't need in-memory speed
- **[Erlang ETS docs](https://www.erlang.org/doc/apps/stdlib/ets.html)** — Underlying ETS documentation
- **[Erlang DETS docs](https://www.erlang.org/doc/apps/stdlib/dets.html)** — Underlying DETS documentation

## Development

Install the pinned tools with `mise install`, then use `just --list` to
find the build and test commands. See [Contributing](CONTRIBUTING.md) for
development setup, dependency audits, SBOMs, changelogs, and releases.
