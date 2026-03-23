# Security & Robustness Report: shelf

**Agent:** Agent 4 — Security & Robustness Reviewer
**Date:** 2024-10-24
**Target:** `shelf` (v0.1.0-dev)

## Executive Summary

The `shelf` library provides a type-safe wrapper around Erlang's `ets` and `dets`. While it successfully bridges Gleam's type system with Erlang's persistence layer, it inherits significant operational risks from the underlying Erlang APIs—specifically regarding atom exhaustion and data durability. The most critical findings relate to Denial of Service (DoS) vectors via atom creation and potential data loss scenarios during process termination.

## Findings

### 1. Atom Exhaustion (DoS) [Critical]
**Location:** `src/shelf_ffi.erl` lines 21-22
```erlang
EtsName = binary_to_atom(Name, utf8),
DetsName = binary_to_atom(Path, utf8),
```
**Vulnerability:** The `open` function converts user-provided strings (`Name` and `Path`) to Erlang atoms. Erlang has a default limit of roughly 1,000,000 atoms. Atoms are not garbage collected.
**Impact:** An attacker who can trigger table creation with random names or paths can crash the entire Erlang VM (DoS).
**Recommendation:** 
*   **Documentation:** Strengthen warning in README (currently present but easy to miss).
*   **Mitigation:** Consider removing `named_table` from ETS creation to use `tid` instead of atoms. For DETS, which requires an atom name, implement a dynamic pool of reusable worker atoms or a registry, rather than using the user-provided string directly as the atom name.

### 2. Data Loss on SIGKILL [Critical]
**Location:** `src/shelf_ffi.erl` line 194 (via `ets:to_dets/2`)
**Vulnerability:** `ets:to_dets/2` is not atomic. It effectively truncates the file and rewrites it.
**Impact:** If the process receives a `SIGKILL` or the machine loses power during a `save()` operation, the DETS file may be left empty or corrupt, resulting in total data loss. `repair: true` cannot recover data that was deleted but not yet written.
**Recommendation:**
*   **Architecture:** Implement a "safe save" pattern: `ets:to_dets` to a temporary file, then `file:rename/2` to overwrite the primary file atomically.

### 3. Path Traversal [High]
**Location:** `src/shelf_ffi.erl` line 26
```erlang
{file, binary_to_list(Path)},
```
**Vulnerability:** The `Path` argument is passed directly to `dets:open_file`.
**Impact:** A user can supply paths like `../../sensitive_file`. Since DETS creates/overwrites files, this allows overwriting arbitrary files on the system with DETS binary data, potentially destroying configuration or system files.
**Recommendation:** Validate `Path` against an allowlist directory or sanitize input if the library is intended for use with untrusted inputs.

### 4. Resource Exhaustion [Medium]
**Location:** General architecture
**Vulnerability:** No limits on the number of open tables or file descriptors.
**Impact:** Opening a large number of tables can exhaust system file descriptors (DETS) or RAM (ETS).
**Recommendation:** Document resource usage implications clearly.

### 5. Error Information Leakage [Low]
**Location:** `src/shelf_ffi.erl` line 276
```erlang
{erlang_error, list_to_binary(io_lib:format("~p", [Reason]))}.
```
**Vulnerability:** Raw Erlang error terms are formatted and returned to the caller.
**Impact:** May expose internal file paths or stack traces in error messages.
**Recommendation:** Ensure applications using `shelf` sanitize these errors before displaying them to end-users.

### 6. Cleanup Guarantees [Pass]
**Location:** `src/shelf/set.gleam` (and others) `with_table`
**Analysis:** Correctly uses `rescue` (try/catch) to ensure `close` is called even if the callback panics.

### 7. Type Safety [Pass]
**Location:** `src/shelf/internal.gleam`
**Analysis:** The `validate_and_load` flow ensures that corrupt or malformed data in the DETS file is caught at `open` time, preserving type safety for the application.

## Summary

The library is functional but requires careful usage in production environments. The **Atom Exhaustion** and **Data Loss** issues are structural and should be addressed before v1.0.

**Status:** Review Complete.
