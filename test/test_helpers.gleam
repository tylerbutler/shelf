import gleam/dynamic.{type Dynamic}

pub fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
pub fn delete_file(path: String) -> Result(Nil, Dynamic)

@external(erlang, "close_test_ffi", "create_directory")
pub fn create_directory(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_read_only")
pub fn make_directory_read_only(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_writable")
pub fn make_directory_writable(path: String) -> Nil

@external(erlang, "close_test_ffi", "delete_directory")
pub fn delete_directory(path: String) -> Nil

pub fn prepare_retry_directory(dir: String, path: String) {
  make_directory_writable(dir)
  cleanup(path)
  delete_directory(dir)
  create_directory(dir)
  Nil
}

pub fn cleanup_retry_directory(dir: String, path: String) {
  make_directory_writable(dir)
  cleanup(path)
  delete_directory(dir)
  Nil
}
