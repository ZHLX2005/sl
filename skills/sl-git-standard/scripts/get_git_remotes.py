# get_git_remotes.py — keep the git.remote manifest and .claude/repo/ in sync.
#
# One script, three subcommands (extract is the classic mode; check/sync add
# diff-preview and convergence on top of it):
#
#   check    default. Read-only diff preview between www/git.remote (manifest)
#            and repo/ on disk. Prints +missing / -stale / !conflict lines and
#            the action sync would take. Exit 0 = consistent, 1 = drift, 2 = error.
#   extract  scan repo/ for nested git repos, append their origin URLs to
#            www/git.remote (auto-dedup keeps history). -f resets the file.
#   sync     converge both ways: extract, then clone missing repos, optionally
#            --prune stale dirs, --update fast-forward existing clones.
#
# Consistency rules:
#   - Manifest lines and tracked clones use the SAME shareable-URL predicate
#     (git@ / https:// / http:// / file://). Clones whose origin is a bare
#     local path are machine-local assets: extract skips them, check/sync
#     never compare or prune them.
#   - The host project itself (origin of root.parent) is never a reference
#     repo: sync will not clone a project into its own .claude/repo/.
#   - Dir names starting with "_" or "." are meta dirs (_read/_self/...),
#     never reference repos.
#
# Root resolution (for <root>/repo and <root>/www/git.remote), first match wins:
#   1. --root <path>           explicit .claude dir (must contain repo/)
#   2. <cwd>/.claude           when run from a project root that has .claude/repo
#   3. skill-anchored .claude  the .claude dir this skill is installed under
#
# NOTE: intentionally NO shebang. On Windows the py launcher resolves
# "#!/usr/bin/env python3" to the WindowsApps python3 stub, which exits
# silently with code 49. Always invoke via an explicit interpreter:
#   py  get_git_remotes.py          (Windows)
#   python3 get_git_remotes.py      (Linux/Mac)
#
# Cross-platform (Windows/Linux/Mac), replaces the former get-git-remotes.ps1/.sh pair.

import argparse
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

URL_PREFIXES = ("git@", "https://", "http://", "file://")

# Meta dirs (_read/_self/...) are notes/workspace, never reference repos.
META_PREFIX = ("_", ".")


def is_shareable_url(url):
    """Manifest-worthy origin. Read and write paths MUST share this predicate."""
    return bool(url) and url.startswith(URL_PREFIXES)


def parse_args():
    p = argparse.ArgumentParser(
        description="Keep www/git.remote manifest and .claude/repo/ clones consistent"
    )
    p.add_argument("command", nargs="?", default="check",
                   choices=["check", "extract", "sync"],
                   help="check (default): diff preview; extract: append remotes; sync: converge")
    p.add_argument(
        "-f", "--force", action="store_true",
        help="extract: reset output file before writing (no dedup needed)",
    )
    p.add_argument(
        "--root", type=Path, default=None,
        help="explicit .claude base directory (must contain repo/); "
             "default: <cwd>/.claude if it has repo/, else the skill-anchored .claude",
    )
    p.add_argument(
        "--prune", action="store_true",
        help="sync: delete repo dirs whose URL is no longer in the manifest",
    )
    p.add_argument(
        "--update", action="store_true",
        help="sync: git pull --ff-only existing clones to update them",
    )
    p.add_argument(
        "--depth", type=int, default=None, metavar="N",
        help="sync: shallow clone with depth N",
    )
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


def host_origin(root):
    """Origin URL of the host project itself (never synced/cloned into itself)."""
    return get_origin(root.parent)


def read_manifest(output_file):
    if not output_file.exists():
        return []
    urls = []
    for line in output_file.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if is_shareable_url(line):
            urls.append(line)
    return urls


def scan_repos(repo_dir):
    """Disk truth. Returns ({dir_name: origin_url}, skipped_count) for real
    clones only; meta dirs (_*/.*) and non-git dirs are counted as skipped."""
    state = {}
    skipped = 0
    for entry in sorted(p for p in repo_dir.iterdir() if p.is_dir()):
        if entry.name.startswith(META_PREFIX) or not (entry / ".git").exists():
            skipped += 1
            continue
        state[entry.name] = get_origin(entry)
    return state, skipped


def url_to_dirname(url):
    """Derive the clone target dir name from a URL (last path segment, .git stripped)."""
    name = url.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    return name


def load_state(root):
    repo_dir = root / "repo"
    www_dir = root / "www"
    output_file = www_dir / "git.remote"
    if not repo_dir.is_dir():
        print(f"Error: Repository directory not found: {repo_dir}", file=sys.stderr)
        sys.exit(2)
    www_dir.mkdir(parents=True, exist_ok=True)
    return repo_dir, www_dir, output_file


# ---------------------------------------------------------------- check


def compute_diff(root, repo_dir, output_file):
    """Manifest vs disk. Returns (missing, stale, conflicts, host_url).

    missing : shareable URL in manifest, no clone on disk    -> sync would clone
    stale : shareable-origin clone, URL not in manifest    -> --prune would delete
    conflict: manifest URL maps to a name taken by a clone with another URL.
              Fires even when the disk clone's origin is a bare local path:
              that dir blocks the manifest's clone slot and must be resolved
              by hand (delete it, or `git remote set-url origin <manifest URL>`).
    Local-path-origin clones otherwise never appear in stale/prune/update lists.
    """
    manifest = read_manifest(output_file)
    host = host_origin(root)
    disk, _ = scan_repos(repo_dir)

    by_name = {url_to_dirname(u): u for u in manifest}
    missing, conflicts = [], []
    for url in dict.fromkeys(manifest):  # dedup, keep order
        if host and url == host:
            continue  # host project itself: never its own reference repo
        name = url_to_dirname(url)
        if name in disk and disk[name] and disk[name] != url:
            conflicts.append((url, name, disk[name]))
        elif not (repo_dir / name).is_dir():
            missing.append((url, name))

    stale = [
        (name, url) for name, url in sorted(disk.items())
        if is_shareable_url(url) and name not in by_name
    ]
    return missing, stale, conflicts, host


