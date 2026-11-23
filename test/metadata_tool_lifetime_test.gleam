import gleam/dynamic/decode
import shelf
import shelf/set
import storage_safety_test
import unitest

@external(erlang, "save_metadata_test_ffi", "is_macos")
fn is_macos() -> Bool

@external(erlang, "metadata_instrumentation_test_ffi", "has_apple_timeout")
fn has_apple_timeout() -> Bool

@external(erlang, "metadata_instrumentation_test_ffi", "has_gnu_timeout")
fn has_gnu_timeout() -> Bool

@external(erlang, "metadata_instrumentation_test_ffi", "timed_writer")
fn timed_writer(
  directory: String,
  open: fn() -> Result(set.PersistentSet(String, Int), shelf.ShelfError),
  gnu: Bool,
) -> Nil

fn exercise(gnu: Bool) -> Nil {
  use directory <- storage_safety_test.with_directory()
  timed_writer(
    directory,
    fn() {
      set.open_config(
        shelf.config("tool_lifetime", "table.dets", base_directory: directory),
        decode.string,
        decode.int,
      )
    },
    gnu,
  )
}

pub fn apple_timeout_reaps_writer_before_dead_owner_guardian_cleans_test() -> Nil {
  use <- unitest.tag("save_metadata")
  use <- unitest.guard(is_macos() && has_apple_timeout())
  exercise(False)
}

pub fn gnu_timeout_reaps_writer_before_dead_owner_guardian_cleans_test() -> Nil {
  use <- unitest.tag("save_metadata")
  use <- unitest.guard(is_macos() && has_gnu_timeout())
  exercise(True)
}
