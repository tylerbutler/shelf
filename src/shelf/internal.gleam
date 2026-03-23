/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references and shared logic used by
/// shelf table types.
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/result
import shelf.{
  type DecodePolicy, type ShelfError, type WriteMode, Lenient, Strict, WriteBack,
  WriteThrough,
}

/// Raw ETS table reference (Erlang tid).
pub type EtsRef

/// Raw DETS table reference (Erlang atom).
pub type DetsRef

// ── Shared helpers ──────────────────────────────────────────────────────

/// Compose key and value decoders into a tuple entry decoder.
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
        Error(_) -> Error(shelf.TypeMismatch)
      }
  }
}

/// If in WriteThrough mode, save ETS to DETS.
pub fn maybe_write_through(
  ets: EtsRef,
  dets: DetsRef,
  write_mode: WriteMode,
) -> Result(Nil, ShelfError) {
  case write_mode {
    WriteThrough -> save(ets, dets)
    WriteBack -> Ok(Nil)
  }
}

// ── Shared FFI bindings ─────────────────────────────────────────────────

@external(erlang, "shelf_ffi", "open_no_load")
pub fn open_no_load(
  name: String,
  path: String,
  table_type: String,
) -> Result(#(EtsRef, DetsRef), ShelfError)

@external(erlang, "shelf_ffi", "dets_to_list")
pub fn dets_to_list(dets: DetsRef) -> Result(List(Dynamic), ShelfError)

@external(erlang, "shelf_ffi", "cleanup")
pub fn cleanup(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "close")
pub fn close(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert")
pub fn insert(
  ets: EtsRef,
  dets: DetsRef,
  object: #(k, v),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "insert_list")
pub fn insert_list(
  ets: EtsRef,
  dets: DetsRef,
  objects: List(#(k, v)),
) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "member")
pub fn member(ets: EtsRef, key: k) -> Result(Bool, ShelfError)

@external(erlang, "shelf_ffi", "to_list")
pub fn to_list(ets: EtsRef) -> Result(List(#(k, v)), ShelfError)

@external(erlang, "shelf_ffi", "fold")
pub fn fold(
  ets: EtsRef,
  fun: fn(#(k, v), acc) -> acc,
  acc: acc,
) -> Result(acc, ShelfError)

@external(erlang, "shelf_ffi", "size")
pub fn size(ets: EtsRef) -> Result(Int, ShelfError)

@external(erlang, "shelf_ffi", "delete_key")
pub fn delete_key(ets: EtsRef, key: k) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_object")
pub fn delete_object(ets: EtsRef, key: k, value: v) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "delete_all")
pub fn delete_all(ets: EtsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "save")
pub fn save(ets: EtsRef, dets: DetsRef) -> Result(Nil, ShelfError)

@external(erlang, "shelf_ffi", "sync_dets")
pub fn sync_dets(dets: DetsRef) -> Result(Nil, ShelfError)
