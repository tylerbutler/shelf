# shelf

## Project Overview

Persistent ETS tables backed by DETS — fast in-memory access with automatic disk persistence for the BEAM. Implements the classic Erlang ETS/DETS persistence pattern with a type-safe Gleam API.

## Build Commands

```bash
gleam build              # Compile project
gleam test               # Run tests
gleam check              # Type check without building
gleam format src test examples/src    # Format code
gleam docs build         # Generate documentation
```

## Project Structure

```
src/
├── shelf.gleam                 # Shared types (ShelfError, WriteMode, Config)
├── shelf_ffi.erl               # Erlang FFI for ETS + DETS + transfers
└── shelf/
    ├── internal.gleam          # Internal types (EtsRef, DetsRef)
    ├── set.gleam               # Persistent set tables (unique keys)
    ├── bag.gleam               # Persistent bag tables (multiple values per key)
    └── duplicate_bag.gleam     # Persistent duplicate bag tables
test/
├── shelf_test.gleam            # Config builder tests + test entry point
├── set_test.gleam              # Set table tests
├── bag_test.gleam              # Bag table tests
├── duplicate_bag_test.gleam    # Duplicate bag table tests
├── persistence_test.gleam      # Save/reload/survive-restart tests
└── write_through_test.gleam    # WriteThrough mode tests
```

## Architecture

### How It Works

1. **Open**: Creates an ETS table + opens a DETS file, then validates all DETS entries through user-supplied decoders before inserting into ETS
2. **Reads**: Always from ETS (microsecond latency)
3. **Writes**: Always to ETS; DETS depends on WriteMode
4. **Save**: `ets:to_dets/2` atomically snapshots ETS contents to DETS
5. **Close**: Save + close DETS + delete ETS

### Write Modes

- **WriteBack** (default): Writes go to ETS only. Call `save()` to persist.
- **WriteThrough**: Every write triggers `ets:to_dets/2` immediately.

### FFI Pattern

The `shelf_ffi.erl` module wraps raw `ets:*` and `dets:*` calls with error translation. Key native functions used:
- `ets:to_dets(EtsTab, DetsTab)` — replaces all DETS contents with ETS (atomic snapshot)
- `dets:foldl/3` via `dets_fold_into_ets_strict/3` — streams DETS entries through decoders into ETS with batched inserts

### Design Decisions

- **Direct Erlang wrapping** (not built on bravo/slate) to use efficient `ets:to_dets` bulk transfers and decoder-validated loading
- **Opaque table handles**: `PSet(k, v)`, `PBag(k, v)`, `PDuplicateBag(k, v)` enforce type safety
- **No ordered set**: DETS doesn't support `ordered_set`
- **ETS table name**: Always `shelf_ets` (unnamed tables via `ets:new/2`); user-provided name is a diagnostic label only
- **DETS table name**: Mapped through a bounded atom registry (`path_to_dets_name`) to avoid unbounded atom creation

## Dependencies

### Runtime
- `gleam_stdlib` - Standard library
- `gleam_erlang` - Erlang interop

### Development
- `startest` - Testing framework

## Conventions

- Use Result types over exceptions
- Exhaustive pattern matching
- Follow `gleam format` output
- Document public functions with `///` comments
- Test files create temporary `.dets` files in `/tmp/` and clean up after each test
