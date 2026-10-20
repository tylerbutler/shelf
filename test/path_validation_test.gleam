import gleam/dynamic/decode
import gleam/string
import shelf
import shelf/set
import storage_safety_test as fixture

pub fn relative_path_within_base_directory_works_test() -> Nil {
  let assert Ok(_resolved) = shelf.validate_path("shelf_pv_valid.dets", "/tmp")
  Nil
}

pub fn absolute_path_within_base_directory_works_test() -> Nil {
  let assert Ok(_resolved) =
    shelf.validate_path("/tmp/shelf_pv_valid_abs.dets", "/tmp")
  Nil
}

pub fn path_traversal_is_rejected_test() -> Nil {
  let result = shelf.validate_path("../etc/passwd", "/tmp")
  let assert Error(shelf.InvalidPath(_)) = result
  Nil
}

pub fn null_bytes_in_path_are_rejected_test() -> Nil {
  let result = shelf.validate_path("shelf_pv\u{0}bad.dets", "/tmp")
  let assert Error(shelf.InvalidPath(_)) = result
  Nil
}

pub fn nested_subdirectory_works_test() -> Nil {
  let assert Ok(_resolved) =
    shelf.validate_path("sub/dir/shelf_pv_nested.dets", "/tmp")
  Nil
}

pub fn sibling_directory_with_shared_prefix_is_rejected_test() -> Nil {
  // "/tmp/data" should NOT match "/tmp/data_sibling/evil.dets"
  let result = shelf.validate_path("/tmp/data_sibling/evil.dets", "/tmp/data")
  let assert Error(shelf.InvalidPath(_)) = result
  Nil
}

pub fn filesystem_root_accepts_absolute_and_relative_descendants_test() -> Nil {
  assert shelf.validate_path("/tmp/root.dets", "/") == Ok("/tmp/root.dets")
  assert shelf.validate_path("tmp/root.dets", "/") == Ok("/tmp/root.dets")
  assert shelf.validate_path("/../../tmp/root.dets", "/")
    == Ok("/tmp/root.dets")
}

pub fn filesystem_root_opens_absolute_and_relative_descendants_test() -> Nil {
  use directory <- fixture.with_directory()
  let path = directory <> "/root.dets"
  let assert Ok(table) = set.open("root", path, "/", decode.string, decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(table) =
    set.open("root", string.drop_start(path, 1), "/", decode.string, decode.int)
  assert set.lookup(table, "key") == Ok(1)
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn intermediate_symlink_escape_is_rejected_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/base"
  fixture.make_directory(base)
  fixture.make_directory(directory <> "/outside")
  fixture.symlink("../outside", base <> "/alias")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("alias/table.dets", base)
  let assert Error(shelf.InvalidPath(_)) =
    set.open("escape", "alias/table.dets", base, decode.string, decode.int)
  assert fixture.list_directory(directory <> "/outside") == []
}

pub fn leaf_symlink_escape_is_rejected_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/base"
  fixture.make_directory(base)
  fixture.write_file(directory <> "/outside.dets", "untouched")
  fixture.symlink("../outside.dets", base <> "/table.dets")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("table.dets", base)
  let assert Error(shelf.InvalidPath(_)) =
    set.open("escape", "table.dets", base, decode.string, decode.int)
  assert fixture.read_file(directory <> "/outside.dets") == <<"untouched":utf8>>
}

pub fn in_base_aliases_resolve_canonically_and_conflict_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/base"
  fixture.make_directory(base)
  fixture.make_directory(base <> "/real")
  fixture.symlink("real", base <> "/alias")
  fixture.symlink("base", directory <> "/base_alias")
  let path = base <> "/real/table.dets"
  let assert Ok(table) =
    set.open("real", "real/table.dets", base, decode.string, decode.int)
  fixture.symlink("real/table.dets", base <> "/leaf.dets")
  assert shelf.validate_path("alias/table.dets", base) == Ok(path)
  assert shelf.validate_path("leaf.dets", base) == Ok(path)
  assert shelf.validate_path("alias/table.dets", directory <> "/base_alias")
    == Ok(path)
  let assert Error(shelf.NameConflict) =
    set.open("alias", "alias/table.dets", base, decode.string, decode.int)
  let assert Error(shelf.NameConflict) =
    set.open("leaf", "leaf.dets", base, decode.string, decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) =
    set.open("alias", "leaf.dets", base, decode.string, decode.int)
  assert set.lookup(reopened, "key") == Ok(1)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn symbolic_link_loops_return_invalid_path_test() -> Nil {
  use directory <- fixture.with_directory()
  fixture.symlink("second", directory <> "/first")
  fixture.symlink("first", directory <> "/second")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("first/table.dets", directory)
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("first", directory)
  Nil
}

pub fn parent_segments_are_resolved_after_symbolic_links_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/base"
  fixture.make_directory(base)
  fixture.make_directory(base <> "/nested")
  fixture.symlink("nested", base <> "/alias")
  assert shelf.validate_path("alias/../table.dets", base)
    == Ok(base <> "/table.dets")
  // Lexical removal of alias/.. would miss this escape.
  fixture.symlink(directory, base <> "/outside")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("outside/../table.dets", base)
  Nil
}

pub fn missing_symlink_target_is_canonical_but_open_requires_parent_test() -> Nil {
  use directory <- fixture.with_directory()
  fixture.symlink("missing", directory <> "/alias")
  assert shelf.validate_path("alias/table.dets", directory)
    == Ok(directory <> "/missing/table.dets")
  let assert Error(shelf.FileError(_)) =
    set.open(
      "missing",
      "alias/table.dets",
      directory,
      decode.string,
      decode.int,
    )
  Nil
}

pub fn non_directory_intermediate_component_is_rejected_test() -> Nil {
  use directory <- fixture.with_directory()
  fixture.write_file(directory <> "/file", "not a directory")
  let assert Error(shelf.InvalidPath(_)) =
    shelf.validate_path("file/../table.dets", directory)
  Nil
}

pub fn unicode_directory_and_filename_survive_save_close_reopen_test() -> Nil {
  use directory <- fixture.with_directory()
  let base = directory <> "/données-日本"
  let filename = "café-雪.dets"
  let path = base <> "/" <> filename
  fixture.make_directory(base)
  assert shelf.validate_path(filename, base) == Ok(path)
  let assert Ok(table) =
    set.open("unicode", filename, base, decode.string, decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.save(table)
  assert fixture.list_directory(base) == [filename]
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) =
    set.open("unicode", path, base, decode.string, decode.int)
  assert set.lookup(reopened, "key") == Ok(42)
  let assert Ok(Nil) = set.close(reopened)
  assert fixture.list_directory(directory) == ["données-日本"]
  assert fixture.list_directory(base) == [filename]
}
