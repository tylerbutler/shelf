import shelf
import unitest

pub fn main() {
  unitest.main()
}

pub fn config_defaults_test() {
  // Just verify the builder works — Config is now opaque
  let _config =
    shelf.config(name: "test", path: "test.dets", base_directory: "/tmp")
  Nil
}

pub fn config_write_mode_test() {
  let _config =
    shelf.config(name: "test", path: "test.dets", base_directory: "/tmp")
    |> shelf.write_mode(shelf.WriteThrough)
  Nil
}
