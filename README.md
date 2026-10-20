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

pub fn main() -> Nil {
  // Open a persistent set — loads existing data from disk
  // Decoders validate data loaded from the DETS file
  let assert Ok(table) =
    set.open(name: "users", path: "data/users.dets",
      base_directory: "/app/data",
      key: decode.string, value: decode.int)

  // Fast writes (to ETS)
  let assert Ok(Nil) = set.insert(into: table, key: "alice", value: 42)
  let assert Ok(Nil) = set.insert(into: table, key: "bob", value: 99)

  // Fast reads (from ETS)
  let assert Ok(42) = set.lookup(from: table, key: "alice")

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

Each write updates DETS before it returns. DETS can buffer writes in
memory; call `sync()` after critical writes. See the
[durability guarantees](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story)
for file and directory synchronization limits.

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
| `sync(table)` | Flush DETS writes and synchronize dirty file data |
| `close(table)` | Save + close DETS + delete ETS |

**`save` vs `sync`**: `save()` snapshots ETS → DETS using a temp-file +
atomic rename (use in WriteBack to persist your changes). `sync()` flushes
DETS writes and calls `file:sync/1` when saving a dirty disk-backed table.
DETS can skip file synchronization for an already-saved table. Neither
operation synchronizes directory entries after file creation or rename.

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

- **Bag / Duplicate Bag**: Removes all occurrences of a specific value while keeping other values for the same key.
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
- **Process ownership**: ETS tables are owned by the process that called `open()` and are created `protected`, so reads work from any process but writes/lifecycle calls are owner-only. See [Process Ownership](https://shelf.tylerbutler.com/advanced/limitations/#process-ownership).
- **Loading large tables**: Open and reload validate DETS entries in batches. Reload also needs a scratch ETS table and transfer memory. Details and limits: [Memory cost on open and reload](https://shelf.tylerbutler.com/advanced/persistence-operations/#memory-cost-on-open-and-reload).

## Security

All DETS file paths are validated against the provided `base_directory` to prevent path traversal attacks. Paths containing `..` segments or other unsafe patterns that would escape the base directory are rejected with an `InvalidPath` error.

## Process Ownership

ETS tables are owned by the process that calls `open()`, and shelf creates them as `protected`. The website documents this in detail at [Process Ownership](https://shelf.tylerbutler.com/advanced/limitations/#process-ownership) — including the read/write split, `Error(NotOwner)` semantics, and recommended supervision patterns.

In short: reads work from any process; writes and lifecycle calls (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`, `close`) must come from the owner.

If the owning process crashes, the ETS table is deleted and unsaved data is lost. The DETS file is preserved — the next `open()` call reloads it.
- Use WriteThrough to send each write to DETS, and `sync()` after critical
  writes. Neither mode guarantees full durability across OS crash or power loss.

### Write Safety

Within the owner process, all shelf operations are individual ETS/DETS calls — there is no built-in transaction support. If you need atomic multi-key updates, coordinate through a single process (e.g., a GenServer).

For set tables, concurrent reads from other processes while the owner writes to *different* keys are safe. Writes to the *same* key result in last-writer-wins (no corruption, but potential data loss from the reader's perspective). Bag and duplicate bag tables follow the same model.

## Development and Releases

Use [mise](https://mise.jdx.dev/) to install the pinned tools with `mise install`.
Keep using Just for builds, tests, and other project tasks: run `just --list`
to see the commands.

Use [trellis](https://trellis.tylerbutler.com/docs/changelog/) for changelogs
and releases. Add an entry for a user-facing change:

```sh
just change Fixed "Fix the user-facing problem"
just changelog-preview
```

Trellis stores TOML fragments in `.changes/unreleased/` and released sections
in `.changes/shelf/`. Do not edit the generated `CHANGELOG.md`.
The `[tools.trellis.changelog]` table in `gleam.toml` defines the change kinds
and version bumps. Development-only changes need no entry; the PR check
warns about missing entries and fails on invalid fragments.

On a push to `main`, trellis creates or updates a release PR on
`release/next`. Merging that PR creates the `v<version>` tag and GitHub
release. The tag starts the Hex publish workflow. The workflows use the
existing `RELEASE_APP_ID`, `RELEASE_APP_PRIVATE_KEY`, and `HEXPM_API_KEY`
secrets. The examples remain workspace members but do not release.

For a manual release, `just changelog` applies the version bump, consumes
the pending fragments, and updates the changelog and internal lockfile versions.
Use `just changelog-preview` first; it does not change files.

## See Also

- **[bravo](https://hex.pm/packages/bravo)** — Use ETS directly when you don't need disk persistence
- **[slate](https://hex.pm/packages/slate)** — Use DETS directly when you don't need in-memory speed
- **[Erlang ETS docs](https://www.erlang.org/doc/apps/stdlib/ets.html)** — Underlying ETS documentation
- **[Erlang DETS docs](https://www.erlang.org/doc/apps/stdlib/dets.html)** — Underlying DETS documentation

## Development

Use Gleam 1.14 or later.

```sh
gleam test    # Run the test suite
gleam build   # Build the package
gleam format  # Format source code
```

### Shared agent setup

Install [APM](https://github.com/microsoft/apm), then run `apm install` to deploy
skills and agents for Claude Code and GitHub Copilot.
Run the command again after changes to `.apm/` or `apm.yml`.

Edit local skills in `.apm/skills/` and local agent definitions in
`.apm/agents/`. APM generates the skill copies in `.claude/skills/` and
`.agents/skills/`, and agent definitions in `.claude/agents/` and
`.github/agents/`. Do not edit these generated copies; commit them with the
source changes. Local agents inherit the tools available in each platform.

Dependency skills and agents remain managed by `apm.yml` and `apm.lock.yaml`;
do not copy them into `.apm/`.

Further documentation can be found at <https://hexdocs.pm/shelf>.
