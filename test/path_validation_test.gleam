import shelf

pub fn relative_path_within_base_directory_works_test() {
  let assert Ok(_resolved) = shelf.validate_path("shelf_pv_valid.dets", "/tmp")
  Nil
}

pub fn absolute_path_within_base_directory_works_test() {
  let assert Ok(_resolved) =
    shelf.validate_path("/tmp/shelf_pv_valid_abs.dets", "/tmp")
  Nil
}

pub fn path_traversal_is_rejected_test() {
  let result = shelf.validate_path("../etc/passwd", "/tmp")
  case result {
    Error(shelf.InvalidPath(_)) -> Nil
    other -> {
      let assert True = other == Error(shelf.InvalidPath("expected"))
      Nil
    }
  }
}

pub fn null_bytes_in_path_are_rejected_test() {
  let result = shelf.validate_path("shelf_pv\u{0}bad.dets", "/tmp")
  case result {
    Error(shelf.InvalidPath(_)) -> Nil
    other -> {
      let assert True = other == Error(shelf.InvalidPath("expected"))
      Nil
    }
  }
}

pub fn nested_subdirectory_works_test() {
  let assert Ok(_resolved) =
    shelf.validate_path("sub/dir/shelf_pv_nested.dets", "/tmp")
  Nil
}

pub fn sibling_directory_with_shared_prefix_is_rejected_test() {
  // "/tmp/data" should NOT match "/tmp/data_sibling/evil.dets"
  let result = shelf.validate_path("/tmp/data_sibling/evil.dets", "/tmp/data")
  case result {
    Error(shelf.InvalidPath(_)) -> Nil
    other -> {
      let assert True = other == Error(shelf.InvalidPath("expected"))
      Nil
    }
  }
}
