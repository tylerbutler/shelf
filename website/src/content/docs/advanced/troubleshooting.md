---
title: Troubleshooting
description: Common shelf errors and operational symptoms, with pointers to the relevant docs and source.
---

This page collects the questions that come up most often when integrating
shelf. Each entry references the relevant error variant or the source of
the limitation.

## I'm getting `NameConflict` on `open()` — why?

`Error(NameConflict)` is returned when you try to open a DETS file that is
already open by another live shelf table in the same VM. shelf maps
file paths to a bounded pool of internal DETS atom names; two opens at
the same path collide intentionally — DETS itself does not allow
concurrent owners of one file.

What to check:

- Are you calling `open()` twice at the same path without closing in
  between? Use `with_table` for short-lived tables.
- Did a previous owner crash? The `NameConflict` should normally clear
  once the guardian process notices the owner exit; if it persists,
  inspect whether you have a stale handle holding the table.
- Are two `set.open` / `bag.open` / `duplicate_bag.open` calls pointing
  at the same path with different table types? Pick one type per file.

## I'm getting `TypeMismatch` after a deploy — what now?

`Error(TypeMismatch(decode_errors))` means the decoders you passed to
`open()` rejected at least one entry already on disk. This usually
happens when the key or value type changed between application versions.

You have three realistic options:

1. **Roll back the decoder change** — confirm the data really should
   match the new shape.
2. **Delete the DETS file** — if the data is regenerable (a cache, an
   index), this is the simplest path.
3. **Run a one-time migration** that opens the old DETS file with the
   old decoders, transforms the entries, and writes them back. See
   [Schema Migration](/advanced/schema-migration/) for the full
   procedure.

The `decode_errors` value carried by `TypeMismatch` is the standard
`gleam/dynamic/decode` error list — log it to see exactly which fields
failed.

## My ETS data disappeared after a crash — is the DETS file safe?

Yes. ETS is in-process memory, so when the owning process exits the ETS
table is deleted. The DETS file on disk is a separate artifact and is
left intact. The next `open()` call streams it back into a fresh ETS
table.

To minimise data loss across crashes:

- In **WriteBack** mode, save() is the explicit persistence call —
  schedule it (timer, after every N writes, at clean shutdown).
- In **WriteThrough** mode, every write reaches DETS immediately, so the
  on-disk file is always at most a few µs behind the in-memory table.

See the [Durability story](/advanced/persistence-operations/#durability-story)
for exactly which calls advance data past which layer.

## Can I share a table across processes?

Reads, yes. Writes, no — at least not directly.

shelf creates ETS tables as `protected`, so any process in the same node
can call read operations (`lookup`, `member`, `size`, `to_list`, `fold`)
on a table handle the owner gives them. Write and lifecycle operations
(`insert`, `delete_*`, `update_counter`, `save`, `reload`, `sync`,
`close`) return `Error(NotOwner)` from any process that isn't the owner.

The standard pattern is to run a single supervised actor that owns the
table and forwards mutation requests; readers consume the handle directly
without going through the actor. See
[Process Ownership](/advanced/limitations/#process-ownership).

## Why is my first `open()` slow on a large table?

The DETS → ETS load streams every entry through your decoders and inserts
into ETS in batches. Both decode work and insert work scale linearly with
the number of entries on disk, so opening a table with millions of
entries can take noticeable wall time even though peak extra memory is
bounded to ~1× the table size.

This is by design — see
[Memory cost on open and reload](/advanced/persistence-operations/#memory-cost-on-open-and-reload).

Mitigations:

- Open large tables once at process start, not on demand.
- Keep tables narrow: prefer multiple smaller tables over one giant one
  if your access patterns allow.

## What does `Error(InvalidPath)` mean?

shelf validates every DETS file path against the `base_directory` you
pass to `open()` / `config()` to prevent path-traversal. Paths containing
`..` segments, absolute paths that escape the base, or platform-unsafe
characters are rejected up front with `Error(InvalidPath(reason))`. Pick
a base directory you control and keep `path` relative to it.

## What is `FileSizeLimitExceeded`?

DETS files are capped at **2 GB** per table — this is a DETS limit, not a
shelf one. If you hit it, partition data across multiple tables or move
to Mnesia / a real database.
