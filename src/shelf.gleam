/// Persistent ETS tables backed by DETS.
///
/// Shelf combines ETS (fast, in-memory) with DETS (persistent, on-disk)
/// to give you microsecond reads with durable storage. The classic
/// Erlang persistence pattern, wrapped in a type-safe Gleam API.
///
/// ## Quick Start
///
/// ```gleam
/// import shelf
/// import shelf/set
///
/// let assert Ok(table) = set.open(name: "cache", path: "data/cache.dets")
/// let assert Ok(Nil) = set.insert(table, "key", "value")
/// let assert Ok("value") = set.lookup(table, "key")
/// let assert Ok(Nil) = set.save(table)   // persist to disk
/// let assert Ok(Nil) = set.close(table)
/// ```
///
/// ## Write Modes
///
/// - `WriteBack` (default) — writes go to ETS only; call `save()` to persist
/// - `WriteThrough` — every write goes to both ETS and DETS immediately
///
/// ## Table Types
///
/// - `shelf/set` — unique keys, one value per key
/// - `shelf/bag` — multiple distinct values per key
/// - `shelf/duplicate_bag` — multiple values per key (duplicates allowed)
///
/// ## Limitations
///
/// - DETS has a 2 GB maximum file size
/// - No ordered set (DETS doesn't support it)
/// - DETS performs disk I/O — `save()` has real latency
///
/// ## Process Ownership
///
/// ETS tables are owned by the process that calls `open()`. If that process
/// exits or crashes, the ETS table is automatically deleted and any unsaved
/// data is lost. The DETS file on disk is preserved — the next `open()` call
/// reloads it. In long-running applications, ensure the owning process is
/// supervised.
///
/// ## Errors
///
/// Operations return `Result` with `ShelfError` for failures.
pub type ShelfError {
  /// No value found for the given key
  NotFound
  /// Key already exists (for insert_new)
  KeyAlreadyPresent
  /// Table has been closed or doesn't exist
  TableClosed
  /// DETS file could not be found or created
  FileError(String)
  /// An ETS table with this name already exists
  NameConflict
  /// DETS file exceeds the 2 GB limit
  FileSizeLimitExceeded
  /// Erlang-level error (catch-all)
  ErlangError(String)
}

/// Controls when writes are persisted to disk.
pub type WriteMode {
  /// Writes go to ETS only. Call `save()` to persist.
  ///
  /// Best for high-throughput writes where you control the save schedule.
  /// Data written since the last `save()` is lost on crash.
  WriteBack
  /// Every write goes to both ETS and DETS immediately.
  ///
  /// Slower writes but no data loss between saves. Reads are still
  /// fast (always from ETS).
  WriteThrough
}

/// Configuration for opening a persistent table.
pub type Config {
  Config(
    /// Unique name for the ETS table (must not conflict with other ETS tables)
    name: String,
    /// File path for the DETS backing store
    path: String,
    /// When to persist writes to disk
    write_mode: WriteMode,
  )
}

/// Create a config with the default write mode (WriteBack).
///
/// ```gleam
/// let conf = shelf.config(name: "users", path: "data/users.dets")
/// ```
///
pub fn config(name name: String, path path: String) -> Config {
  Config(name:, path:, write_mode: WriteBack)
}

/// Set the write mode on a config.
///
/// ```gleam
/// let conf =
///   shelf.config(name: "users", path: "data/users.dets")
///   |> shelf.write_mode(shelf.WriteThrough)
/// ```
///
pub fn write_mode(config config: Config, mode mode: WriteMode) -> Config {
  Config(..config, write_mode: mode)
}
