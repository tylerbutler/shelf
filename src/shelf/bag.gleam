/// Persistent bag tables — multiple distinct values per key.
///
/// A bag table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). Multiple values can be stored per key, but
/// duplicate key-value pairs are silently ignored.
///
/// **Ownership**: The process that calls `open()` owns the table. Reads
/// work from any process; writes and lifecycle ops (`insert`, `delete_*`,
/// `save`, `reload`, `sync`, `close`) are owner-only and return
/// `Error(NotOwner)` from other processes.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf/bag
///
/// let assert Ok(table) =
///   bag.open(name: "tags", path: "data/tags.dets",
///     base_directory: "/app/data",
///     key: decode.string, value: decode.string)
/// let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "red")
/// let assert Ok(Nil) = bag.insert(into: table, key: "color", value: "blue")
/// let assert Ok(["red", "blue"]) = bag.lookup(from: table, key: "color")
/// // values contains "red" and "blue" (order is unspecified)
/// let assert Ok(Nil) = bag.save(table)
/// let assert Ok(Nil) = bag.close(table)
/// ```
///
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError}
import shelf/internal.{
  type DetsReference, type EtsReference, type GuardianReference,
}

/// An open persistent bag table with typed keys and values.
pub opaque type PersistentBag(k, v) {
  PersistentBag(
    ets: EtsReference,
    dets: DetsReference,
    guardian: GuardianReference,
    write_mode: shelf.WriteMode,
    entry_decoder: Decoder(#(k, v)),
  )
}

/// Compatibility alias for `PersistentBag`.
pub type PBag(k, v) =
  PersistentBag(k, v)

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent bag table with full configuration.
///
/// If the DETS file exists, its contents are loaded into a fresh ETS
/// table after validating each entry through the provided decoders.
/// If no file exists, both tables start empty.
///
/// The DETS file path is validated against the configured base directory.
///
/// ```gleam
/// let config =
///   shelf.config(name: "tags", path: "tags.dets",
///     base_directory: "/app/data")
///   |> shelf.write_mode(shelf.WriteThrough)
/// let assert Ok(table) =
///   bag.open_config(config, key: decode.string, value: decode.string)
/// ```
///
pub fn open_config(
  config config: Config,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
) -> Result(PersistentBag(k, v), ShelfError) {
  use result <- result.try(internal.generic_open(
    config,
    internal.Bag,
    key_decoder,
    value_decoder,
  ))
  Ok(PersistentBag(
    ets: result.0,
    dets: result.1,
    guardian: result.2,
    write_mode: result.3,
    entry_decoder: result.4,
  ))
}

/// Open a persistent bag table with defaults (WriteBack mode).
///
/// ```gleam
/// let assert Ok(table) =
///   bag.open(name: "tags", path: "tags.dets",
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
) -> Result(PersistentBag(k, v), ShelfError) {
  open_config(
    config: shelf.config(name:, path:, base_directory:),
    key: key_decoder,
    value: value_decoder,
  )
}

/// Close the table, saving all data to disk.
///
/// On `Ok(Nil)`, the handle must not be used again. If the final save
/// fails with a retryable persistence error, `close()` returns
/// `Error(...)` and leaves the table open so the caller can retry.
/// If close fails terminally, shelf still releases resources and future
/// operations on the handle return `Error(TableClosed)`.
///
pub fn close(table: PersistentBag(k, v)) -> Result(Nil, ShelfError) {
  internal.close(table.ets, table.dets, table.guardian)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// If the final save fails during close, `with_table` force-cleans the
/// table to release resources. If the callback succeeded, the close
/// error is returned; if both the callback and close fail, the callback
/// error is preserved.
///
/// ```gleam
/// use table <- bag.with_table("tags", "tags.dets",
///   base_directory: "/app/data",
///   key: decode.string, value: decode.string)
/// bag.insert(into: table, key: "color", value: "red")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  base_directory base_directory: String,
  key key_decoder: Decoder(k),
  value value_decoder: Decoder(v),
  fun fun: fn(PersistentBag(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  internal.generic_with_table(
    fn() {
      open(
        name:,
        path:,
        base_directory:,
        key: key_decoder,
        value: value_decoder,
      )
    },
    close,
    fn(table) { internal.cleanup(table.ets, table.dets, table.guardian) },
    fun,
  )
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
///
pub fn lookup(
  from table: PersistentBag(k, v),
  key key: k,
) -> Result(List(v), ShelfError) {
  ffi_lookup_bag(table.ets, key)
}

/// Check if a key exists without returning the values.
///
pub fn member(
  of table: PersistentBag(k, v),
  key key: k,
) -> Result(Bool, ShelfError) {
  internal.member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(
  from table: PersistentBag(k, v),
) -> Result(List(#(k, v)), ShelfError) {
  internal.to_list(table.ets)
}

/// Fold over all entries. Order is unspecified.
///
pub fn fold(
  over table: PersistentBag(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, ShelfError) {
  internal.generic_fold(table.ets, initial, fun)
}

/// Return the number of entries in the table.
///
pub fn size(of table: PersistentBag(k, v)) -> Result(Int, ShelfError) {
  internal.size(table.ets)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicate key-value pairs are ignored.
///
pub fn insert(
  into table: PersistentBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  internal.generic_insert(table.ets, table.dets, table.write_mode, key, value)
}

/// Insert multiple key-value pairs.
///
pub fn insert_list(
  into table: PersistentBag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  internal.generic_insert_list(table.ets, table.dets, table.write_mode, entries)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
pub fn delete_key(
  from table: PersistentBag(k, v),
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
  from table: PersistentBag(k, v),
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
pub fn delete_all(from table: PersistentBag(k, v)) -> Result(Nil, ShelfError) {
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
/// See the
/// [Durability story](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story)
/// for the full layer-by-layer breakdown of which crashes this protects against.
///
pub fn save(table: PersistentBag(k, v)) -> Result(Nil, ShelfError) {
  internal.save(table.ets, table.dets)
}

/// Discard unsaved ETS changes and reload from DETS.
///
/// Validates all DETS entries in a scratch table through the stored decoders.
/// Validation failure leaves the live ETS table untouched. On success, clears
/// the live table and fills it one key group at a time to preserve value order.
/// Transfer memory depends on the largest key group, not a fixed batch size.
/// This is not transactional: concurrent readers can see empty or partially
/// reloaded contents.
///
/// Only useful in WriteBack mode — in WriteThrough mode, ETS and
/// DETS are always in sync.
///
pub fn reload(table: PersistentBag(k, v)) -> Result(Nil, ShelfError) {
  internal.generic_reload(table.ets, table.dets, table.entry_decoder)
}

/// Flush pending DETS writes and synchronize dirty file data.
///
/// Calls `dets:sync/1`, which uses `file:sync/1` when saving a dirty
/// disk-backed table. DETS can skip file synchronization if it already
/// marked the table as saved. This does not synchronize the containing
/// directory after file creation or rename. See the
/// [Durability story](https://shelf.tylerbutler.com/advanced/persistence-operations/#durability-story)
/// for what `sync()` does and does not guarantee.
///
pub fn sync(table: PersistentBag(k, v)) -> Result(Nil, ShelfError) {
  internal.sync_dets(table.ets, table.dets)
}

// ── FFI bindings (bag-specific) ─────────────────────────────────────────

@external(erlang, "shelf_ffi", "lookup_bag")
fn ffi_lookup_bag(ets: EtsReference, key: k) -> Result(List(v), ShelfError)
