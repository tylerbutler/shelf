/// Persistent bag tables — multiple distinct values per key.
///
/// A bag table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). Multiple values can be stored per key, but
/// duplicate key-value pairs are silently ignored.
///
/// ## Example
///
/// ```gleam
/// import shelf/bag
///
/// let assert Ok(table) = bag.open("tags", "data/tags.dets")
/// let assert Ok(Nil) = bag.insert(table, "color", "red")
/// let assert Ok(Nil) = bag.insert(table, "color", "blue")
/// let assert Ok(["red", "blue"]) = bag.lookup(table, "color")
/// let assert Ok(Nil) = bag.save(table)
/// let assert Ok(Nil) = bag.close(table)
/// ```
///
import gleam/result
import shelf.{
  type Config, type ShelfError, type WriteMode, Config, WriteBack, WriteThrough,
}
import shelf/internal.{type DetsRef, type EtsRef}

/// An open persistent bag table with typed keys and values.
pub opaque type PBag(k, v) {
  PBag(ets: EtsRef, dets: DetsRef, write_mode: WriteMode)
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent bag table with full configuration.
///
pub fn open_config(config: Config) -> Result(PBag(k, v), ShelfError) {
  let Config(name:, path:, write_mode:) = config
  ffi_open_bag(name, path)
  |> result.map(fn(refs) { PBag(ets: refs.0, dets: refs.1, write_mode:) })
}

/// Open a persistent bag table with defaults (WriteBack mode).
///
/// ```gleam
/// let assert Ok(table) = bag.open("tags", "data/tags.dets")
/// ```
///
pub fn open(
  name name: String,
  path path: String,
) -> Result(PBag(k, v), ShelfError) {
  open_config(shelf.config(name:, path:))
}

/// Close the table, saving all data to disk.
///
pub fn close(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  ffi_close(table.ets, table.dets)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// ```gleam
/// use table <- bag.with_table("tags", "data/tags.dets")
/// bag.insert(table, "color", "red")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  fun fun: fn(PBag(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  use table <- result.try(open(name:, path:))
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
  ffi_member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(from table: PBag(k, v)) -> Result(List(#(k, v)), ShelfError) {
  ffi_to_list(table.ets)
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
  ffi_fold(table.ets, wrapper, initial)
}

/// Return the number of objects stored.
///
pub fn size(of table: PBag(k, v)) -> Result(Int, ShelfError) {
  ffi_size(table.ets)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicate key-value pairs are ignored.
///
pub fn insert(
  into table: PBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(ffi_insert(table.ets, table.dets, #(key, value)))
  maybe_write_through(table)
}

/// Insert multiple key-value pairs.
///
pub fn insert_list(
  into table: PBag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  use _ <- result.try(ffi_insert_list(table.ets, table.dets, entries))
  maybe_write_through(table)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
pub fn delete_key(from table: PBag(k, v), key key: k) -> Result(Nil, ShelfError) {
  use _ <- result.try(ffi_delete_key(table.ets, key))
  maybe_write_through(table)
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
  use _ <- result.try(ffi_delete_object(table.ets, key, value))
  maybe_write_through(table)
}

/// Delete all entries (keeps the table open).
///
pub fn delete_all(from table: PBag(k, v)) -> Result(Nil, ShelfError) {
  use _ <- result.try(ffi_delete_all(table.ets))
  maybe_write_through(table)
}

// ── Persistence ─────────────────────────────────────────────────────────

/// Snapshot the current ETS contents to DETS.
///
pub fn save(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  ffi_save(table.ets, table.dets)
}

/// Discard unsaved ETS changes and reload from DETS.
///
pub fn reload(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  ffi_load(table.ets, table.dets)
}

/// Flush the DETS write buffer to the OS.
///
pub fn sync(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  ffi_sync_dets(table.dets)
}

// ── Internal ────────────────────────────────────────────────────────────

fn maybe_write_through(table: PBag(k, v)) -> Result(Nil, ShelfError) {
  case table.write_mode {
    WriteThrough -> ffi_save(table.ets, table.dets)
    WriteBack -> Ok(Nil)
  }
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "shelf_ffi", "open_bag")
fn ffi_open_bag(
  name: String,
  path: String,
) -> Result(#(EtsRef, DetsRef), ShelfError)

@external(erlang, "shelf_ffi", "close")
fn ffi_close(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert")
fn ffi_insert(
  ets: EtsRef,
  dets: DetsRef,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert_list")
fn ffi_insert_list(
  ets: EtsRef,
  dets: DetsRef,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "lookup_bag")
fn ffi_lookup_bag(ets: EtsRef, key: k) -> Result(List(v), ShelfError)

@external(erlang, "shelf_ffi", "member")
fn ffi_member(ets: EtsRef, key: k) -> Result(Bool, ShelfError)

@external(erlang, "shelf_ffi", "to_list")
fn ffi_to_list(ets: EtsRef) -> Result(List(#(k, v)), ShelfError)

@external(erlang, "shelf_ffi", "fold")
fn ffi_fold(
  ets: EtsRef,
  fun: fn(#(k, v), acc) -> acc,
  acc: acc,
) -> Result(acc, ShelfError)

@external(erlang, "shelf_ffi", "size")
fn ffi_size(ets: EtsRef) -> Result(Int, ShelfError)

@external(erlang, "shelf_ffi", "delete_key")
fn ffi_delete_key(ets: EtsRef, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_object")
fn ffi_delete_object(ets: EtsRef, key: k, value: v) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_all")
fn ffi_delete_all(ets: EtsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "save")
fn ffi_save(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "load")
fn ffi_load(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "sync_dets")
fn ffi_sync_dets(dets: DetsRef) -> Result(Nil, ShelfError)
