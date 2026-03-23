/// Persistent ETS tables backed by DETS.
///
/// Shelf combines ETS (fast, in-memory) with DETS (persistent, on-disk)
/// to give you microsecond reads with durable storage. The classic
/// Erlang persistence pattern, wrapped in a type-safe Gleam API.
///
/// ## Quick Start
///
/// ```gleam
/// import gleam/dynamic/decode
/// import shelf
/// import shelf/set
///
/// let assert Ok(table) =
///   set.open(name: "cache", path: "data/cache.dets",
///     key: decode.string, value: decode.string)
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
/// - Opening tables with decoder validation materializes all DETS entries
///   into memory; best suited for tables under ~50K entries
///   (see https://github.com/tylerbutler/shelf/issues/13)
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
import gleam/dynamic/decode

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
  /// Data loaded from DETS did not match the expected types.
  ///
  /// Returned when opening a table whose DETS file contains entries that
  /// fail to decode with the provided key/value decoders. The list of
  /// `DecodeError`s describes which fields failed and why.
  TypeMismatch(List(decode.DecodeError))
  /// Erlang-level error (catch-all)
  ErlangError(String)
}

/// Controls how decode failures are handled when loading data from DETS.
pub type DecodePolicy {
  /// Any entry that fails to decode causes the open to fail with
  /// `TypeMismatch`. This is the default and recommended policy.
  Strict
  /// Entries that fail to decode are silently dropped — the count of
  /// skipped entries is not reported. Only successfully decoded entries
  /// are loaded into the ETS table. Use with caution: you may unknowingly
  /// lose data if your decoders don't match all stored entries.
  Lenient
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
pub opaque type Config {
  Config(
    /// Unique name for the ETS table (must not conflict with other ETS tables)
    name: String,
    /// File path for the DETS backing store
    path: String,
    /// When to persist writes to disk
    write_mode: WriteMode,
    /// How to handle entries that fail to decode when loading from DETS
    decode_policy: DecodePolicy,
  )
}

/// Create a config with defaults (WriteBack mode, Strict decode policy).
///
/// ```gleam
/// let conf = shelf.config(name: "users", path: "data/users.dets")
/// ```
///
pub fn config(name name: String, path path: String) -> Config {
  Config(name:, path:, write_mode: WriteBack, decode_policy: Strict)
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

/// Set the decode policy on a config.
///
/// ```gleam
/// let conf =
///   shelf.config(name: "users", path: "data/users.dets")
///   |> shelf.decode_policy(shelf.Lenient)
/// ```
///
pub fn decode_policy(
  config config: Config,
  policy policy: DecodePolicy,
) -> Config {
  Config(..config, decode_policy: policy)
}

// ── Internal accessors ──────────────────────────────────────────────────
// These allow sibling modules to read opaque Config fields.

@internal
pub fn get_name(config: Config) -> String {
  config.name
}

@internal
pub fn get_path(config: Config) -> String {
  config.path
}

@internal
pub fn get_write_mode(config: Config) -> WriteMode {
  config.write_mode
}

@internal
pub fn get_decode_policy(config: Config) -> DecodePolicy {
  config.decode_policy
}
