# Shelf Comprehensive Code Review — Unified Report

Fleet review conducted 2026-03-23 by 6 parallel expert agents:
Erlang/OTP, Gleam API, Testing, Security, Documentation, Architecture.

Where multiple agents flagged the same issue, the count is noted as **[N agents]**.

---

## 🔴 CRITICAL

### 1. `dets:foldl/3` error return silently passed to Gleam as a list [1 agent]
**Source**: Erlang agent · `src/shelf_ffi.erl:51-57`

`dets:foldl/3` can return `{error, Reason}` as a *normal return value* (not an exception). The current code wraps it in `{ok, Result}`, so Gleam receives `Ok({error, Reason})` and tries to use the error tuple as a `List(Dynamic)`, causing a downstream crash.

**Fix**: Check the return value:
```erlang
case dets:foldl(...) of
    {error, Reason} -> {error, translate_error(Reason)};
    Result when is_list(Result) -> {ok, Result}
end
```

### 2. Resource leak in `open_config` when `dets_to_list` fails [1 agent]
**Source**: Erlang agent · `src/shelf/set.gleam:71` (same in bag:65, duplicate_bag:65)

After `open_no_load` succeeds, if `dets_to_list` returns an error, `result.try` short-circuits and returns the error. `cleanup(ets, dets)` is never called — it only runs when `validate_and_load` fails. Both ETS table and DETS handle leak.

**Fix**: Wrap the entire post-open logic so any failure triggers cleanup.

### 3. Resource leak in `close/2` — no best-effort cleanup [2 agents]
**Source**: Erlang + Security agents · `src/shelf_ffi.erl:74-85`

If `ets:to_dets/2` throws, the catch fires but `dets:close` and `ets:delete` never execute. Both handles leak in a half-closed, unrecoverable state.

**Fix**: Best-effort cleanup pattern — attempt each step independently:
```erlang
SaveResult = (catch ets:to_dets(Ets, Dets)),
_ = (catch dets:close(Dets)),
_ = (catch ets:delete(Ets)),
```

### 4. `with_table` doesn't catch panics — cleanup guarantee is broken [4 agents]
**Source**: Security, Gleam API, Architecture, Erlang agents · `set.gleam:139`, `bag.gleam:127`, `duplicate_bag.gleam:127`

If the callback contains a `let assert` that fails or any Erlang exception, `close(table)` never runs. Additionally, when close *does* run, its error is silently discarded (`let _ = close(table)`).

**Fix**: Wrap callback in `rescue`/`try-catch` so close runs unconditionally. When callback succeeds but close fails, propagate the close error.

### 5. `ets:info(Ets, size)` returns `undefined` for deleted tables [1 agent]
**Source**: Erlang agent · `src/shelf_ffi.erl:178-182`

`ets:info(Tab, size)` returns the atom `undefined` (not an exception) for non-existent tables. The FFI returns `{ok, undefined}`, which Gleam trusts as `Ok(Int)` — a type violation that can cause silent data corruption.

**Fix**: Check for `undefined` and return `{error, table_closed}`.

### 6. `internal.gleam` pub functions allow bypassing type safety [3 agents]
**Source**: Gleam API, Security, Architecture agents · `src/shelf/internal.gleam:15-150`

All internal functions are `pub`, and `EtsRef`/`DetsRef` are obtainable via `open_no_load`. External users can bypass decoder validation entirely. Additionally, ETS tables are created as `public`, allowing any VM process to write arbitrary data directly.

**Fix**: Add `@internal` to all pub functions (Gleam >= 1.7.0). Change ETS access from `public` to `protected`.

### 7. `tag_index` example crashes at runtime [1 agent]
**Source**: Docs agent · `examples/src/tag_index.gleam:66`

After `bag.delete_key`, the next line does `let assert Ok(erlang_articles) = bag.lookup(...)`. Since the key was deleted, lookup returns `Error(NotFound)` and the assert panics. Verified by running the example.

### 8. README `insert_new` example will crash [1 agent]
**Source**: Docs agent · `README.md:142`

`let assert Ok(Nil) = set.insert_new(t, "key", "value2")` — the comment says the result is `Error(KeyAlreadyPresent)`, but the code asserts `Ok(Nil)`.

---

## 🟡 IMPROVEMENT

### 9. WriteThrough mode is O(n) per write — full table snapshot [2 agents]
**Source**: Erlang + Architecture agents · `src/shelf/internal.gleam:78-87`

Every write in WriteThrough triggers `ets:to_dets/2`, which replaces ALL DETS contents. For 100K entries, a single insert copies all 100K+ entries to disk. The FFI already has unused `_Dets` params positioned for per-operation mirroring.

**Fix**: Use targeted `dets:insert/2`, `dets:delete/2`, etc. for WriteThrough. Reserve `ets:to_dets` for `save()` and `close()`.

### 10. Atom exhaustion via `binary_to_atom` with user-provided strings [3 agents]
**Source**: Erlang, Security, Architecture agents · `src/shelf_ffi.erl:19-20`

Both table names and file paths are converted to permanent atoms. ~1M unique names crashes the entire VM. Not documented.

**Fix (minimum)**: Document prominently. **Fix (better)**: Drop `named_table`, use ETS tid references directly. Use `binary_to_existing_atom` for TypeBin (line 21).

### 11. `FileSizeLimitExceeded` error variant is unreachable [2 agents]
**Source**: Erlang + Architecture agents · `src/shelf.gleam:66`, `src/shelf_ffi.erl:217-229`

Defined in `ShelfError` but `translate_error` has no clause that produces it. DETS 2GB errors fall through to generic `FileError`.

**Fix**: Add `translate_error({file_error, _, enospc}) -> file_size_limit_exceeded`.

