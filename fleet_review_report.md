# Fleet Review Report

## Executive Summary
The `shelf` library is well-architected, idiomatic, and generally robust. However, **critical vulnerabilities** related to atom exhaustion and memory usage were identified, along with a significant documentation error in `set.delete_object`. Addressing these issues is essential for a stable v1.0 release.

## 🔴 Critical Findings (Immediate Action Required)

### 1. Atom Exhaustion Vulnerability (DoS)
*   **Source**: Agents 1 (Erlang), 4 (Security)
*   **Location**: `src/shelf_ffi.erl:20-23`
*   **Issue**: The library calls `binary_to_atom/2` on user-provided table names and DETS file paths. Since atoms are not garbage collected (limit ~1M), an attacker or dynamic usage pattern (e.g., one table per user) will crash the entire Erlang VM.
*   **Remediation**:
    *   Stop using `named_table` for ETS (use the returned `tid` reference instead).
    *   For DETS, use `binary_to_existing_atom` or maintain a fixed pool of atoms if possible, or strictly document this limitation.

### 2. Memory Spike on Load
*   **Source**: Agents 1 (Erlang), 6 (Architecture)
*   **Location**: `shelf_ffi:dets_to_list/1` -> `internal:validate_and_load/4`
*   **Issue**: Opening a table materializes the entire DETS file content into memory **three times**:
    1.  Raw Erlang list from `dets:to_list`.
    2.  Decoded Gleam list.
    3.  Final ETS table insertion.
*   **Impact**: Opening a 500MB dataset requires ~1.5GB+ peak RAM, potentially causing OOM kills.
*   **Remediation**: Implement a streaming/chunked loader using `dets:foldl` to validate and insert in batches.

### 3. Documentation Error: `set.delete_object`
*   **Source**: Agent 2 (Gleam)
*   **Location**: `src/shelf/set.gleam`
*   **Issue**: Documentation states the `value` argument is "ignored". **This is false.** The function performs an atomic **Compare-and-Delete** operation (deleting the key *only* if the value matches).
*   **Impact**: Users relying on "ignore value" semantics will introduce race conditions or logic bugs. Users needing CAS-style deletes will think the feature is missing.
*   **Remediation**: Correct documentation to highlight this as a feature ("Atomic Compare-and-Delete").

### 4. Data Loss Risk on Save
*   **Source**: Agent 4 (Security)
*   **Issue**: `ets:to_dets/2` is not atomic. If the process receives `SIGKILL` or crashes during a save, the DETS file may be truncated or corrupted, leading to total data loss.
*   **Remediation**: Implement "safe save": write to a temporary file, then atomic rename to overwrite the persistence file.

### 5. Critical Test Gaps
*   **Source**: Agent 3 (Testing)
*   **Issue**:
    *   `sync` operation is completely untested.
    *   No concurrency/race condition tests.
    *   No crash recovery simulations.
    *   `update_counter` error cases (missing key/non-int) missing.

## 🟡 High Priority (Robustness & Architecture)

### 6. Global Name Collisions
*   **Source**: Agent 1 (Erlang)
*   **Issue**: `ets:new(..., [named_table])` enforces global uniqueness. Two independent components cannot open tables with the same name (e.g., "cache").
*   **Remediation**: Remove `named_table` option. The Gleam API already uses opaque handles, so named tables are unnecessary implementation details.

### 7. Path Traversal Risk
*   **Source**: Agent 4 (Security)
*   **Issue**: `dets:open_file` accepts arbitrary paths. A malicious user could overwrite system files (e.g., `../../etc/passwd`) with DETS data.
*   **Remediation**: Validate paths against an allowed directory or document strictly.

### 8. Code Duplication
*   **Source**: Agent 6 (Architecture)
*   **Issue**: `set.gleam`, `bag.gleam`, and `duplicate_bag.gleam` share ~80% implementation logic.
*   **Remediation**: Extract common logic to `internal.gleam` generic functions (e.g., `internal.insert(table_type, ...)`) to reduce maintenance burden.

## 🔵 Improvements (DX & Polish)

*   **Documentation**:
    *   Use labeled arguments in README examples (e.g., `set.insert(into: t, ...)`). (Agent 5)
    *   Clarify `delete_all` keeps the table open. (Agent 5)
*   **Error Handling**:
    *   The mapping `badarg -> table_closed` is misleading for concurrency violations. (Agent 1)
*   **API**:
    *   `insert_new` FFI receives unused arguments. (Agent 2)

## Recommended Plan
1.  **Fix Criticals**: Atom exhaustion, Documentation error, Memory spike.
2.  **Fill Test Gaps**: Add `sync` and concurrency tests.
3.  **Refactor**: Remove `named_table` and deduplicate code.
