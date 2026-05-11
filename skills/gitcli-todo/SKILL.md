---
name: gitcli-todo
description: Use when tracking git tag progress as a todo list, querying commits between tags, marking tags as done, or managing cursor-based workflows across git repositories.
---

# GitCLI Todo - Git Tag Cursor Tool

## Overview

`tagcli` (gittags) is a CLI tool that treats git tags as a todo/checklist system. It tracks progress by marking tags as done via a cursor file, allowing you to query remaining tags and their associated commits.

## Quick Reference

| Command | Description |
|---------|-------------|
| `tagcli query -n <N>` | Show next N undoned tags with commits |
| `tagcli ack <tag>` | Mark a tag as done |
| `tagcli status` | Show all tags with done/pending status |
| `tagcli reset` | Clear all done marks |
| `tagcli init` | Initialize cursor file |

## Workflow

1. Run `tagcli query -n 5` to see next 5 pending tags and their commits
2. Review the commits to understand what changed
3. Run `tagcli ack <tag>` to mark a tag as completed
4. Next query automatically skips done tags

## Cursor File

- Location: `.gittags-cursor` in the executable's directory
- Format: One tag name per line
- Each installation has its own cursor (useful for different projects)

## Output Format

```
docker/execd/1.0.0 [pending] 2025-12-17
─────────────────────────────────
  a7a92daa feat(workflow): add components/execd test workflow
  cb8e9ac2 chore(github): fix github issue template config

docker/code-interpreter/1.0.0 [pending] 2025-12-17
─────────────────────────────────
  ...

[Showing 3/105 undoned tags]
```

## Example Use Case

```bash
# See what needs review
tagcli query -n 3

# Mark one as reviewed/approved
tagcli ack docker/code-interpreter/1.0.0

# Continue - will show next 3 undoned
tagcli query -n 3

# See overall progress
tagcli status
```

## Build from Source

```bash
cd lab/gittags
go build -o tagcli.exe .
```

## Key Behavior

- Tags sorted by creation date (earliest first)
- `query -n N` returns N undoned tags, skipping already-done ones
- Each tag shows commits since the previous tag
- No network calls - all local git operations
