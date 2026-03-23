/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references and shared logic used by
/// shelf table types.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/result
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

/// Validate raw DETS entries through the decoder and batch-insert into ETS.
///
/// **Performance note**: this materializes all DETS entries into a Gleam list
/// before decoding and inserting into ETS. Peak memory is ~3x the DETS
/// contents (the raw list + the decoded pairs + the ETS table). This works
/// well for tables under
/// ~50K entries; for larger tables or large values, memory pressure may be
/// significant. See https://github.com/tylerbutler/shelf/issues/13 for a
/// planned streaming approach using `dets:foldl` directly in the FFI.
///
@internal
pub fn validate_and_load(
  entries: List(Dynamic),
  ets: EtsRef,
  dets: DetsRef,
  entry_decoder: Decoder(#(k, v)),
  policy: DecodePolicy,
) -> Result(Nil, ShelfError) {
  case policy {
    Strict -> {
      use pairs <- result.try(decode_all_strict(entries, entry_decoder, []))
      insert_list(ets, dets, pairs)
    }
    Lenient -> {
      let pairs =
        list.filter_map(entries, fn(entry) { decode.run(entry, entry_decoder) })
      insert_list(ets, dets, list.reverse(pairs))
    }
  }
}

fn decode_all_strict(
  entries: List(Dynamic),
  decoder: Decoder(#(k, v)),
  acc: List(#(k, v)),
) -> Result(List(#(k, v)), ShelfError) {
  case entries {
    [] -> Ok(list.reverse(acc))
    [entry, ..rest] ->
      case decode.run(entry, decoder) {
        Ok(pair) -> decode_all_strict(rest, decoder, [pair, ..acc])
        Error(errors) -> Error(shelf.TypeMismatch(errors))
      }
  }
}

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
