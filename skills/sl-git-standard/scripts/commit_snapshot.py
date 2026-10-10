# commit_snapshot.py — create / list / show / prune / index shallow-clone
# snapshots of the host project under .claude/repo/project/.
#
# One script, five subcommands:
#   snapshot  default. Shallow-clone <commit> (or HEAD) into
#             .claude/repo/project/<date>-<short_hash>/. Writes
#             .snapshot-meta.json per snapshot and appends to snapshots.json.
#   list      List snapshots with commit subject + date.
#   show      Print .snapshot-meta.json of a named snapshot.
#   prune     Keep the N most recent snapshots; delete the rest (default 10).
#   index     Generate PROJECT_INDEX.md / .json per snapshot.
#
# Cross-platform (Windows/Linux/Mac), replaces the former
# clone-snapshot.sh + clone-snapshot.ps1 + prune-snapshots.sh trio.
#
# NOTE: intentionally NO shebang. On Windows the py launcher resolves
# "#!/usr/bin/env python3" to the WindowsApps python3 stub, which exits
# silently with code 49. Always invoke via an explicit interpreter:
#   py  commit_snapshot.py          (Windows)
#   python3 commit_snapshot.py      (Linux/Mac)
#
# Root resolution: --root <path> > <cwd>/.claude > skill-anchored

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime
from pathlib import Path

META_PREFIX = (".",)
GLOBAL_INDEX = "snapshots.json"
META_FILE = ".snapshot-meta.json"


def parse_args():
    p = argparse.ArgumentParser(
        description="Create / list / show / prune / index commit snapshots "
                    "in .claude/repo/project/"
    )
    p.add_argument("command", nargs="?", default="snapshot",
                   choices=["snapshot", "list", "show", "prune", "index"],
                   help="snapshot (default): create; list/show/prune/index: manage")
    p.add_argument("arg", nargs="?",
                   help="snapshot: commit hash (default HEAD); show: snapshot name")
    p.add_argument("--root", type=Path, default=None,
                   help="explicit .claude base directory (must contain repo/); "
                        "default: <cwd>/.claude if it has repo/, "
                        "else the skill-anchored .claude")
    p.add_argument("--keep", type=int, default=10,
                   help="prune: keep N most recent snapshots (default 10)")
    return p.parse_args()


def resolve_root(explicit, skill_claude):
    """Pick the .claude base dir; returns (root, how_it_was_chosen)."""
    if explicit is not None:
        return explicit, "--root"
    cwd_claude = Path.cwd() / ".claude"
    if (cwd_claude / "repo").is_dir():
        return cwd_claude, "cwd"
    return skill_claude, "skill-anchored"


def run_git(args, cwd):
    return subprocess.run(
        ["git"] + args, cwd=cwd, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )


def get_origin(repo_dir):
    proc = run_git(["remote", "get-url", "origin"], cwd=repo_dir)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def get_commit_info(repo_root, commit):
    """Return (full_hash, author, email, timestamp, subject) or None."""
    target = commit or "HEAD"
    proc = run_git(["log", "-1", "--format=%H%n%an%n%ae%n%at%n%s", target],
                   cwd=repo_root)
    if proc.returncode != 0:
        return None
    lines = proc.stdout.strip().split("\n")
    if len(lines) < 5:
        return None
    try:
        return lines[0], lines[1], lines[2], int(lines[3]), lines[4]
    except ValueError:
        return None


def rmtree_force(path):
    """rmtree that survives Windows: .git object files are read-only, so
    chmod + retry on failure instead of crashing mid-prune."""
    def _onexc(func, p, exc):
        os.chmod(p, stat.S_IWRITE)
        func(p)
    try:
        shutil.rmtree(path, onexc=_onexc)   # Python 3.12+
    except TypeError:
        shutil.rmtree(path, onerror=lambda f, p, e: _onexc(f, p, None))


def load_state(root):
    """Return repo_dir = .claude/repo/project/ (created if missing)."""
    repo_dir = root / "repo" / "project"
    repo_dir.mkdir(parents=True, exist_ok=True)
    return repo_dir


