import gleam/dynamic.{type Dynamic}

pub fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
pub fn delete_file(path: String) -> Result(Nil, Dynamic)
