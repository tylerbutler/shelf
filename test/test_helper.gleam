import gleam/erlang/process.{type Monitor, type Pid}

pub type DeleteError {
  FileNotFound
  FileDeleteFailed(String)
}

pub fn cleanup(path: String) -> Nil {
  case delete_file(path) {
    Ok(Nil) | Error(FileNotFound) -> Nil
    Error(FileDeleteFailed(detail)) -> {
      let message = "Failed to clean up " <> path <> ": " <> detail
      panic as message
    }
  }
}

@external(erlang, "close_test_ffi", "delete_file")
pub fn delete_file(path: String) -> Result(Nil, DeleteError)

/// Wait only for this guardian's DOWN message, flushing the monitor on timeout.
pub fn await_guardian(monitor: Monitor, guardian: Pid) -> Nil {
  let result =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 1000)
  process.demonitor_process(monitor)
  let assert Ok(process.ProcessDown(stopped_monitor, stopped, _)) = result
  assert stopped_monitor == monitor
  assert stopped == guardian
}

@external(erlang, "close_test_ffi", "create_directory")
pub fn create_directory(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_read_only")
pub fn make_directory_read_only(path: String) -> Nil

@external(erlang, "close_test_ffi", "make_directory_writable")
pub fn make_directory_writable(path: String) -> Nil

@external(erlang, "close_test_ffi", "delete_directory")
pub fn delete_directory(path: String) -> Nil

pub fn prepare_retry_directory(directory: String, path: String) -> Nil {
  make_directory_writable(directory)
  cleanup(path)
  delete_directory(directory)
  create_directory(directory)
  Nil
}

pub fn cleanup_retry_directory(directory: String, path: String) -> Nil {
  make_directory_writable(directory)
  cleanup(path)
  delete_directory(directory)
  Nil
}