def update_global_index(repo_dir, name, meta):
    index_file = repo_dir / GLOBAL_INDEX
    data = {"snapshots": []}
    if index_file.exists():
        try:
            data = json.loads(index_file.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or "snapshots" not in data:
                data = {"snapshots": []}
        except (json.JSONDecodeError, OSError):
            data = {"snapshots": []}
    data["snapshots"].append({"name": name, **meta})
    index_file.write_text(json.dumps(data, indent=2, ensure_ascii=False),
                          encoding="utf-8")


# ---------------------------------------------------------------- snapshot


def cmd_snapshot(root, repo_dir, commit):
    repo_root = root.parent
    info = get_commit_info(repo_root, commit)
    if not info:
        print(f"Error: cannot resolve commit {commit or 'HEAD'}", file=sys.stderr)
        return 2

    full_hash, author, email, ts, subject = info
    short_hash = full_hash[:7]
    date_str = datetime.fromtimestamp(ts).strftime("%Y-%m-%d")
    name = f"{date_str}-{short_hash}"
    target = repo_dir / name

    if target.exists():
        print(f"Snapshot already exists: {name}")
        return 0

    target.mkdir(parents=True, exist_ok=True)
    proc = run_git(["clone", "--depth=1", full_hash, str(target)],
                   cwd=repo_root)
    if proc.returncode != 0:
        rmtree_force(target)
        err = (proc.stderr or "").strip().splitlines()
        print(f"  FAILED: {err[-1] if err else 'git clone error'}", file=sys.stderr)
        return 1

    meta = {
        "commit": full_hash,
        "short_hash": short_hash,
        "author": author,
        "email": email,
        "timestamp": ts,
        "subject": subject,
        "remote_url": get_origin(repo_root),
        "created_at": datetime.now().isoformat(),
    }
    (target / META_FILE).write_text(
        json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    update_global_index(repo_dir, name, meta)
    print(f"OK: snapshot created: {name}")
    print(f"     {subject}")
    return 0


# ---------------------------------------------------------------- list


def cmd_list(root, repo_dir):
    snapshots = sorted(
        [d for d in repo_dir.iterdir()
         if d.is_dir() and not d.name.startswith(META_PREFIX)],
        key=lambda d: d.name,
        reverse=True,
    )
    if not snapshots:
        print("No snapshots yet.")
        return 0
    print(f"Found {len(snapshots)} snapshot(s):")
    for d in snapshots:
        meta_path = d / META_FILE
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                print(f"  {d.name}  (unreadable meta)")
                continue
            ts = meta.get("timestamp", 0)
            date = datetime.fromtimestamp(ts).strftime("%Y-%m-%d")
            subject = meta.get("subject", "(no subject)")
            print(f"  {d.name}  {date}  {subject[:60]}")
        else:
            print(f"  {d.name}  (no meta)")
    return 0


# ---------------------------------------------------------------- show


def cmd_show(root, repo_dir, name):
    if not name:
        print("Error: show requires a snapshot name", file=sys.stderr)
        return 2
    target = repo_dir / name
    meta_path = target / META_FILE
    if not meta_path.exists():
        print(f"Error: snapshot {name} not found", file=sys.stderr)
        return 2
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    print(f"=== Snapshot: {name} ===")
    for k, v in meta.items():
        print(f"  {k}: {v}")
    return 0


# ---------------------------------------------------------------- prune


def cmd_prune(root, repo_dir, keep):
    snapshots = sorted(
        [d for d in repo_dir.iterdir()
         if d.is_dir() and not d.name.startswith(META_PREFIX)],
        key=lambda d: d.name,
        reverse=True,
    )
    to_delete = snapshots[keep:]
    for d in to_delete:
        print(f"  deleting {d.name}")
        rmtree_force(d)
    if to_delete:
        print(f"Pruned {len(to_delete)} snapshot(s), "
              f"kept {min(keep, len(snapshots))}.")
    else:
        print(f"No pruning needed ({len(snapshots)} <= {keep}).")
    return 0


# ---------------------------------------------------------------- index


INDEX_SKIP = ("PROJECT_INDEX.md", "PROJECT_INDEX.json")


def cmd_index(root, repo_dir):
    count = 0
    for snapshot_dir in sorted(repo_dir.iterdir()):
        if not snapshot_dir.is_dir() or snapshot_dir.name.startswith(META_PREFIX):
            continue
        files = [
            p.relative_to(snapshot_dir)
            for p in snapshot_dir.rglob("*")
            if p.is_file() and p.name not in INDEX_SKIP
        ]

        json_path = snapshot_dir / "PROJECT_INDEX.json"
        md_path = snapshot_dir / "PROJECT_INDEX.md"
        json_path.write_text(
            json.dumps({"snapshot": snapshot_dir.name,
                        "files": [str(f) for f in files]},
                       indent=2, ensure_ascii=False),
            encoding="utf-8")
        md_lines = [f"# {snapshot_dir.name}", "",
                    f"Files: {len(files)}", "",
                    "## File list", ""]
        for f in sorted(files):
            md_lines.append(f"- `{f}`")
        md_path.write_text("\n".join(md_lines), encoding="utf-8")
        print(f"Indexed: {snapshot_dir.name} ({len(files)} files)")
        count += 1
    if count == 0:
        print("No snapshots to index.")
    return 0


# ---------------------------------------------------------------- main


def main():
    args = parse_args()

    skill_claude = Path(__file__).resolve().parents[3]
    if skill_claude.name != ".claude":
        # Installed somewhere unexpected; still usable via --root / cwd.
        skill_claude = None

    root, how = resolve_root(args.root, skill_claude)
    repo_dir = load_state(root)

    if args.command == "list":
        return cmd_list(root, repo_dir)
    if args.command == "show":
        return cmd_show(root, repo_dir, args.arg)
    if args.command == "prune":
        return cmd_prune(root, repo_dir, args.keep)
    if args.command == "index":
        return cmd_index(root, repo_dir)

    rc = cmd_snapshot(root, repo_dir, args.arg)
    if how == "skill-anchored":
        print("Note: resolved to skill-anchored .claude (not a project). "
              "Pass --root or run from a project directory.", file=sys.stderr)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # never let a crash masquerade as a clean exit
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)
