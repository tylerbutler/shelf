/// Persistent set tables — one value per key.
///
/// A set table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). On open, existing data is loaded from disk
/// into memory and validated against the provided decoders. On close,
/// data is saved back to disk.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf/set
///
/// let assert Ok(table) =
///   set.open(name: "users", path: "data/users.dets",
///     key: decode.string, value: decode.int)
/// let assert Ok(Nil) = set.insert(table, "alice", 42)
/// let assert Ok(42) = set.lookup(table, "alice")
/// let assert Ok(Nil) = set.save(table)    // persist to disk
/// let assert Ok(Nil) = set.close(table)   // auto-saves on close
/// ```
///
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError, Config}
import shelf/internal.{type DetsRef, type EtsRef}

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
/// ```gleam
/// let config =
///   shelf.config(name: "cache", path: "data/cache.dets")
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
  let Config(name:, path:, write_mode:, decode_policy:) = config
  use refs <- result.try(internal.open_no_load(name, path, "set"))
  let ets = refs.0
  let dets = refs.1
  let entry_decoder = internal.build_entry_decoder(key_decoder, value_decoder)
  case internal.dets_to_list(dets) {
    Error(e) -> {
      let _ = internal.cleanup(ets, dets)
      Error(e)
    }
    Ok(entries) ->
      case
        internal.validate_and_load(
          entries,
          ets,
          dets,
          entry_decoder,
          decode_policy,
        )
      {
        Ok(Nil) ->
          Ok(PSet(ets:, dets:, write_mode:, entry_decoder:, decode_policy:))
        Error(e) -> {
          let _ = internal.cleanup(ets, dets)
          Error(e)
        }
      }
  }
}

/// Open a persistent set table with defaults (WriteBack mode, Strict decoding).
///
/// ```gleam
/// let assert Ok(table) =
///   set.open(name: "users", path: "data/users.dets",
///     key: decode.string, value: decode.int)
/// ```
///
pub fn open(
  name name: String,
  path path: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PSet(k, v), ShelfError) {
  open_config(
    config: shelf.config(name:, path:),
    key: key_decoder,
    value: value_decoder,
  )
}

/// Close the table, saving all data to disk.
///
/// Performs a final snapshot of ETS to DETS, closes the DETS file,
/// and deletes the ETS table. The handle must not be used after closing.
///
pub fn close(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  internal.close(table.ets, table.dets)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// The table is opened before the callback and closed after it returns
/// (even if it returns an error). Data is auto-saved on close.
///
/// ```gleam
/// use table <- set.with_table("cache", "data/cache.dets",
///   key: decode.string, value: decode.string)
/// set.insert(table, "key", "value")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
  fun fun: fn(PSet(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  use table <- result.try(open(
    name:,
    path:,
    key: key_decoder,
    value: value_decoder,
  ))
  let result = case rescue(fn() { fun(table) }) {
    Ok(result) -> result
    Error(_crash) -> Error(shelf.ErlangError("Callback panicked"))
  }
  case close(table) {
    Ok(Nil) -> result
    Error(close_err) ->
      case result {
        Ok(_) -> Error(close_err)
        Error(_) -> result
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
  let wrapper = fn(entry: #(k, v), acc: acc) -> acc {
    fun(acc, entry.0, entry.1)
  }
  internal.fold(table.ets, wrapper, initial)
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
  use _ <- result.try(internal.insert(table.ets, table.dets, #(key, value)))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Insert multiple key-value pairs at once.
///
pub fn insert_list(
  into table: PSet(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.insert_list(table.ets, table.dets, entries))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Insert a key-value pair only if the key does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the key exists.
///
pub fn insert_new(
  into table: PSet(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(ffi_insert_new(table.ets, table.dets, #(key, value)))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete the entry with the given key.
///
pub fn delete_key(from table: PSet(k, v), key key: k) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.delete_key(table.ets, key))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Delete a specific key-value pair.
///
/// For set tables, this is equivalent to `delete_key` since each key
/// has at most one value.
///
pub fn delete_object(
  from table: PSet(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.delete_object(table.ets, key, value))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Delete all entries (keeps the table open).
///
pub fn delete_all(from table: PSet(k, v)) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.delete_all(table.ets))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

// ── Persistence ─────────────────────────────────────────────────────────

/// Snapshot the current ETS contents to DETS.
///
/// Uses `ets:to_dets/2` internally — atomically replaces all DETS
/// contents with the current ETS state. This is efficient: the
/// transfer happens in the Erlang VM without materializing the
/// entire table as a list.
///
/// **Crash safety**: `ets:to_dets/2` replaces DETS contents non-atomically —
/// it deletes existing DETS data then inserts from ETS. A process kill
/// (SIGKILL) between delete and insert can leave DETS empty. Normal
/// shutdowns and Erlang exceptions are safe. Consider periodic backups
/// for critical data.
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
  use _ <- result.try(internal.delete_all(table.ets))
  use entries <- result.try(internal.dets_to_list(table.dets))
  internal.validate_and_load(
    entries,
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
  internal.sync_dets(table.dets)
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
pub fn update_counter(
  in table: PSet(k, Int),
  key key: k,
  increment amount: Int,
) -> Result(Int, ShelfError) {
  use new_val <- result.try(ffi_update_counter(table.ets, key, amount))
  use _ <- result.try(internal.maybe_write_through(
    table.ets,
    table.dets,
    table.write_mode,
  ))
  Ok(new_val)
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
