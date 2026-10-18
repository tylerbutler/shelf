/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references and shared logic used by
/// shelf table types.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{type Config, type ShelfError, type WriteMode}

/// Raw ETS table reference (Erlang tid).
@internal
pub type EtsReference

/// Raw DETS table reference (Erlang atom).
@internal
pub type DetsReference

/// Guardian process PID — monitors the owner and cleans up DETS on crash.
@internal
pub type GuardianReference

/// Native ETS/DETS kinds, represented by the atoms set, bag, duplicate_bag.
@internal
pub type TableKind {
  Set
  Bag
  DuplicateBag
}

// ── Shared helpers ──────────────────────────────────────────────────────

/// Compose key and value decoders into a tuple entry decoder.
@internal
pub fn build_entry_decoder(
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Decoder(#(k, v)) {
  use key <- decode.field(0, key_decoder)
  use value <- decode.field(1, value_decoder)
  decode.success(#(key, value))
}

/// Stream DETS entries through the decoder and insert into ETS one at a time.
///
/// Uses `dets:foldl` in the FFI to avoid materializing all entries into memory.
/// Peak memory is ~1x (just the ETS table) instead of ~3x with the bulk approach.
/// Any entry that fails decoding causes the load to fail with `TypeMismatch`.
@internal
pub fn stream_validate_and_load(
  ets: EtsReference,
  dets: DetsReference,
  entry_decoder: Decoder(#(k, v)),
) -> Result(Nil, ShelfError) {
  let decoder_fn = fn(entry: Dynamic) -> Result(
    #(k, v),
    List(decode.DecodeError),
  ) {
    decode.run(entry, entry_decoder)
  }
  ffi_dets_fold_into_ets_strict(dets, ets, decoder_fn)
}

@external(erlang, "shelf_ffi", "dets_fold_into_ets_strict")
fn ffi_dets_fold_into_ets_strict(
  dets: DetsReference,
  ets: EtsReference,
  decoder_fn: fn(Dynamic) -> Result(#(k, v), List(decode.DecodeError)),
) -> Result(Nil, ShelfError)

// ── Generic table operations ────────────────────────────────────────────
// These eliminate duplication between set, bag, and duplicate_bag modules.

/// Generic open: validate path, create ETS+DETS, stream-load entries.
@internal
pub fn generic_open(
  config: Config,
  table_type: TableKind,
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Result(
  #(EtsReference, DetsReference, GuardianReference, WriteMode, Decoder(#(k, v))),
  ShelfError,
) {
  let name = shelf.get_name(config)
  let path = shelf.get_path(config)
  let base_directory = shelf.get_base_directory(config)
  let write_mode = shelf.get_write_mode(config)
  use resolved_path <- result.try(shelf.validate_path(path, base_directory))
  use references <- result.try(open_no_load(name, resolved_path, table_type))
  let ets = references.0
  let dets = references.1
  let guardian = references.2
  let entry_decoder = build_entry_decoder(key_decoder, value_decoder)
  case stream_validate_and_load(ets, dets, entry_decoder) {
    Ok(Nil) -> Ok(#(ets, dets, guardian, write_mode, entry_decoder))
    Error(e) -> {
      let _ = cleanup(ets, dets, guardian)
      Error(e)
    }
  }
}

/// Generic insert with write-through support.
/// In WriteThrough mode, DETS is written first so a DETS failure
/// never leaves ETS in a divergent state.
@internal
pub fn generic_insert(
  ets: EtsReference,
  dets: DetsReference,
  write_mode: WriteMode,
  key: k,
  value: v,
) -> Result(Nil, ShelfError) {
  case write_mode {
    shelf.WriteThrough -> {
      use _ <- result.try(dets_insert(dets, #(key, value)))
      insert(ets, dets, #(key, value))
    }
    shelf.WriteBack -> insert(ets, dets, #(key, value))
  }
}

/// Generic insert_list with write-through support.
@internal
pub fn generic_insert_list(
  ets: EtsReference,
  dets: DetsReference,
  write_mode: WriteMode,
  entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  case write_mode {
    shelf.WriteThrough -> {
      use _ <- result.try(dets_insert_list(dets, entries))
      insert_list(ets, dets, entries)
    }
    shelf.WriteBack -> insert_list(ets, dets, entries)
  }
}

/// Generic delete_key with write-through support.
@internal
pub fn generic_delete_key(
  ets: EtsReference,
  dets: DetsReference,
  write_mode: WriteMode,
  key: k,
) -> Result(Nil, ShelfError) {
  case write_mode {
    shelf.WriteThrough -> {
      use _ <- result.try(dets_delete_key(dets, key))
      delete_key(ets, key)
    }
    shelf.WriteBack -> delete_key(ets, key)
  }
}

/// Generic delete_object with write-through support.
@internal
pub fn generic_delete_object(
  ets: EtsReference,
  dets: DetsReference,
  write_mode: WriteMode,
  key: k,
  value: v,
) -> Result(Nil, ShelfError) {
  case write_mode {
    shelf.WriteThrough -> {
      use _ <- result.try(dets_delete_object(dets, key, value))
      delete_object(ets, key, value)
    }
    shelf.WriteBack -> delete_object(ets, key, value)
  }
}

/// Generic delete_all with write-through support.
@internal
pub fn generic_delete_all(
  ets: EtsReference,
  dets: DetsReference,
  write_mode: WriteMode,
) -> Result(Nil, ShelfError) {
  case write_mode {
    shelf.WriteThrough -> {
      use _ <- result.try(dets_delete_all(dets))
      delete_all(ets)
    }
    shelf.WriteBack -> delete_all(ets)
  }
}

/// Generic reload: load DETS into a scratch table first, swap on success.
/// On failure the live ETS table is untouched.
@internal
pub fn generic_reload(
  ets: EtsReference,
  dets: DetsReference,
  entry_decoder: Decoder(#(k, v)),
) -> Result(Nil, ShelfError) {
  let decoder_fn = fn(entry: Dynamic) -> Result(
    #(k, v),
    List(decode.DecodeError),
  ) {
    decode.run(entry, entry_decoder)
  }
  ffi_reload_atomic(ets, dets, decoder_fn)
}

@external(erlang, "shelf_ffi", "reload_atomic")
fn ffi_reload_atomic(
  ets: EtsReference,
  dets: DetsReference,
  decoder_fn: fn(Dynamic) -> Result(#(k, v), List(decode.DecodeError)),
) -> Result(Nil, ShelfError)

/// Shared with_table implementation: open, run callback (with panic rescue),
/// then close. Unlike explicit close, a scope cannot leave a retryable handle
/// behind: force cleanup on close failure, preserving the original error.
/// Preserves crash detail from the rescue FFI.
@internal
pub fn generic_with_table(
  open_fn: fn() -> Result(table, ShelfError),
  close_fn: fn(table) -> Result(Nil, ShelfError),
  cleanup_fn: fn(table) -> Result(Nil, ShelfError),
  fun: fn(table) -> Result(a, ShelfError),
) -> Result(a, ShelfError) {
  use table <- result.try(open_fn())
  let callback_result = case rescue(fn() { fun(table) }) {
    Ok(result) -> result
    Error(crash_detail) -> Error(shelf.ErlangError(crash_detail))
  }
  case close_fn(table) {
    Ok(Nil) -> callback_result
    Error(close_error) -> {
      // Cleanup checks the original ETS handle before touching DETS, so a
      // callback that closed and reopened the path cannot lose its new table.
      let _ = cleanup_fn(table)
      case callback_result {
        Ok(_) -> Error(close_error)
        Error(_) -> callback_result
      }
    }
  }
}

@external(erlang, "shelf_rescue_ffi", "rescue")
pub fn rescue(fun: fn() -> a) -> Result(a, String)

/// Generic fold with key-value destructuring.
@internal
pub fn generic_fold(
  ets: EtsReference,
  initial: acc,
  fun: fn(acc, k, v) -> acc,
) -> Result(acc, ShelfError) {
  let wrapper = fn(entry: #(k, v), acc: acc) -> acc {
    fun(acc, entry.0, entry.1)
  }
  fold(ets, wrapper, initial)
}

// ── Shared FFI bindings ─────────────────────────────────────────────────

@external(erlang, "shelf_ffi", "open_no_load")
@internal
pub fn open_no_load(
  name: String,
  path: String,
  table_type: TableKind,
) -> Result(#(EtsReference, DetsReference, GuardianReference), ShelfError)

@external(erlang, "shelf_ffi", "cleanup")
@internal
pub fn cleanup(
  ets: EtsReference,
  dets: DetsReference,
  guardian: GuardianReference,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "close")
@internal
pub fn close(
  ets: EtsReference,
  dets: DetsReference,
  guardian: GuardianReference,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert")
@internal
pub fn insert(
  ets: EtsReference,
  dets: DetsReference,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert_list")
@internal
pub fn insert_list(
  ets: EtsReference,
  dets: DetsReference,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "member")
@internal
pub fn member(ets: EtsReference, key: k) -> Result(Bool, ShelfError)

@external(erlang, "shelf_ffi", "to_list")
@internal
pub fn to_list(ets: EtsReference) -> Result(List(#(k, v)), ShelfError)

@external(erlang, "shelf_ffi", "fold")
@internal
pub fn fold(
  ets: EtsReference,
  fun: fn(#(k, v), acc) -> acc,
  acc: acc,
) -> Result(acc, ShelfError)

@external(erlang, "shelf_ffi", "size")
@internal
pub fn size(ets: EtsReference) -> Result(Int, ShelfError)

@external(erlang, "shelf_ffi", "delete_key")
@internal
pub fn delete_key(ets: EtsReference, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_object")
@internal
pub fn delete_object(
  ets: EtsReference,
  key: k,
  value: v,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_all")
@internal
pub fn delete_all(ets: EtsReference) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "save")
@internal
pub fn save(ets: EtsReference, dets: DetsReference) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "sync_dets")
@internal
pub fn sync_dets(
  ets: EtsReference,
  dets: DetsReference,
) -> Result(Nil, ShelfError)

// ── Targeted DETS operations (for WriteThrough mode) ────────────────────

@external(erlang, "shelf_ffi", "dets_insert")
@internal
pub fn dets_insert(
  dets: DetsReference,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_insert_list")
@internal
pub fn dets_insert_list(
  dets: DetsReference,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_key")
@internal
pub fn dets_delete_key(dets: DetsReference, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_object")
@internal
pub fn dets_delete_object(
  dets: DetsReference,
  key: k,
  value: v,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_all")
@internal
pub fn dets_delete_all(dets: DetsReference) -> Result(Nil, ShelfError)
