import shelf
import startest.{describe, it}
import startest/expect

pub fn path_validation_tests() {
  describe("path validation", [
    it("relative path within base_directory works", fn() {
      let assert Ok(_resolved) =
        shelf.validate_path("shelf_pv_valid.dets", "/tmp")
      Nil
    }),
    it("absolute path within base_directory works", fn() {
      let assert Ok(_resolved) =
        shelf.validate_path("/tmp/shelf_pv_valid_abs.dets", "/tmp")
      Nil
    }),
    it("path traversal is rejected", fn() {
      let result = shelf.validate_path("../etc/passwd", "/tmp")
      case result {
        Error(shelf.InvalidPath(_)) -> Nil
        other -> {
          expect.to_equal(other, Error(shelf.InvalidPath("expected")))
          Nil
        }
      }
    }),
    it("null bytes in path are rejected", fn() {
      let result = shelf.validate_path("shelf_pv\u{0}bad.dets", "/tmp")
      case result {
        Error(shelf.InvalidPath(_)) -> Nil
        other -> {
          expect.to_equal(other, Error(shelf.InvalidPath("expected")))
          Nil
        }
      }
    }),
    it("nested subdirectory works", fn() {
      let assert Ok(_resolved) =
        shelf.validate_path("sub/dir/shelf_pv_nested.dets", "/tmp")
      Nil
    }),
  ])
}