### 12. `TypeMismatch` provides no diagnostic detail [1 agent]
**Source**: Gleam API agent · `src/shelf.gleam:67-71`

When strict decoding fails on one entry out of thousands, the user gets zero information about which entry failed or what the error was.

**Fix**: Include decode error details: `TypeMismatch(List(decode.DecodeError))`.

### 13. bag/duplicate_bag test coverage is critically low [1 agent]
**Source**: Testing agent

| Module | Coverage |
|--------|----------|
| set | 83% (15/18 functions) |
| bag | 35% (6/17 functions) |
| duplicate_bag | 24% (4/17 functions) |

Untested: `with_table`, `member`, `to_list`, `fold`, `size`, `insert_list`, `delete_all`, `save`, `reload`, `sync` for bag/duplicate_bag. WriteThrough and persistence tests only cover set.

### 14. Error paths are untested across all table types [1 agent]
**Source**: Testing agent

- `update_counter` on non-existent key (→ `NotFound`)
- `update_counter` on non-integer value (→ `ErlangError`)
- Operations on a closed table (→ `TableClosed`)
- `sync` operation (never tested)
- `with_table` when callback returns error

### 15. `ets:to_dets` data loss window on crash [1 agent]
**Source**: Security agent · `src/shelf_ffi.erl:77,188`

`ets:to_dets/2` deletes all DETS contents *then* inserts from ETS. A SIGKILL between delete and insert leaves DETS empty. `{repair, true}` fixes structural corruption but cannot recover deleted data.

**Fix**: Document in `save()` docstring. Consider save-to-temp-then-rename for atomic file replacement.

### 16. No `with_table_config` variant [1 agent]
**Source**: Gleam API agent · `src/shelf/set.gleam:125-141`

No way to use `with_table` with custom config (e.g., WriteThrough). Must manually open/close.

### 17. `Lenient` mode drops entries silently [1 agent]
**Source**: Gleam API agent · `src/shelf/internal.gleam:55-58`

The count of skipped entries is discarded. Users may not realize they're losing data.

### 18. 50K entry scaling caveat missing from README [1 agent]
**Source**: Docs agent

Module docs warn about this but the README Limitations section omits it.

### 19. ~530 lines of duplicated code across table modules [2 agents]
**Source**: Architecture + Gleam API agents

bag.gleam and duplicate_bag.gleam are 96% identical. Practical mitigation: extract shared `open_impl` into internal.gleam, or use code generation.

### 20. TOCTOU race in `update_counter` error diagnosis [1 agent]
**Source**: Erlang agent · `src/shelf_ffi.erl:205-214`

After `update_counter` throws `badarg`, `ets:lookup` is used to determine the cause. Another process (table is `public`) could change state between the two calls.

### 21. No concurrency or process supervision docs [1 agent]
**Source**: Docs agent

No mention of concurrent access safety or how to supervise table-owning processes.

### 22. No schema migration guidance [1 agent]
**Source**: Docs agent

If a user changes their value type between releases, `open()` returns `TypeMismatch` with no documented escape hatch.

---

## 🔵 NIT

### 23. Unused `_Dets` parameter in FFI insert functions [3 agents]
`src/shelf_ffi.erl:89,96,103` — vestige of earlier design, will be needed for WriteThrough fix (#9).

### 24. Test helper duplication across all test files [2 agents]
Every test file duplicates `cleanup`/`delete_file`. Extract to shared `test/test_helpers.gleam`.

### 25. `translate_error(badarg) → table_closed` is imprecise [1 agent]
`badarg` from ETS can mean many things; mapping it unconditionally to `table_closed` can mislead.

### 26. Inconsistent doc comments for `size` [1 agent]
Set says "entries", bag/duplicate_bag say "objects stored".

### 27. `bag.gleam`/`duplicate_bag.gleam` module examples show specific lookup order [1 agent]
ETS bag lookup order is unspecified, but examples show exact ordered results.

### 28. `Config` type is fully public (not opaque) [1 agent]
Users can bypass the builder. Consider making it opaque if validation is added later.

### 29. CLAUDE.md and justfile disagree on format scope [1 agent]
CLAUDE.md: `gleam format src test` vs justfile: `gleam format src test examples/src`.

### 30. `delete_object` on set is semantically redundant [1 agent]
Doc correctly notes it's equivalent to `delete_key`, but the value param creates a minor footgun.

---

## Cross-Agent Agreement Matrix

Issues flagged by 3+ agents (highest confidence):

| Finding | Erlang | Gleam | Testing | Security | Docs | Arch |
|---------|--------|-------|---------|----------|------|------|
| `with_table` cleanup broken | ✅ | ✅ | | ✅ | | ✅ |
| `internal.gleam` pub exposure | | ✅ | | ✅ | | ✅ |
| Atom exhaustion risk | ✅ | | | ✅ | | ✅ |
| Unused `_Dets` param | ✅ | ✅ | | | | ✅ |

---

## Recommended Priority Order

**Ship-blocking (fix before 1.0)**:
1. #1 — `dets_to_list` unchecked error (silent crash)
2. #2 — Resource leak on `dets_to_list` failure
3. #3 — Resource leak in `close/2`
4. #4 — `with_table` panic safety + close error propagation
5. #5 — `size` returns `undefined` as Int
6. #6 — `@internal` annotations + `protected` ETS
7. #7, #8 — Fix crashing examples/docs

**High value improvements**:
8. #9 — WriteThrough O(1) per write
9. #10 — Document atom exhaustion risk
10. #13, #14 — Fill test coverage gaps
11. #11 — Wire up `FileSizeLimitExceeded`
12. #12 — `TypeMismatch` with decode error detail

**Polish**:
13. Everything else, starting with #15 (data loss docs) and #18 (README scaling caveat)
