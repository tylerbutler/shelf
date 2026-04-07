---
title: Quick Start
description: Get up and running with shelf in minutes.
---

:::caution[Pre-1.0 Software]
shelf is not yet 1.0. The API is unstable and features may be removed in minor releases.
:::

This guide walks you through basic persistent ETS operations with shelf.

## 1. Add shelf to your project

```bash
gleam add shelf
```

## 2. Open a persistent table

```gleam
import gleam/dynamic/decode
import shelf/set

pub fn main() {
  // Open a persistent set — loads existing data from disk
  let assert Ok(table) =
    set.open(name: "users", path: "data/users.dets", key: decode.string, value: decode.int)

  // Fast writes (to ETS)
  let assert Ok(Nil) = set.insert(table, "alice", 42)
  let assert Ok(Nil) = set.insert(table, "bob", 99)

  // Fast reads (from ETS)
  let assert Ok(42) = set.lookup(table, "alice")

  // Persist to disk when ready
  let assert Ok(Nil) = set.save(table)

  // Close auto-saves
  let assert Ok(Nil) = set.close(table)
}
```

On next startup, `set.open` automatically loads the saved data back into ETS. The decoders ensure that every entry loaded from disk matches the expected types — any corrupted or mistyped entries are caught at load time.

## Next steps

- Learn about [Set Tables](/guides/set-tables/) for unique key-value storage
- Use [Bag Tables](/guides/bag-tables/) for multiple values per key
- Configure [Write Modes](/guides/write-modes/) for your durability needs
- Understand [Persistence Operations](/advanced/persistence-operations/) like save, reload, and sync