def cmd_check(root, repo_dir, output_file):
    missing, stale, conflicts, host = compute_diff(root, repo_dir, output_file)
    manifest_n = len(read_manifest(output_file))

    print(f"Manifest: {output_file}")
    if host:
        print(f"Host repo (excluded from sync): {host}")

    if not (missing or stale or conflicts):
        print("OK: manifest and repo/ are consistent.")
        return 0

    print("Drift detected - actions `sync` would take:")
    for url, name in missing:
        print(f"  + clone  {url}  ->  repo/{name}/")
    for name, url in stale:
        print(f"  - prune  repo/{name}/  (origin {url} not in manifest; needs --prune)")
    for url, name, actual in conflicts:
        print(f"  ! conflict  repo/{name}/ has {actual}, manifest wants {url}")
    print(f"\nManifest entries: {manifest_n}, missing: {len(missing)}, "
          f"stale: {len(stale)}, conflicts: {len(conflicts)}")
    return 1


# ---------------------------------------------------------------- extract


def cmd_extract(root, repo_dir, output_file, force):
    if force and output_file.exists():
        output_file.unlink()

    existing = set(read_manifest(output_file))
    host = host_origin(root)

    added = deduped = no_remote = local = 0
    disk, skipped = scan_repos(repo_dir)
    for name, url in disk.items():
        if not url:
            print(f"Warning: {name}: No remote 'origin' found", file=sys.stderr)
            no_remote += 1
            continue
        if not is_shareable_url(url):
            local += 1  # bare local path: machine-local asset, not tracked
            continue
        if host and url == host:
            deduped += 1  # host project itself: not a reference repo
            continue
        if url in existing:
            deduped += 1
            continue
        with output_file.open("a", encoding="utf-8") as f:
            f.write(url + "\n")
        existing.add(url)
        added += 1

    print(f"Root: {root}  Host excluded: {host or 'n/a'}")
    print(f"Added: {added}, Deduped: {deduped}, NoRemote: {no_remote}, "
          f"LocalPath: {local}, SkippedDirs: {skipped}")
    print(f"Output: {output_file}")
    return 0


# ---------------------------------------------------------------- sync


def cmd_sync(root, repo_dir, output_file, prune, update, depth):
    host = host_origin(root)

    # 1. Pull disk truth into the manifest first (append + dedup).
    rc = cmd_extract(root, repo_dir, output_file, force=False)

    missing, stale, conflicts, _ = compute_diff(root, repo_dir, output_file)

    # 2. Clone what the manifest wants but disk lacks.
    cloned = failed = 0
    for url, name in missing:
        target = repo_dir / name
        git_args = ["clone"]
        if depth:
            git_args += ["--depth", str(depth)]
        git_args += [url, str(target)]
        print(f"Cloning {url} -> repo/{name}/ ...")
        proc = run_git(git_args, cwd=repo_dir.parent)
        if proc.returncode != 0:
            err = (proc.stderr or "").strip().splitlines()
            print(f"  FAILED: {err[-1] if err else 'git clone error'}", file=sys.stderr)
            failed += 1
            continue
        cloned += 1

    # 3. Update existing clones (fast-forward only).
    updated = 0
    if update:
        disk, _ = scan_repos(repo_dir)
        for name, url in sorted(disk.items()):
            if not is_shareable_url(url) or url == host:
                continue
            proc = run_git(["pull", "--ff-only"], cwd=repo_dir / name)
            if proc.returncode == 0:
                print(f"Updated repo/{name}/")
                updated += 1
            else:
                err = (proc.stderr or "").strip().splitlines()
                print(f"Update skipped repo/{name}/: {err[-1] if err else 'git pull error'}",
                      file=sys.stderr)

    # 4. Prune stale dirs only when explicitly asked.
    pruned = 0
    if prune and stale:
        print("Pruning stale repo dirs (origin no longer in manifest):")
        for name, url in stale:
            print(f"  deleting repo/{name}/  (origin {url})")
            rmtree_force(repo_dir / name)
            pruned += 1

    print(f"\nSync done. Cloned: {cloned}, clone-failed: {failed}, "
          f"Updated: {updated}, Pruned: {pruned}, Conflicts: {len(conflicts)}")
    for url, name, actual in conflicts:
        print(f"  ! unresolved conflict repo/{name}/: has {actual}, manifest wants {url}",
              file=sys.stderr)
    return 0 if not conflicts else 2


# ---------------------------------------------------------------- helpers


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


def main():
    args = parse_args()

    skill_claude = Path(__file__).resolve().parents[3]
    if skill_claude.name != ".claude":
        # Installed somewhere unexpected; still usable via --root / cwd.
        skill_claude = None

    root, how = resolve_root(args.root, skill_claude)
    repo_dir, www_dir, output_file = load_state(root)

    if args.command == "extract":
        return cmd_extract(root, repo_dir, output_file, args.force)
    if args.command == "sync":
        return cmd_sync(root, repo_dir, output_file, args.prune, args.update, args.depth)

    rc = cmd_check(root, repo_dir, output_file)
    if how == "skill-anchored":
        print("Note: resolved to skill-anchored .claude (not a project). "
              "Pass --root or run from a project directory.", file=sys.stderr)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # never let a crash masquerade as check drift (exit 1)
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)
