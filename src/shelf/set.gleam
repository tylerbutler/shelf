/// Persistent set tables — one value per key.
///
/// A set table backed by ETS (for fast reads and writes) and DETS
/// (for persistence). On open, existing data is loaded from disk
/// into memory. On close, data is saved back to disk.
///
/// ## Example
///
/// ```gleam
/// import shelf/set
///
/// let assert Ok(table) = set.open("users", "data/users.dets")
/// let assert Ok(Nil) = set.insert(table, "alice", 42)
/// let assert Ok(42) = set.lookup(table, "alice")
/// let assert Ok(Nil) = set.save(table)    // persist to disk
/// let assert Ok(Nil) = set.close(table)   // auto-saves on close
/// ```
///
import shelf.{
  type Config, type ShelfError, type WriteMode, Config, WriteBack, WriteThrough,
}
import shelf/internal.{type DetsRef, type EtsRef}

/// An open persistent set table with typed keys and values.
///
/// Reads always go to ETS (fast). Writes go to ETS immediately
/// and to DETS according to the configured write mode.
pub opaque type PSet(k, v) {
  PSet(ets: EtsRef, dets: DetsRef, write_mode: WriteMode)
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open a persistent set table with full configuration.
///
/// If the DETS file exists, its contents are loaded into a fresh ETS
/// table. If no file exists, both tables start empty.
///
/// ```gleam
/// let config =
///   shelf.config(name: "cache", path: "data/cache.dets")
///   |> shelf.write_mode(shelf.WriteThrough)
/// let assert Ok(table) = set.open_config(config)
/// ```
///
pub fn open_config(config: Config) -> Result(PSet(k, v), ShelfError) {
  let Config(name:, path:, write_mode:) = config
  case ffi_open_set(name, path) {
    Ok(#(ets, dets)) -> Ok(PSet(ets:, dets:, write_mode:))
    Error(err) -> Error(err)
  }
}

/// Open a persistent set table with defaults (WriteBack mode).
///
/// ```gleam
/// let assert Ok(table) = set.open("users", "data/users.dets")
/// ```
///
pub fn open(
  name name: String,
  path path: String,
) -> Result(PSet(k, v), ShelfError) {
  open_config(shelf.config(name:, path:))
}

/// Close the table, saving all data to disk.
///
/// Performs a final snapshot of ETS to DETS, closes the DETS file,
/// and deletes the ETS table. The handle must not be used after closing.
///
pub fn close(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  ffi_close(table.ets, table.dets)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// The table is opened before the callback and closed after it returns
/// (even if it returns an error). Data is auto-saved on close.
///
/// ```gleam
/// use table <- set.with_table("cache", "data/cache.dets")
/// set.insert(table, "key", "value")
/// ```
///
pub fn with_table(
  name name: String,
  path path: String,
  fun fun: fn(PSet(k, v)) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  case open(name:, path:) {
    Ok(table) -> {
      let result = fun(table)
      let _ = close(table)
      result
    }
    Error(err) -> Error(err)
  }
}

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
  ffi_member(table.ets, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
///
pub fn to_list(from table: PSet(k, v)) -> Result(List(#(k, v)), ShelfError) {
  ffi_to_list(table.ets)
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
  ffi_fold(table.ets, wrapper, initial)
}

/// Return the number of entries in the table.
///
pub fn size(of table: PSet(k, v)) -> Result(Int, ShelfError) {
  ffi_size(table.ets)
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
  case ffi_insert(table.ets, table.dets, #(key, value)) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
}

/// Insert multiple key-value pairs at once.
///
pub fn insert_list(
  into table: PSet(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  case ffi_insert_list(table.ets, table.dets, entries) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
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
  case ffi_insert_new(table.ets, table.dets, #(key, value)) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete the entry with the given key.
///
pub fn delete_key(from table: PSet(k, v), key key: k) -> Result(Nil, ShelfError) {
  case ffi_delete_key(table.ets, key) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
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
  case ffi_delete_object(table.ets, key, value) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
}

/// Delete all entries (keeps the table open).
///
pub fn delete_all(from table: PSet(k, v)) -> Result(Nil, ShelfError) {
  case ffi_delete_all(table.ets) {
    Ok(Nil) -> maybe_write_through(table)
    Error(err) -> Error(err)
  }
}

// ── Persistence ─────────────────────────────────────────────────────────

/// Snapshot the current ETS contents to DETS.
///
/// Uses `ets:to_dets/2` internally — atomically replaces all DETS
/// contents with the current ETS state. This is efficient: the
/// transfer happens in the Erlang VM without materializing the
/// entire table as a list.
///
/// ```gleam
/// // After a batch of writes...
/// let assert Ok(Nil) = set.save(table)
/// ```
///
pub fn save(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  ffi_save(table.ets, table.dets)
}

/// Discard unsaved ETS changes and reload from DETS.
///
/// Clears the ETS table and loads all DETS contents into it.
/// Only useful in WriteBack mode — in WriteThrough mode, ETS and
/// DETS are always in sync.
///
pub fn reload(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  ffi_load(table.ets, table.dets)
}

/// Flush the DETS write buffer to the OS.
///
/// DETS buffers writes internally. This forces them to be written
/// to the underlying filesystem. Most useful in WriteThrough mode
/// when you want to guarantee durability.
///
pub fn sync(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  ffi_sync_dets(table.dets)
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
  case ffi_update_counter(table.ets, key, amount) {
    Ok(new_val) -> {
      case table.write_mode {
        WriteThrough -> {
          let _ = ffi_save(table.ets, table.dets)
          Ok(new_val)
        }
        WriteBack -> Ok(new_val)
      }
    }
    Error(err) -> Error(err)
  }
}

// ── Internal ────────────────────────────────────────────────────────────

/// If in WriteThrough mode, save ETS→DETS after every write.
fn maybe_write_through(table: PSet(k, v)) -> Result(Nil, ShelfError) {
  case table.write_mode {
    WriteThrough -> ffi_save(table.ets, table.dets)
    WriteBack -> Ok(Nil)
  }
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "shelf_ffi", "open_set")
fn ffi_open_set(
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

@external(erlang, "shelf_ffi", "insert_new")
fn ffi_insert_new(
  ets: EtsRef,
  dets: DetsRef,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "lookup_set")
fn ffi_lookup_set(ets: EtsRef, key: k) -> Result(v, ShelfError)

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

@external(erlang, "shelf_ffi", "update_counter")
fn ffi_update_counter(
  ets: EtsRef,
  key: k,
  increment: Int,
) -> Result(Int, ShelfError)
