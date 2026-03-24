/// Persistent bag tables — multiple distinct values per key.
///
/// A bag table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). Multiple values can be stored per key, but
/// duplicate key-value pairs are silently ignored.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf/bag
///
/// let assert Ok(table) =
///   bag.open(name: "tags", path: "data/tags.dets",
///     key: decode.string, value: decode.string)
/// let assert Ok(Nil) = bag.insert(table, "color", "red")
/// let assert Ok(Nil) = bag.insert(table, "color", "blue")
/// let assert Ok(["red", "blue"]) = bag.lookup(table, "color")
/// let assert Ok(Nil) = bag.save(table)
/// let assert Ok(Nil) = bag.close(table)
/// ```
///
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError}
import shelf/internal.{type DetsRef, type EtsRef}

/// An open persistent bag table with typed keys and values.
pub opaque type PBag(k, v) {
  PBag(
    ets: EtsRef,
    dets: DetsRef,
    write_mode: shelf.WriteMode,
    entry_decoder: Decoder(#(k, v)),
    decode_policy: shelf.DecodePolicy,
  )
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent bag table with full configuration.
///
/// If the DETS file exists, its contents are loaded into a fresh ETS
/// table after validating each entry through the provided decoders.
/// If no file exists, both tables start empty.
///
/// ```gleam
/// let config =
///   shelf.config(name: "tags", path: "data/tags.dets")
///   |> shelf.write_mode(shelf.WriteThrough)
/// let assert Ok(table) =
///   bag.open_config(config, key: decode.string, value: decode.string)
/// ```
///
pub fn open_config(
  config config: Config,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PBag(k, v), ShelfError) {
  let name = shelf.get_name(config)
  let path = shelf.get_path(config)
  let write_mode = shelf.get_write_mode(config)
  let decode_policy = shelf.get_decode_policy(config)
  use refs <- result.try(internal.open_no_load(name, path, "bag"))
  let ets = refs.0
  let dets = refs.1
  let entry_decoder = internal.build_entry_decoder(key_decoder, value_decoder)
  use entries <- result.try(internal.dets_to_list(dets))
  case
    internal.validate_and_load(entries, ets, dets, entry_decoder, decode_policy)
  {
    Ok(Nil) ->
      Ok(PBag(ets:, dets:, write_mode:, entry_decoder:, decode_policy:))
    Error(e) -> {
      let _ = internal.cleanup(ets, dets)
      Error(e)
    }
  }
}

/// Open a persistent bag table with defaults (WriteBack mode, Strict decoding).
///
/// ```gleam
/// let assert Ok(table) =
///   bag.open(name: "tags", path: "data/tags.dets",
///     key: decode.string, value: decode.string)
/// ```
///
pub fn open(
  name name: String,
  path path: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PBag(k, v), ShelfError) {
  open_config(
    config: shelf.config(name:, path:),
    key: key_decoder,
    value: value_decoder,
  )
}

/// Close the table, saving all data to disk.
///
pub fn close(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  internal.close(table.ets, table.dets)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// ```gleam
/// use table <- bag.with_table("tags", "data/tags.dets",
///   key: decode.string, value: decode.string)
/// bag.insert(table, "color", "red")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
  fun fun: fn(PBag(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  use table <- result.try(open(
    name:,
    path:,
    key: key_decoder,
    value: value_decoder,
  ))
  let result = fun(table)
  let _ = close(table)
  result
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
///
pub fn lookup(from table: PBag(k, v), key key: k) -> Result(List(v), ShelfError) {
  ffi_lookup_bag(table.ets, key)
}

/// Check if a key exists without returning the values.
///
pub fn member(of table: PBag(k, v), key key: k) -> Result(Bool, ShelfError) {
  internal.member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(from table: PBag(k, v)) -> Result(List(#(k, v)), ShelfError) {
  internal.to_list(table.ets)
}

/// Fold over all entries. Order is unspecified.
///
pub fn fold(
  over table: PBag(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, ShelfError) {
  let wrapper = fn(entry: #(k, v), acc: acc) -> acc {
    fun(acc, entry.0, entry.1)
  }
  internal.fold(table.ets, wrapper, initial)
}

/// Return the number of objects stored.
///
pub fn size(of table: PBag(k, v)) -> Result(Int, ShelfError) {
  internal.size(table.ets)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicate key-value pairs are ignored.
///
pub fn insert(
  into table: PBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.insert(table.ets, table.dets, #(key, value)))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Insert multiple key-value pairs.
///
pub fn insert_list(
  into table: PBag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.insert_list(table.ets, table.dets, entries))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
pub fn delete_key(from table: PBag(k, v), key key: k) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.delete_key(table.ets, key))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Delete a specific key-value pair.
///
/// Only the exact matching pair is removed. Other values for the same
/// key are preserved.
///
pub fn delete_object(
  from table: PBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(internal.delete_object(table.ets, key, value))
  internal.maybe_write_through(table.ets, table.dets, table.write_mode)
}

/// Delete all entries (keeps the table open).
///
pub fn delete_all(from table: PBag(k, v)) -> Result(Nil, ShelfError) {
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
pub fn save(table: PBag(k, v)) -> Result(Nil, ShelfError) {
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
pub fn reload(table: PBag(k, v)) -> Result(Nil, ShelfError) {
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
pub fn sync(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  internal.sync_dets(table.dets)
}

// ── FFI bindings (bag-specific) ─────────────────────────────────────────

@external(erlang, "shelf_ffi", "lookup_bag")
fn ffi_lookup_bag(ets: EtsRef, key: k) -> Result(List(v), ShelfError)
