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

`save()` and `close()` require a supported local macOS filesystem and
metadata tools. They return `FileError` on Linux and other platforms.
Read [file metadata](#file-metadata) before running the example.

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

Every table follows the same life: you open it, your decoders check the
saved data, you read and write through ETS, and you save the changes to
DETS. The sections below follow that order.

## Open: Choose a Table Type

Each table type has its own module and opaque handle: `PersistentSet(k, v)`,
`PersistentBag(k, v)`, or `PersistentDuplicateBag(k, v)`. They differ in
what happens when you insert a second value for the same key.

### Set — unique keys

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

Sets also support atomic integer counters with `update_counter`.

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

For batch inserts, deletes, folds, counters, and a full comparison of the
operations each type supports, see
[Common Patterns](https://shelf.tylerbutler.com/guides/common-patterns/).

## Load: Decoders Check Saved Data

A DETS file can outlive the code that wrote it. When you open a table,
Shelf passes every saved key and value through your `gleam/dynamic/decode`
decoders before it loads them into ETS. If a value does not match the types
your code expects now, `open()` returns `Error(TypeMismatch(...))` instead of
a table with bad data in it. `reload()` runs the same checks.

After loading, Gleam's type system keeps the table correct, so `save()`
needs no decoders and uses Erlang's bulk `ets:to_dets/2` transfer.

Shelf always writes records as `#(key, value)`. A DETS file written by other
Erlang or Elixir code can hold larger records, so Shelf rejects any record
with extra fields with `TypeMismatch` before it runs your decoders. A failed
open preserves the stored records, and a failed reload leaves the live ETS
contents unchanged.

> **Performance note**: The load streams entries through `dets:foldl`,
> validates each entry, and inserts batches into ETS. Reload also keeps a
> scratch table and needs transfer memory. See
> [Memory cost on open and reload](https://shelf.tylerbutler.com/advanced/persistence-operations/#memory-cost-on-open-and-reload).

### Schema Migration

When you change the key or value types between application versions, the
saved data fails the new decoders. You have two choices:

1. **Delete and rebuild**: Delete the DETS file and repopulate it from your source of truth.
2. **Run a migration**: Open the old file with the *old* decoders as a temporary shelf table, transform the entries, write them to a temporary path with the *new* decoders, then atomically `rename` the new file over the old one and reopen.

For a file with larger records from other Erlang or Elixir code, first use
native DETS tools to rewrite each record as `#(key, value)` at a new path.
Keep every required field inside the key or value, because Shelf does not
discard extra fields. Keep the original file until you verify the result.

The website documents the procedure at [Schema Migration](https://shelf.tylerbutler.com/advanced/schema-migration/).
Run the example in [`examples/src/shelf_examples/schema_migration.gleam`](examples/src/shelf_examples/schema_migration.gleam).

## Write: Choose When Changes Reach DETS

Reads always use ETS. The write mode decides when a change also reaches DETS:

| Write Mode | Behavior | Use Case |
|-----------|----------|----------|
| `WriteBack` (default) | ETS only; call `save()` to persist | High-throughput, periodic snapshots |
| `WriteThrough` | DETS first, then ETS on every write | Persist each change without a full snapshot |

### WriteBack (default)

Writes go to ETS only, and you decide when to persist them:

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

The price of that speed is that a crash loses every write since the last
`save()`. Choose a save schedule that matches how much you can lose: a
periodic timer, every N writes, or clean shutdown.

### WriteThrough

Every write goes to DETS before ETS. If the DETS write fails, ETS does not
change, so the two never disagree:

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

DETS can still hold these writes in its own memory buffer. Call `sync()` to
flush that buffer to the file. See [Durability](#durability) for what each
mode does and does not protect against.

## Save and Close

Four calls move data between ETS and DETS:

| Function | Behavior |
|----------|----------|
| `save(table)` | Atomic snapshot ETS → DETS (writes to temp file, then renames for crash safety) |
| `reload(table)` | Discard ETS, reload from DETS |
| `sync(table)` | Flush DETS write buffer to OS |
| `close(table)` | Save + close DETS + delete ETS |

`save()` and `sync()` solve different problems. In WriteBack, `save()`
copies ETS into a temporary DETS file and renames it over the database, so
the file holds either the old snapshot or the new one. In WriteThrough, the
changes are already in DETS, and `sync()` drains DETS's buffer into the open
file.

Use `with_table` to make sure a table is always closed:

```gleam
use table <- set.with_table("cache", "data/cache.dets",
  base_directory: "/app/data",
  key: decode.string, value: decode.string)
set.insert(into: table, key: "key", value: "value")
// table is auto-closed when the callback returns
```

If the final save fails, `with_table` releases the table and returns an
error, and the unsaved changes are lost. A callback error takes precedence
over a close error. When you need to keep the handle and retry a failed
save, call `close()` yourself.

### File metadata

Because `save()` replaces the file, it must carry the file's access controls
across. `save()` and `close()` check the mode, owner (uid), group (gid),
ACLs, extended attributes, and file flags before the replacement. Shelf
supports these operations on macOS only and uses platform tools for the
controls that Erlang cannot read. On Linux and other platforms, or when
the tools cannot preserve and verify the protections, Shelf keeps the
original file and returns `FileError`. This includes the final save in
`with_table()`. Correct the cause and retry with the same table handle
when you use manual `close()`. See
[file access controls](https://shelf.tylerbutler.com/advanced/persistence-operations/#file-access-controls)
for supported platforms, required tools, and limits.

### Leftovers after a VM crash

If the VM crashes during a save, it can leave a `.shelf-save-<pid>-<counter>`
directory beside the database. Shelf does not scan for these directories,
because another VM can still be writing them. After you confirm abandonment
and stop all writers, use `shelf.cleanup_snapshot(directory:, base_directory:)`
to remove one exact directory, including DETS sidecars and sorter files.
The function checks all entries before deletion and rejects links, nested
directories, and unknown files. Follow the
[manual cleanup procedure](https://shelf.tylerbutler.com/advanced/persistence-operations/#manual-cleanup-after-a-vm-crash),
and leave any directory whose owner you cannot confirm.

### Durability

Each failure removes one more layer of protection. If the owner process
exits, its ETS table goes with it: WriteBack loses unsaved changes, and
WriteThrough changes stay in DETS. If the VM crashes, writes still in the
DETS buffer can also be lost. If the OS crashes or the power fails, even a
synced file can lose data, because DETS does not expose `fsync(2)`. If your
application must survive that last case, choose another store. The
[Durability story](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story)
gives the exact guarantee of each call.

## Process Ownership

The process that calls `open()` owns the table. Shelf creates the ETS table
as `protected`, so any process can read it, but only the owner can write or
manage it (`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`,
`close`). Calls from other processes return `Error(NotOwner)`. For a
long-running application, open the table in a supervised process and send
it your write requests.

The owner's life decides the table's life. If the owner crashes, ETS deletes
the table and unsaved data is lost, but the DETS file stays, and the next
`open()` loads it again.

Because only the owner writes, writes never race each other. Readers in other
processes, however, see each write as soon as ETS applies it, so they can see
a multi-key update half-done. Shelf has no transactions. If readers must
never see a partial update, send their reads through the owner as well.

The website covers the details at
[Process Ownership](https://shelf.tylerbutler.com/advanced/limitations/#process-ownership).

## Error Handling

All operations return `Result(value, ShelfError)` for storage failures.
Exceptions raised by a `fold` callback propagate to the caller; they are not
converted to `ShelfError`.

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

[Troubleshooting](https://shelf.tylerbutler.com/advanced/troubleshooting/)
lists every error variant and what to do about the common ones.

## Limitations

- **DETS file size**: 2 GB maximum per table
- **No ordered set**: DETS doesn't support `ordered_set`
- **Erlang only**: Requires the BEAM runtime (no JavaScript target)
- **Single node**: DETS is local to one node (use Mnesia for distribution)
- **One table per file**: Table names are only labels and need not be unique, but each database file can have one live shelf table per VM, including during save. A second open through the same path, a hard link, or a filesystem-supported case or Unicode alias returns `NameConflict`, even in the same process.
- **Filesystem identity**: Opening requires reliable device and nonzero inode values. If the filesystem cannot provide them, shelf returns `FileError` without loading entries or returning a table handle.
- **Loading large tables**: Open and reload validate DETS entries in batches. Reload also needs a scratch ETS table and transfer memory. Details and limits: [Memory cost on open and reload](https://shelf.tylerbutler.com/advanced/persistence-operations/#memory-cost-on-open-and-reload).

## Security

Shelf trusts the base directory you give it, and it stops paths from leaving
that directory. It resolves every DETS path against `base_directory`,
including symbolic links in existing directories and at the filename. A path
that escapes the resolved base returns `InvalidPath`, and so do null bytes,
link loops, and resolution errors. Aliases inside the base resolve to the
same canonical path and share one reservation. Unicode names are preserved,
and `/` is a valid base directory. Missing components can pass validation,
but opening still requires the parent directory to exist.

These checks happen once, before I/O, and inside one VM. They do not stop
another process from replacing a directory or symbolic link between
validation and I/O, they do not lock files against other VMs, and they do
not check whether a hard link points outside the base. Use a base directory
and contents that you control.

Save replaces the file at the original path. Other hard links keep pointing
to the old file, so after a successful save they name a distinct file that
can open as a separate table.

A save writes its snapshot in a private sibling directory, which it creates
exclusively on the same filesystem, then renames the DETS file over the
database. It never uses an unrelated `<database>.tmp` file, and it cleans up
only its own files. If the owner exits during save, the guardian cleans up
after temporary DETS shutdown. Only a VM crash can leave the directory behind
(see [Leftovers after a VM crash](#leftovers-after-a-vm-crash)).

## See Also

- **[bravo](https://hex.pm/packages/bravo)** — Use ETS directly when you don't need disk persistence
- **[slate](https://hex.pm/packages/slate)** — Use DETS directly when you don't need in-memory speed
- **[Erlang ETS docs](https://www.erlang.org/doc/apps/stdlib/ets.html)** — Underlying ETS documentation
- **[Erlang DETS docs](https://www.erlang.org/doc/apps/stdlib/dets.html)** — Underlying DETS documentation

## Development

Install the pinned tools with `mise install`, then use `just --list` to
find the build and test commands. See [Contributing](CONTRIBUTING.md) for
development setup, dependency audits, SBOMs, changelogs, and releases.
