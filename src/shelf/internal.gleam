/// Internal module — not part of the public API.
///
/// Holds the raw ETS and DETS references used by shelf table types.
/// Raw ETS table reference (Erlang tid).
pub type EtsRef

/// Raw DETS table reference (Erlang atom).
pub type DetsRef

/// A pair of ETS + DETS references returned by the FFI open functions.
pub type TableRefs {
  TableRefs(ets: EtsRef, dets: DetsRef)
}
