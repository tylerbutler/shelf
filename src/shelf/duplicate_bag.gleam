/// Persistent duplicate bag tables — multiple values per key, duplicates allowed.
///
/// A duplicate bag table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). Multiple values can be stored per key, and identical
/// key-value pairs are preserved (unlike bag tables which deduplicate).
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf/duplicate_bag
///
/// let assert Ok(table) =
///   duplicate_bag.open(name: "events", path: "data/events.dets",
///     key: decode.string, value: decode.string)
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_1")
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_1")
/// let assert Ok(["btn_1", "btn_1"]) = duplicate_bag.lookup(table, "click")
/// // values contains "btn_1" twice (order is unspecified)
/// let assert Ok(Nil) = duplicate_bag.close(table)
/// ```
///
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError}
import shelf/internal.{type DetsRef, type EtsRef, type GuardianRef}

/// An open persistent duplicate bag table with typed keys and values.
pub opaque type PDuplicateBag(k, v) {
  PDuplicateBag(
    ets: EtsRef,
    dets: DetsRef,
    guardian: GuardianRef,
    write_mode: shelf.WriteMode,
    entry_decoder: Decoder(#(k, v)),
    decode_policy: shelf.DecodePolicy,
  )
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent duplicate bag table with full configuration.
///
/// If the DETS file exists, its contents are loaded into a fresh ETS
/// table after validating each entry through the provided decoders.
/// If no file exists, both tables start empty.
///
/// The DETS file path is validated against the configured base directory.
///
/// ```gleam
/// let config =
///   shelf.config(name: "events", path: "events.dets",
///     base_directory: "/app/data")
///   |> shelf.write_mode(shelf.WriteThrough)
/// let assert Ok(table) =
///   duplicate_bag.open_config(config,
///     key: decode.string, value: decode.string)
/// ```
///
pub fn open_config(
  config config: Config,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PDuplicateBag(k, v), ShelfError) {
  use result <- result.try(internal.generic_open(
    config,
    "duplicate_bag",
    key_decoder,
    value_decoder,
  ))
  Ok(PDuplicateBag(
    ets: result.0,
    dets: result.1,
    guardian: result.2,
    write_mode: result.3,
    entry_decoder: result.4,
    decode_policy: result.5,
  ))
}

/// Open a persistent duplicate bag table with defaults (WriteBack mode, Strict decoding).
///
/// ```gleam
/// let assert Ok(table) =
///   duplicate_bag.open(name: "events", path: "events.dets",
///     base_directory: "/app/data",
///     key: decode.string, value: decode.string)
/// ```
///
pub fn open(
  name name: String,
  path path: String,
  base_directory base_directory: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PDuplicateBag(k, v), ShelfError) {
  open_config(
    config: shelf.config(name:, path:, base_directory:),
    key: key_decoder,
    value: value_decoder,
  )
}

/// Close the table, saving all data to disk.
///
pub fn close(table: PDuplicateBag(k, v)) -> Result(Nil, ShelfError) {
  internal.close(table.ets, table.dets, table.guardian)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// ```gleam
/// use table <- duplicate_bag.with_table("events", "events.dets",
///   base_directory: "/app/data",
///   key: decode.string, value: decode.string)
/// duplicate_bag.insert(table, "click", "btn_1")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  base_directory base_directory: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
  fun fun: fn(PDuplicateBag(k, v)) -> Result(a, ShelfError),
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
    Error(close_err) ->
      case result {
        Ok(_) -> Error(close_err)
        Error(_) -> result
      }
  }
}

@external(erlang, "shelf_rescue_ffi", "rescue")
fn rescue(fun: fn() -> a) -> Result(a, String)

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
///
pub fn lookup(
  from table: PDuplicateBag(k, v),
  key key: k,
) -> Result(List(v), ShelfError) {
  ffi_lookup_bag(table.ets, key)
}

/// Check if a key exists without returning the values.
///
pub fn member(
  of table: PDuplicateBag(k, v),
  key key: k,
) -> Result(Bool, ShelfError) {
  internal.member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(
  from table: PDuplicateBag(k, v),
) -> Result(List(#(k, v)), ShelfError) {
  internal.to_list(table.ets)
}

/// Fold over all entries. Order is unspecified.
///
pub fn fold(
  over table: PDuplicateBag(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, ShelfError) {
  internal.generic_fold(table.ets, initial, fun)
}

/// Return the number of entries in the table.
///
pub fn size(of table: PDuplicateBag(k, v)) -> Result(Int, ShelfError) {
  internal.size(table.ets)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicates are preserved.
///
pub fn insert(
  into table: PDuplicateBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  internal.generic_insert(table.ets, table.dets, table.write_mode, key, value)
}

/// Insert multiple key-value pairs.
///
pub fn insert_list(
  into table: PDuplicateBag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  internal.generic_insert_list(table.ets, table.dets, table.write_mode, entries)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
pub fn delete_key(
  from table: PDuplicateBag(k, v),
  key key: k,
) -> Result(Nil, ShelfError) {
  internal.generic_delete_key(table.ets, table.dets, table.write_mode, key)
}

/// Delete a specific key-value pair.
///
/// Only the exact matching pair is removed. Other values for the same
/// key are preserved.
///
pub fn delete_object(
  from table: PDuplicateBag(k, v),
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
pub fn delete_all(from table: PDuplicateBag(k, v)) -> Result(Nil, ShelfError) {
  internal.generic_delete_all(table.ets, table.dets, table.write_mode)
}

// ── Persistence ─────────────────────────────────────────────────────────

/// Snapshot the current ETS contents to DETS.
///
/// Uses an atomic save strategy: data is written to a temporary file
/// first, then atomically renamed over the original DETS file. This
/// prevents data loss if the process is killed mid-save.
///
pub fn save(table: PDuplicateBag(k, v)) -> Result(Nil, ShelfError) {
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
pub fn reload(table: PDuplicateBag(k, v)) -> Result(Nil, ShelfError) {
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
pub fn sync(table: PDuplicateBag(k, v)) -> Result(Nil, ShelfError) {
  internal.sync_dets(table.dets)
}

// ── FFI bindings (duplicate-bag-specific) ────────────────────────────────

@external(erlang, "shelf_ffi", "lookup_bag")
fn ffi_lookup_bag(ets: EtsRef, key: k) -> Result(List(v), ShelfError)
