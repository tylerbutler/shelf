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
///     base_directory: "/app/storage",
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
/// ## Security
///
/// All DETS file paths are validated against a required base directory.
/// Paths that escape the base directory (e.g., via `..` traversal) or
/// contain null bytes are rejected with `InvalidPath`.
///
/// ## Limitations
///
/// - DETS has a 2 GB maximum file size
/// - No ordered set (DETS doesn't support it)
/// - DETS performs disk I/O — `save()` has real latency
/// - Opening tables streams entries via `dets:foldl` directly into ETS
///   without materializing a full list in memory.
///
/// ## Process Ownership
///
/// ETS tables are owned by the process that calls `open()`. If that process
/// exits or crashes, the ETS table is automatically deleted and any unsaved
/// data is lost. The DETS file on disk is preserved — the next `open()` call
/// reloads it. In long-running applications, ensure the owning process is
/// supervised.
///
/// **Reads** (`lookup`, `member`, `to_list`, `fold`, `size`) work from any
/// process — ETS tables are created as `protected`.
///
/// **Writes and lifecycle** (`insert`, `delete_*`, `update_counter`, `save`,
/// `reload`, `sync`, `close`) are restricted to the owner process. Non-owner
/// attempts return `Error(NotOwner)`. If you need cross-process writes, wrap
/// the table in a supervised actor/server that owns the table and forwards
/// mutation requests.
///
/// ## Errors
///
/// Operations return `Result` with `ShelfError` for failures.
import gleam/dynamic/decode
import gleam/string

pub type ShelfError {
  /// No value found for the given key
  NotFound
  /// Key already exists (for insert_new)
  KeyAlreadyPresent
  /// Table has been closed or doesn't exist
  TableClosed
  /// The calling process is not the table owner.
  ///
  /// ETS tables are `protected` — only the process that called `open()`
  /// can perform writes and lifecycle operations. Other processes can
  /// read freely. Wrap the table in a supervised actor/server if you
  /// need cross-process writes.
  NotOwner
  /// DETS file could not be found or created
  FileError(String)
  /// A DETS file at this path is already open by another shelf table.
  /// This is a file-level conflict, not related to the table name.
  NameConflict
  /// The DETS file path is invalid (escapes base directory, contains
  /// null bytes, or is otherwise unsafe)
  InvalidPath(String)
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
    /// Diagnostic label for the table (not used as an ETS table name)
    name: String,
    /// File path for the DETS backing store (relative to base_directory)
    path: String,
    /// Base directory that all DETS paths are resolved against
    base_directory: String,
    /// When to persist writes to disk
    write_mode: WriteMode,
  )
}

/// Create a config with defaults (WriteBack mode).
///
/// The `name` is a diagnostic label for the table — it is not used as an
/// ETS table name and does not need to be unique. Multiple tables can
/// share the same name as long as they use different DETS file paths.
///
/// The `base_directory` restricts DETS file paths to prevent directory
/// traversal attacks. The `path` is resolved relative to `base_directory`.
///
/// ```gleam
/// let conf = shelf.config(name: "users", path: "users.dets",
///   base_directory: "/app/data")
/// ```
///
pub fn config(
  name name: String,
  path path: String,
  base_directory base_directory: String,
) -> Config {
  Config(name:, path:, base_directory:, write_mode: WriteBack)
}

/// Set the write mode on a config.
///
/// ```gleam
/// let conf =
///   shelf.config(name: "users", path: "users.dets",
///     base_directory: "/app/data")
///   |> shelf.write_mode(shelf.WriteThrough)
/// ```
///
pub fn write_mode(config config: Config, mode mode: WriteMode) -> Config {
  Config(..config, write_mode: mode)
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
pub fn get_base_directory(config: Config) -> String {
  config.base_directory
}

@internal
pub fn get_write_mode(config: Config) -> WriteMode {
  config.write_mode
}

/// Validate that a path is safe and resolve it against the base directory.
///
/// Rejects paths containing null bytes or that escape the base directory
/// via `..` traversal. Returns the resolved absolute path on success.
@internal
pub fn validate_path(
  path: String,
  base_directory: String,
) -> Result(String, ShelfError) {
  case string.contains(path, "\u{0}") {
    True -> Error(InvalidPath("Path contains null bytes"))
    False ->
      case string.contains(base_directory, "\u{0}") {
        True -> Error(InvalidPath("Base directory contains null bytes"))
        False -> ffi_validate_path(path, base_directory)
      }
  }
}

@external(erlang, "shelf_ffi", "validate_path")
fn ffi_validate_path(
  path: String,
  base_directory: String,
) -> Result(String, ShelfError)
