# Fleet Mode: Comprehensive Codebase Review

Launch 6 parallel agents to review the shelf codebase from different expert perspectives. Each agent produces a structured report with findings categorized as **Critical**, **Improvement**, or **Nit**.

## Execution

Launch all 6 agents with `agent_type: "general-purpose"` and `mode: "background"`. After all complete, synthesize findings into a unified report organized by severity, deduplicating overlapping findings and noting where multiple agents flagged the same issue.

---

## Agent 1 — Erlang/OTP Expert: FFI & ETS/DETS Correctness

**Role**: Senior Erlang/OTP engineer reviewing the Erlang FFI layer for correctness, safety, and idiomatic usage of ETS and DETS.

**Files**: `src/shelf_ffi.erl`, `src/shelf/internal.gleam`, `src/shelf/set.gleam`, `src/shelf/bag.gleam`, `src/shelf/duplicate_bag.gleam`, `test/type_safety_test_ffi.erl`

**Review Axes**:
1. **ETS/DETS correctness**: Are ets:\*/dets:\* calls used correctly? Any race conditions between ETS and DETS? Is ets:to_dets/2 semantics understood correctly (it REPLACES all DETS contents)?
2. **Error handling**: Are all Erlang exceptions caught? Could any badarg/badmatch slip through? Is the error translation complete? Are there error atoms that could arrive from ETS/DETS that aren't handled?
3. **Resource leaks**: Could ETS tables or DETS handles leak on failure paths? Check open_no_load's error handling, cleanup/2, and the Gleam-side open_config functions.
4. **Process safety**: ETS tables are owned by the calling process. Are there any concurrency hazards? Is `public` access appropriate? Could named_table cause issues?
5. **Atom exhaustion**: The library converts user-provided strings to atoms via binary_to_atom. Could this be an atom table exhaustion risk?
6. **DETS limitations**: Does the library correctly handle the 2GB limit? What about DETS repair on corrupt files? What happens if the DETS file format changes between OTP versions?
7. **Performance**: Is ets:to_dets/2 the right choice for WriteThrough mode (it replaces ALL DETS contents on every write)? Are there better alternatives?

---

## Agent 2 — Gleam Language Expert: API Design & Idiomatic Gleam

**Role**: Gleam language expert reviewing the public API for idiomatic patterns, type safety, and developer experience.

**Files**: `src/shelf.gleam`, `src/shelf/set.gleam`, `src/shelf/bag.gleam`, `src/shelf/duplicate_bag.gleam`, `src/shelf/internal.gleam`, `README.md`, `gleam.toml`

