---
name: add-changelog-entry
description: Use when you've made code changes and need to add a changelog entry. Analyzes git diffs to create changie fragment YAML files in the correct format for this project.
---

<required>
*CRITICAL* Add the following steps to your Todo list using TodoWrite:

1. Analyze recent code changes using git diff
2. Determine the appropriate changelog kind(s) and draft entry body text
3. Confirm entries with the user before writing
4. Write changie fragment YAML files to `.changes/unreleased/`
5. Verify the created files are valid
</required>

# Overview

This skill creates changelog entries for the **shelf** project using [changie](https://changie.dev/). Instead of running the interactive `changie new` command, it writes fragment YAML files directly to `.changes/unreleased/`.

# Step-by-Step Process

## 1. Analyze recent code changes

Examine what has changed to determine what changelog entries are needed. Run:

```bash
# Check for staged changes first, fall back to unstaged, then recent commits
git --no-pager diff --cached --stat
git --no-pager diff --stat
git --no-pager log --oneline -5
```

Read the actual diffs to understand the nature of the changes:

```bash
git --no-pager diff --cached  # staged changes
git --no-pager diff           # unstaged changes
```

If no local changes are found, check the most recent commit(s) that don't have changelog entries yet.

## 2. Determine changelog kind(s) and draft entries

Classify each distinct change into one of the following kinds (defined in `.changie.yaml`):

| Kind           | When to use                                         | Version bump |
|----------------|-----------------------------------------------------|-------------|
| **Breaking**   | API changes that break existing usage                | minor (major after v1.0) |
| **Added**      | New features, new public functions, new types        | minor       |
| **Changed**    | Behavior changes to existing features                | patch       |
| **Deprecated** | Features marked for future removal                   | patch       |
| **Fixed**      | Bug fixes                                            | patch       |
| **Performance**| Performance improvements                             | patch       |
| **Removed**    | Removed features or public API                       | patch       |
| **Reverted**   | Reverted previous changes                            | patch       |
| **Dependencies** | Dependency version changes                         | patch       |
| **Security**   | Security-related fixes                               | patch       |

Draft a body for each entry. The body format is:

```
Short summary title on the first line
Optional longer description on subsequent lines explaining the change in more detail.
Multiple paragraphs are fine.
```

The first line becomes the `#####` heading in the rendered changelog. Keep it concise but descriptive.

**Writing guidelines:**
- Write from the **user's perspective** — what changed for them, not implementation details
- Use imperative mood for the title line (e.g., "Add X" not "Added X")
- If a change is breaking, explain what users need to update
- Reference PR numbers if available (e.g., `(#42)`)

## 3. Confirm entries with the user

Present the proposed entries and ask for confirmation before writing files. Show the kind, title, and body for each entry. Ask if any should be added, removed, or modified.

## 4. Write changie fragment YAML files

Write a Python script to create the fragment files. Each fragment is a YAML file in `.changes/unreleased/` with the naming convention `{Kind}-{YYYYMMDD}-{HHMMSS}.yaml`.

```python
#!/usr/bin/env python3
"""Create changie changelog fragment files."""
import os
from datetime import datetime

CHANGES_DIR = ".changes/unreleased"

def create_fragment(kind: str, body: str) -> str:
    """Create a changie fragment YAML file and return the file path."""
    now = datetime.now()
    timestamp = now.strftime("%Y%m%d-%H%M%S")
    filename = f"{kind}-{timestamp}.yaml"
    filepath = os.path.join(CHANGES_DIR, filename)

    # Format the timestamp in Go's reference time format (changie convention)
    # Example: 2026-03-22T21:32:46.808155106-07:00
    iso_time = now.astimezone().isoformat()

    content = f"""kind: {kind}
body: |-
{chr(10).join('    ' + line if line else '' for line in body.split(chr(10)))}
time: {iso_time}
"""
    with open(filepath, 'w') as f:
        f.write(content)

    return filepath

# Example usage:
# create_fragment("Fixed", "Fix resource leak on table close\nETS table was not deleted when close() encountered a DETS sync error.")
```

Write a script like the above, customized for the specific entries needed, and run it with `python3`.

**Important:** If creating multiple entries, space them at least 1 second apart or use unique timestamps to avoid filename collisions.

## 5. Verify the created files

After writing, verify the files:

```bash
# List new fragment files
ls -la .changes/unreleased/

# Show contents of newly created files
cat .changes/unreleased/{filename}.yaml

# Preview what the changelog will look like
changie batch auto --dry-run
```

Confirm the preview looks correct. If changie reports any errors, fix the YAML format.

# Reference: Fragment YAML Format

```yaml
kind: Added
body: |-
    Short summary title
    Optional longer description explaining the change.
time: 2026-03-22T21:32:46.808155106-07:00
```

- `kind`: Must exactly match one of the kinds in `.changie.yaml`
- `body`: Uses YAML block scalar (`|-`). First line is the title, rest is description. Each line indented 4 spaces.
- `time`: ISO 8601 timestamp with timezone offset
