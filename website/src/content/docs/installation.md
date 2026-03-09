---
title: Installation
description: How to install shelf in your Gleam project.
---

:::caution[Pre-1.0 Software]
shelf is not yet 1.0. The API is unstable and features may be removed in minor releases.
:::

Add shelf to your Gleam project:

```bash
gleam add shelf
```

This adds shelf to your `gleam.toml` dependencies. shelf targets the **Erlang (BEAM)** runtime — it does not support the JavaScript target.

## Requirements

- **Gleam** >= 1.7.0
- **Erlang/OTP** >= 26 (recommended: 27+)
- **Target**: Erlang only

## Dependencies

shelf brings in these Gleam packages automatically:

| Package | Purpose |
|---------|---------|
| `gleam_stdlib` | Standard library |
| `gleam_erlang` | Erlang interop |
