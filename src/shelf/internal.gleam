/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references and shared logic used by
/// shelf table types.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import shelf.{
  type Config, type DecodePolicy, type ShelfError, type WriteMode, Lenient,
  Strict,
}

/// Raw ETS table reference (Erlang tid).
@internal
pub type EtsRef

/// Raw DETS table reference (Erlang atom).
@internal
pub type DetsRef

/// Guardian process PID — monitors the owner and cleans up DETS on crash.
@internal
pub type GuardianRef

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
@internal
pub fn stream_validate_and_load(
  ets: EtsRef,
  dets: DetsRef,
  entry_decoder: Decoder(#(k, v)),
  policy: DecodePolicy,
) -> Result(Nil, ShelfError) {
  let decoder_fn = fn(entry: Dynamic) -> Result(
    #(k, v),
    List(decode.DecodeError),
  ) {
    decode.run(entry, entry_decoder)
  }
  case policy {
    Strict -> ffi_dets_fold_into_ets_strict(dets, ets, decoder_fn)
    Lenient -> ffi_dets_fold_into_ets_lenient(dets, ets, decoder_fn)
  }
}

@external(erlang, "shelf_ffi", "dets_fold_into_ets_strict")
fn ffi_dets_fold_into_ets_strict(
  dets: DetsRef,
  ets: EtsRef,
  decoder_fn: fn(Dynamic) -> Result(#(k, v), List(decode.DecodeError)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_fold_into_ets_lenient")
fn ffi_dets_fold_into_ets_lenient(
  dets: DetsRef,
  ets: EtsRef,
  decoder_fn: fn(Dynamic) -> Result(#(k, v), List(decode.DecodeError)),
) -> Result(Nil, ShelfError)

// ── Generic table operations ────────────────────────────────────────────
// These eliminate duplication between set, bag, and duplicate_bag modules.

/// Generic open: validate path, create ETS+DETS, stream-load entries.
@internal
pub fn generic_open(
  config: Config,
  table_type: String,
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Result(
  #(EtsRef, DetsRef, GuardianRef, WriteMode, Decoder(#(k, v)), DecodePolicy),
  ShelfError,
) {
  let name = shelf.get_name(config)
  let path = shelf.get_path(config)
  let base_directory = shelf.get_base_directory(config)
  let write_mode = shelf.get_write_mode(config)
  let decode_policy = shelf.get_decode_policy(config)
  use resolved_path <- result.try(shelf.validate_path(path, base_directory))
  use refs <- result.try(open_no_load(name, resolved_path, table_type))
  let ets = refs.0
  let dets = refs.1
  let guardian = refs.2
  let entry_decoder = build_entry_decoder(key_decoder, value_decoder)
  case stream_validate_and_load(ets, dets, entry_decoder, decode_policy) {
    Ok(Nil) ->
      Ok(#(ets, dets, guardian, write_mode, entry_decoder, decode_policy))
    Error(e) -> {
      let _ = cleanup(ets, dets, guardian)
      Error(e)
    }
  }
}

/// Generic insert with write-through support.
@internal
pub fn generic_insert(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
  key: k,
  value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(insert(ets, dets, #(key, value)))
  case write_mode {
    shelf.WriteThrough -> dets_insert(dets, #(key, value))
    shelf.WriteBack -> Ok(Nil)
  }
}

/// Generic insert_list with write-through support.
@internal
pub fn generic_insert_list(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
  entries: List(#(k, v)),
) -> Result(Nil, ShelfError) {
  use _ <- result.try(insert_list(ets, dets, entries))
  case write_mode {
    shelf.WriteThrough -> dets_insert_list(dets, entries)
    shelf.WriteBack -> Ok(Nil)
  }
}

/// Generic delete_key with write-through support.
@internal
pub fn generic_delete_key(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
  key: k,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(delete_key(ets, key))
  case write_mode {
    shelf.WriteThrough -> dets_delete_key(dets, key)
    shelf.WriteBack -> Ok(Nil)
  }
}

/// Generic delete_object with write-through support.
@internal
pub fn generic_delete_object(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
  key: k,
  value: v,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(delete_object(ets, key, value))
  case write_mode {
    shelf.WriteThrough -> dets_delete_object(dets, key, value)
    shelf.WriteBack -> Ok(Nil)
  }
}

/// Generic delete_all with write-through support.
@internal
pub fn generic_delete_all(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(delete_all(ets))
  case write_mode {
    shelf.WriteThrough -> dets_delete_all(dets)
    shelf.WriteBack -> Ok(Nil)
  }
}

/// Generic reload: clear ETS and stream-load from DETS.
@internal
pub fn generic_reload(
  ets: EtsRef,
  dets: DetsRef,
  entry_decoder: Decoder(#(k, v)),
  decode_policy: DecodePolicy,
) -> Result(Nil, ShelfError) {
  use _ <- result.try(delete_all(ets))
  stream_validate_and_load(ets, dets, entry_decoder, decode_policy)
}

/// Generic fold with key-value destructuring.
@internal
pub fn generic_fold(
  ets: EtsRef,
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
  table_type: String,
) -> Result(#(EtsRef, DetsRef, GuardianRef), ShelfError)

@external(erlang, "shelf_ffi", "dets_to_list")
@internal
pub fn dets_to_list(dets: DetsRef) -> Result(List(Dynamic), ShelfError)

@external(erlang, "shelf_ffi", "cleanup")
@internal
pub fn cleanup(
  ets: EtsRef,
  dets: DetsRef,
  guardian: GuardianRef,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "close")
@internal
pub fn close(
  ets: EtsRef,
  dets: DetsRef,
  guardian: GuardianRef,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert")
@internal
pub fn insert(
  ets: EtsRef,
  dets: DetsRef,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert_list")
@internal
pub fn insert_list(
  ets: EtsRef,
  dets: DetsRef,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "member")
@internal
pub fn member(ets: EtsRef, key: k) -> Result(Bool, ShelfError)

@external(erlang, "shelf_ffi", "to_list")
@internal
pub fn to_list(ets: EtsRef) -> Result(List(#(k, v)), ShelfError)

@external(erlang, "shelf_ffi", "fold")
@internal
pub fn fold(
  ets: EtsRef,
  fun: fn(#(k, v), acc) -> acc,
  acc: acc,
) -> Result(acc, ShelfError)

@external(erlang, "shelf_ffi", "size")
@internal
pub fn size(ets: EtsRef) -> Result(Int, ShelfError)

@external(erlang, "shelf_ffi", "delete_key")
@internal
pub fn delete_key(ets: EtsRef, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_object")
@internal
pub fn delete_object(ets: EtsRef, key: k, value: v) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_all")
@internal
pub fn delete_all(ets: EtsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "save")
@internal
pub fn save(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "sync_dets")
@internal
pub fn sync_dets(dets: DetsRef) -> Result(Nil, ShelfError)

// ── Targeted DETS operations (for WriteThrough mode) ────────────────────

@external(erlang, "shelf_ffi", "dets_insert")
@internal
pub fn dets_insert(dets: DetsRef, object: #(k, v)) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_insert_list")
@internal
pub fn dets_insert_list(
  dets: DetsRef,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_key")
@internal
pub fn dets_delete_key(dets: DetsRef, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_object")
@internal
pub fn dets_delete_object(
  dets: DetsRef,
  key: k,
  value: v,
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "dets_delete_all")
@internal
pub fn dets_delete_all(dets: DetsRef) -> Result(Nil, ShelfError)
