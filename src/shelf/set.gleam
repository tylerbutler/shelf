/// Persistent set tables — one value per key.
///
/// A set table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). On open, existing data is loaded from disk
/// into memory and validated against the provided decoders. On close,
/// data is saved back to disk.
///
/// **Ownership**: The process that calls `open()` owns the table. Reads
/// work from any process; writes and lifecycle ops (`insert`, `delete_*`,
/// `update_counter`, `save`, `reload`, `sync`, `close`) are owner-only
/// and return `Error(NotOwner)` from other processes.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf/set
///
/// let assert Ok(table) =
///   set.open(name: "users", path: "users.dets",
///     base_directory: "/app/data",
///     key: decode.string, value: decode.int)
/// let assert Ok(Nil) = set.insert(table, "alice", 42)
/// let assert Ok(42) = set.lookup(table, "alice")
/// let assert Ok(Nil) = set.save(table)    // persist to disk
/// let assert Ok(Nil) = set.close(table)   // auto-saves on close
/// ```
///
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError}
import shelf/internal.{type DetsRef, type EtsRef, type GuardianRef}

/// An open persistent set table with typed keys and values.
///
/// Reads always go to ETS (fast). Writes go to ETS immediately
/// and to DETS according to the configured write mode.
///
/// The table stores decoders used to validate data loaded from DETS,
/// ensuring type safety at the persistence boundary.
pub opaque type PSet(k, v) {
  PSet(
    ets: EtsRef,
    dets: DetsRef,
    guardian: GuardianRef,
    write_mode: shelf.WriteMode,
    entry_decoder: Decoder(#(k, v)),
    decode_policy: shelf.DecodePolicy,
  )
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent set table with full configuration.
///
/// If the DETS file exists, its contents are loaded into a fresh ETS
/// table after validating each entry through the provided decoders.
/// If no file exists, both tables start empty.
///
/// The DETS file path is validated against the configured base directory.
///
/// ```gleam
/// let config =
///   shelf.config(name: "cache", path: "cache.dets",
///     base_directory: "/app/data")
///   |> shelf.write_mode(shelf.WriteThrough)
/// let assert Ok(table) =
///   set.open_config(config, key: decode.string, value: decode.int)
/// ```
///
pub fn open_config(
  config config: Config,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PSet(k, v), ShelfError) {
  use result <- result.try(internal.generic_open(
    config,
    "set",
    key_decoder,
    value_decoder,
  ))
  Ok(PSet(
    ets: result.0,
    dets: result.1,
    guardian: result.2,
    write_mode: result.3,
    entry_decoder: result.4,
    decode_policy: result.5,
  ))
}

/// Open a persistent set table with defaults (WriteBack mode, Strict decoding).
///
/// ```gleam
/// let assert Ok(table) =
///   set.open(name: "users", path: "users.dets",
///     base_directory: "/app/data",
///     key: decode.string, value: decode.int)
/// ```
///
pub fn open(
  name name: String,
  path path: String,
  base_directory base_directory: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PSet(k, v), ShelfError) {
  open_config(
    config: shelf.config(name:, path:, base_directory:),
    key: key_decoder,
    value: value_decoder,
  )
}

/// Close the table, saving all data to disk.
///
/// Performs a final snapshot of ETS to DETS, closes the DETS file,
/// and deletes the ETS table.
///
/// On `Ok(Nil)`, the handle must not be used again. If the final save
/// fails with a retryable persistence error, `close()` returns
/// `Error(...)` and leaves the table open so the caller can retry.
/// If close fails terminally, Shelf still releases resources and future
/// operations on the handle return `Error(TableClosed)`.
///
pub fn close(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.close(table.ets, table.dets, table.guardian)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// The table is opened before the callback and closed after it returns
/// (even if it returns an error). Data is auto-saved on close; if the
/// final save fails, `with_table` force-cleans the table to release
/// resources. If the callback succeeded, the close error is returned;
/// if both the callback and close fail, the callback error is preserved.
///
/// ```gleam
/// use table <- set.with_table("cache", "cache.dets",
///   base_directory: "/app/data",
///   key: decode.string, value: decode.string)
/// set.insert(table, "key", "value")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  base_directory base_directory: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
  fun fun: fn(PSet(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  use table <- result.try(open(
    name:,
    path:,
    base_directory:,
    key: key_decoder,
    value: value_decoder,
  ))
  let result = case rescue(fn() { fun(table) }) {
    Ok(result) -> result
    Error(_crash) -> Error(shelf.ErlangError("Callback panicked"))
  }
  case close(table) {
    Ok(Nil) -> result
    Error(close_err) -> {
      let _ = internal.cleanup(table.ets, table.dets, table.guardian)
      case result {
        Ok(_) -> Error(close_err)
        Error(_) -> result
      }
    }
  }
}

@external(erlang, "shelf_rescue_ffi", "rescue")
fn rescue(fun: fn() -> a) -> Result(a, String)

// ── Read (always from ETS — fast) ───────────────────────────────────────

/// Look up the value for a key.
///
/// Reads from ETS — consistent microsecond latency regardless of
/// table size or whether the data has been saved to disk.
///
/// Returns `Error(NotFound)` if the key does not exist.
///
pub fn lookup(from table: PSet(k, v), key key: k) -> Result(v, ShelfError) {
  ffi_lookup_set(table.ets, key)
}

/// Check if a key exists without returning the value.
///
pub fn member(of table: PSet(k, v), key key: k) -> Result(Bool, ShelfError) {
  internal.member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(from table: PSet(k, v)) -> Result(List(#(k, v)), ShelfError) {
  internal.to_list(table.ets)
}

/// Fold over all entries. Order is unspecified.
///
pub fn fold(
  over table: PSet(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, ShelfError) {
  internal.generic_fold(table.ets, initial, fun)
}

/// Return the number of entries in the table.
///
pub fn size(of table: PSet(k, v)) -> Result(Int, ShelfError) {
  internal.size(table.ets)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Overwrites if key exists.
///
/// In WriteBack mode, only ETS is updated — call `save()` to persist.
/// In WriteThrough mode, both ETS and DETS are updated.
///
pub fn insert(
  into table: PSet(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  internal.generic_insert(table.ets, table.dets, table.write_mode, key, value)
}

/// Insert multiple key-value pairs at once.
///
pub fn insert_list(
  into table: PSet(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  internal.generic_insert_list(table.ets, table.dets, table.write_mode, entries)
}

/// Insert a key-value pair only if the key does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the key exists.
///
/// In WriteThrough mode, uniqueness is checked in ETS first, then DETS
/// is written, then ETS. Since writes are owner-only (single process),
/// there is no race between the check and write.
///
pub fn insert_new(
  into table: PSet(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  case table.write_mode {
    shelf.WriteThrough -> {
      // Check uniqueness in ETS first
      use exists <- result.try(internal.member(table.ets, key))
      case exists {
        True -> Error(shelf.KeyAlreadyPresent)
        False -> {
          // DETS first, then ETS
          use _ <- result.try(internal.dets_insert(table.dets, #(key, value)))
          internal.insert(table.ets, table.dets, #(key, value))
        }
      }
    }
    shelf.WriteBack -> ffi_insert_new(table.ets, table.dets, #(key, value))
  }
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete the entry with the given key.
///
pub fn delete_key(from table: PSet(k, v), key key: k) -> Result(Nil, ShelfError) {
  internal.generic_delete_key(table.ets, table.dets, table.write_mode, key)
}

/// Atomic Compare-and-Delete: delete the entry only if both key and value match.
///
/// Unlike `delete_key`, which removes the entry regardless of its value,
/// this function checks the full `#(key, value)` tuple. If the stored
/// value doesn't match, nothing is deleted — useful for optimistic
/// concurrency patterns where you want to avoid clobbering a concurrent
/// update.
///
pub fn delete_object(
  from table: PSet(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  internal.generic_delete_object(
    table.ets,
    table.dets,
    table.write_mode,
    key,
    value,
  )
}

/// Delete all entries from the table.
///
/// The table remains open and usable after this call — only the data
/// is removed. To release the table entirely, use `close`.
///
pub fn delete_all(from table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.generic_delete_all(table.ets, table.dets, table.write_mode)
}

// ── Persistence ─────────────────────────────────────────────────────────

/// Snapshot the current ETS contents to DETS.
///
/// Uses an atomic save strategy: data is written to a temporary file
/// first, then atomically renamed over the original DETS file. This
/// prevents data loss if the process is killed mid-save (the original
/// file remains intact until the rename succeeds).
///
/// ```gleam
/// // After a batch of writes...
/// let assert Ok(Nil) = set.save(table)
/// ```
///
pub fn save(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.save(table.ets, table.dets)
}

/// Discard unsaved ETS changes and reload from DETS.
///
/// Clears the ETS table, re-reads all DETS entries, validates them
/// through the stored decoders, and loads valid entries into ETS.
/// The configured decode policy is respected on reload.
/// Only useful in WriteBack mode — in WriteThrough mode, ETS and
/// DETS are always in sync.
///
pub fn reload(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.generic_reload(
    table.ets,
    table.dets,
    table.entry_decoder,
    table.decode_policy,
  )
}

/// Flush the DETS write buffer to the OS.
///
/// DETS buffers writes internally. This forces them to be written
/// to the underlying filesystem. Most useful in WriteThrough mode
/// when you want to guarantee durability.
///
pub fn sync(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.sync_dets(table.ets, table.dets)
}

// ── Counters ────────────────────────────────────────────────────────────

/// Atomically increment an integer value by the given amount.
///
/// The value associated with the key must be an integer. Returns the
/// new value after incrementing. The increment can be negative.
///
/// ```gleam
/// let assert Ok(Nil) = set.insert(table, "hits", 0)
/// let assert Ok(1) = set.update_counter(table, "hits", 1)
/// let assert Ok(3) = set.update_counter(table, "hits", 2)
/// ```
///
/// In WriteThrough mode, the ETS atomic increment happens first (only ETS
/// supports update_counter), then DETS is updated. If the DETS write fails,
/// the ETS increment is rolled back by applying the negated amount.
pub fn update_counter(
  in table: PSet(k, Int),
  key key: k,
  increment amount: Int,
) -> Result(Int, ShelfError) {
  use new_val <- result.try(ffi_update_counter(table.ets, key, amount))
  case table.write_mode {
    shelf.WriteThrough ->
      case internal.dets_insert(table.dets, #(key, new_val)) {
        Ok(Nil) -> Ok(new_val)
        Error(e) -> {
          // Undo ETS change to maintain consistency
          let _ = ffi_update_counter(table.ets, key, -amount)
          Error(e)
        }
      }
    shelf.WriteBack -> Ok(new_val)
  }
}

// ── FFI bindings (set-specific) ─────────────────────────────────────────

@external(erlang, "shelf_ffi", "lookup_set")
fn ffi_lookup_set(ets: EtsRef, key: k) -> Result(v, ShelfError)

@external(erlang, "shelf_ffi", "insert_new")
fn ffi_insert_new(
  ets: EtsRef,
  dets: DetsRef,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "update_counter")
fn ffi_update_counter(
  ets: EtsRef,
  key: k,
  increment: Int,
) -> Result(Int, ShelfError)