**Review Axes**:
1. **API consistency**: Are the three table type modules consistent in their function signatures, naming, and behavior? Are there missing operations on some types that should exist?
2. **Type safety**: The opaque types PSet/PBag/PDuplicateBag all store decoders. Is the type safety boundary solid? Could a user circumvent it? Are the phantom types (k, v) used correctly?
3. **Idiomatic Gleam**: Does the API follow Gleam conventions? Are labeled arguments used consistently? Is the `use` pattern (with_table) implemented correctly? Does the config builder pattern feel natural?
4. **Error design**: Is ShelfError well-designed? Are there missing error cases? Should some errors be more specific? Is the error type too flat or appropriately structured?
5. **Module organization**: Is the split between shelf.gleam, internal.gleam, and the table modules correct? Should internal.gleam be truly internal (no pub functions)?
6. **Documentation quality**: Are doc comments (///) complete, accurate, and include examples? Are the module-level docs useful? Does the README accurately reflect the API?
7. **Code duplication**: The three table modules share nearly identical structure. Is there a way to reduce duplication while maintaining type safety? Evaluate the tradeoffs.

---

## Agent 3 — Testing Expert: Coverage, Edge Cases & Reliability

**Role**: Testing specialist reviewing test coverage, edge cases, and test quality for a data persistence library.

**Files (tests)**: `test/shelf_test.gleam`, `test/set_test.gleam`, `test/bag_test.gleam`, `test/duplicate_bag_test.gleam`, `test/persistence_test.gleam`, `test/write_through_test.gleam`, `test/type_safety_test.gleam`, `test/type_safety_test_ffi.erl`

**Files (source)**: `src/shelf/set.gleam`, `src/shelf/bag.gleam`, `src/shelf/duplicate_bag.gleam`, `src/shelf/internal.gleam`, `src/shelf.gleam`, `src/shelf_ffi.erl`

**Review Axes**:
1. **Coverage gaps**: Map every public function in set.gleam, bag.gleam, and duplicate_bag.gleam. Which functions lack tests? Which error paths are untested?
2. **Edge cases**: Are these tested? Empty tables, very long keys/values, non-ASCII keys, integer keys, nested data structures, the 2GB DETS limit, concurrent access from multiple processes, operations after close.
3. **Persistence robustness**: Is there a test that actually simulates process crash (not just close/reopen)? Are corrupt DETS files tested? What about DETS files from a different table type?
4. **Test isolation**: Do tests properly clean up? Could test ordering affect results (shared ETS names, leftover DETS files)? Each test uses unique names — is this sufficient?
5. **WriteThrough coverage**: WriteThrough tests only cover set tables. Are bag and duplicate_bag tested in WriteThrough mode?
6. **Missing test categories**: Are there tests for: insert_list with empty list, delete on non-existent key, fold/to_list on empty table, update_counter on non-existent key, update_counter on non-integer value, with_table when callback errors, reload in WriteThrough mode, sync operation?
7. **Test helper duplication**: Every test file has its own cleanup/delete_file functions. Should these be shared?

---

## Agent 4 — Security & Robustness Reviewer

**Role**: Security and robustness engineer reviewing for potential vulnerabilities and failure modes.

**Files**: `src/shelf_ffi.erl`, `src/shelf/internal.gleam`, `src/shelf.gleam`, `src/shelf/set.gleam`, `src/shelf/bag.gleam`, `src/shelf/duplicate_bag.gleam`, `README.md`

**Review Axes**:
1. **Atom exhaustion attack**: binary_to_atom is called with user-provided strings for both table names and file paths. An attacker creating many tables could exhaust the atom table (1M limit by default), crashing the entire VM. Is this documented? Should binary_to_existing_atom be used instead? What mitigations exist?
2. **Path traversal**: The DETS path is user-provided. Are there any path traversal risks? Could a user overwrite arbitrary files via the DETS path?
3. **Resource exhaustion**: What happens if a user opens many tables and never closes them? Is there any limit? Could this be used for DoS?
4. **Data integrity**: What happens if the process is killed (SIGKILL) during ets:to_dets/2? Is the DETS file left in a corrupt state? Does `{repair, true}` handle this? What data loss scenarios exist?
5. **Error information leakage**: Do error messages (ErlangError(String)) expose internal implementation details that shouldn't be shown to end users?
6. **Type confusion at FFI boundary**: The FFI functions accept arbitrary Erlang terms. Could malformed data from the FFI layer cause crashes in the Gleam code? Is the decode boundary comprehensive?
7. **Cleanup guarantees**: In with_table, if the callback panics (let assert failure), is the table still closed? What about unhandled Erlang exceptions?

---

## Agent 5 — Documentation & Developer Experience Reviewer

**Role**: Developer experience specialist reviewing documentation for completeness, accuracy, and usability.

**Files**: `README.md`, `src/shelf.gleam`, `src/shelf/set.gleam`, `src/shelf/bag.gleam`, `src/shelf/duplicate_bag.gleam`, `src/shelf/internal.gleam`, `gleam.toml`, `CLAUDE.md`, `examples/` directory

**Review Axes**:
1. **Accuracy**: Do all code examples in README.md and doc comments actually compile and work? Are there any stale or incorrect examples?
2. **Completeness**: Are all public functions documented? Are all error cases explained? Is the relationship between save/sync/close clear? Are WriteBack vs WriteThrough tradeoffs well-explained?
3. **Onboarding experience**: Could a new user go from zero to working code using only the README? Are the Quick Start steps complete (install, import, use)? Is the mental model (ETS+DETS) explained clearly?
4. **Missing guides**: Are these topics covered? Process ownership and supervision, error handling patterns, migration/schema evolution, performance characteristics, when NOT to use shelf, comparison to alternatives (Mnesia, bravo+slate).
5. **API discoverability**: Would a user know about with_table, reload, sync, decode_policy, and update_counter from the README alone? Are these features buried or prominent?
6. **HexDocs readiness**: Will `gleam docs build` produce good documentation? Are module-level docs comprehensive? Do function docs include useful descriptions?
7. **Examples project**: Does the examples/ directory exist and work? Does it demonstrate realistic usage patterns?

---

## Agent 6 — Architecture & Maintainability Reviewer

**Role**: Software architect reviewing internal structure for maintainability, extensibility, and technical debt.

**Files**: All source files, all test files, `gleam.toml`, `justfile`, `README.md`, `CLAUDE.md`

**Review Axes**:
1. **Code duplication**: The three table modules (set, bag, duplicate_bag) share ~80% identical code. Quantify the duplication. Could a macro, code generation, or shared abstraction reduce it? What are the tradeoffs in Gleam where there are no macros or traits?
2. **FFI boundary design**: Is the FFI interface well-factored? Should there be more or fewer FFI functions? Is the Gleam↔Erlang type mapping clean? Are there functions that could be pure Gleam instead of FFI?
3. **Extensibility**: How hard would it be to add: (a) a new table type, (b) a new operation (e.g., match/select), (c) a new write mode (e.g., WriteBehind with async batching), (d) table-level options (e.g., read/write concurrency)?
4. **Memory model**: The validate_and_load function materializes all DETS entries 3x (raw list + decoded list + ETS). Is this documented? Is issue #13 (streaming approach) the right fix? What's the practical ceiling?
5. **Internal module exposure**: internal.gleam exports pub functions. Could external users depend on these? Should they use @internal or some other mechanism?
6. **Build & CI**: Is the justfile well-organized? Is CI comprehensive? Are there missing quality gates?
7. **Dependency footprint**: Only gleam_stdlib and gleam_erlang. Is this appropriate? Are there missing dependencies that would improve the library?
