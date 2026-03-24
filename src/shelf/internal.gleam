/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references and shared logic used by
/// shelf table types.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import shelf.{type DecodePolicy, type ShelfError, Lenient, Strict}

/// Raw ETS table reference (Erlang tid).
@internal
pub type EtsRef

/// Raw DETS table reference (Erlang atom).
@internal
pub type DetsRef

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
/// Peak memory is ~1x (just the ETS table) instead of ~3x with the bulk approach
/// that first calls `dets_to_list` then decodes the full list.
///
/// Closes https://github.com/tylerbutler/shelf/issues/13
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

// ── Shared FFI bindings ─────────────────────────────────────────────────

@external(erlang, "shelf_ffi", "open_no_load")
@internal
pub fn open_no_load(
  name: String,
  path: String,
  table_type: String,
) -> Result(#(EtsRef, DetsRef), ShelfError)

@external(erlang, "shelf_ffi", "dets_to_list")
@internal
pub fn dets_to_list(dets: DetsRef) -> Result(List(Dynamic), ShelfError)

@external(erlang, "shelf_ffi", "cleanup")
@internal
pub fn cleanup(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "close")
@internal
pub fn close(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

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
