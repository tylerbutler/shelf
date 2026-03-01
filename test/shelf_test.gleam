import shelf
import startest
import startest/expect

pub fn main() {
  startest.run(startest.default_config())
}

// Verify the config builder works
pub fn config_defaults_test() {
  let config = shelf.config(name: "test", path: "test.dets")
  expect.to_equal(config.name, "test")
  expect.to_equal(config.path, "test.dets")
  expect.to_equal(config.write_mode, shelf.WriteBack)
}

pub fn config_write_mode_test() {
  let config =
    shelf.config(name: "test", path: "test.dets")
    |> shelf.write_mode(shelf.WriteThrough)
  expect.to_equal(config.write_mode, shelf.WriteThrough)
}
