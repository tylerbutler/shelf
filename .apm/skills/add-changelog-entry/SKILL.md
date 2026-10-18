---
name: add-changelog-entry
description: Use when code changes need a user-facing changelog entry. Analyze git diffs and create trellis TOML fragments for shelf. Skip development-only changes.
---

# Add a changelog entry

## Inspect the changes

Read the staged and unstaged diffs. If neither contains changes, inspect the
relevant recent commits.

```sh
git --no-pager diff --cached
git --no-pager diff
git --no-pager log --oneline -5
```

Add entries only for user-facing changes. Do not add entries for changes
limited to development tools, CI, tests, or refactoring without a behavior change.
Check `.changes/unreleased/` for an entry that already covers the change.

## Draft and confirm

Read `[tools.trellis.changelog]` in `gleam.toml` for the configured kinds and
version bumps. Use one entry per distinct change.

Write a short imperative summary on the first line. Add details on later
lines when users need them. Explain how to update callers for a breaking
change, and include a PR reference when available.

Show the proposed kind and body to the user and ask for confirmation before
writing a new entry.

## Create the fragment

Use trellis to create the fragment with a unique filename:

```sh
trellis changelog new --package shelf --kind Fixed \
  --body "Fix resource cleanup after a failed save"
```

The Just interface accepts the same kind and body:

```sh
just change Fixed "Fix resource cleanup after a failed save"
```

Trellis writes a TOML file in `.changes/unreleased/`:

```toml
package = "shelf"
kind = "Fixed"
body = "Fix resource cleanup after a failed save"
```

Use safe shell argument quoting for entry text. For a multiline body, use a
quoted heredoc or a TOML multiline string. Keep the package name `shelf`;
the examples do not release.

## Verify

Read the new fragment, then run:

```sh
trellis doctor
trellis version plan
```

Fix parsing errors or unknown kinds before finishing. Do not run
`trellis version apply` or edit the generated `CHANGELOG.md` when adding
an entry; the release workflow handles batching and version bumps.
