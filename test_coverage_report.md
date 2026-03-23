# Test Coverage & Quality Report

## Summary
The test suite provides good coverage of the "happy path" for basic CRUD operations across all table types (`set`, `bag`, `duplicate_bag`). `TypeMismatch` handling is well-tested. However, there are significant gaps in testing concurrent access, crash recovery, and error conditions. The `sync` function is completely untested.

## 1. Critical Gaps (Must Fix)

### Missing Function Coverage
*   **`sync/1`**: This function is present in all modules (`set`, `bag`, `duplicate_bag`) but is **never called** in any test. Its behavior (flushing DETS buffers) is unverified.
*   **`update_counter/3` Error Cases**:
    *   Calling on a **missing key** (should return `Error(NotFound)`).
    *   Calling on a **non-integer value** (should return `Error(TypeMismatch)` or similar).
    *   Currently only the success path is tested in `set_test.gleam`.

### Concurrency & Reliability
*   **Concurrent Access**: No tests spawn multiple processes to read/write to the same table simultaneously. This is critical for a shared ETS table to ensure no race conditions in the Gleam wrapper logic.
*   **Crash Recovery**: No tests simulate an OS process kill (`SIGKILL`) to verify:
    *   `WriteBack` mode loses unsaved data.
    *   `WriteThrough` mode preserves data.
    *   `ets:to_dets` atomicity issues (DETS file corruption/truncation) mentioned in docs are not reproduced or guarded against.

## 2. Improvements (Should Fix)

### WriteThrough Coverage
`write_through_test.gleam` is `set`-heavy. `bag` and `duplicate_bag` have spotty coverage:
*   **`bag`**: Missing tests for `insert_list`, `delete_object`, `delete_all` in WriteThrough mode.
*   **`duplicate_bag`**: Missing tests for `insert_list`, `delete_key`, `delete_all` in WriteThrough mode.
*   **`reload`**: Not tested in WriteThrough mode (should be a safe no-op or sync).

### Error Handling & Edge Cases
*   **`with_table` Panic**: The code wraps the callback in `rescue`, but no test intentionally panics in the callback to verify the table is closed and the error is returned.
*   **Empty Collections**:
    *   `insert_list` with an empty list `[]`.
    *   `delete_all` on an already empty table.
*   **File Errors**: No tests for:
    *   Opening a table in a read-only directory (`EACCES`).
    *   Corrupt DETS files (garbage bytes in header).

## 3. Nits (Good to Have)

*   **Unicode Stress**: While `string` is used, explicit tests with Emoji/Unicode keys would ensure the Erlang FFI handles binary conversion correctly in all cases.
*   **Large Data**: No tests approach the DETS 2GB limit or test performance with >50k items (where `validate_and_load` might spike memory).
*   **Refactoring**: `delete_object` in `set.gleam` is an alias for `delete_key` but isn't explicitly tested in `set_test.gleam` (only in `write_through_test.gleam`).

## Action Items

1.  Create `test/concurrency_test.gleam` to spawn processes and hammer a shared table.
2.  Add a `sync` test case to `persistence_test.gleam`.
3.  Add error case tests to `set_test.gleam` for `update_counter`.
4.  Expand `write_through_test.gleam` to cover all operations for all table types.
5.  Add a `panic` test case to `with_table` in `shelf_test.gleam`.
