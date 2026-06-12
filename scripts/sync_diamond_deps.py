#!/usr/bin/env python3
"""
sync_diamond_deps.py — resolve a Zig "diamond dependency" by converging the
conflicting package onto a single version across the local DevNW sibling
ecosystem, patch-tagging each consumer in topological order.

This is the companion fix-tool to `detect_diamond_deps.py` (which only
*reports* diamonds). It has two modes:

LOCAL mode (default — safe for pre-commit):
    Detect diamonds in THIS repo. For each conflicting package P, pick the
    target = highest version among the candidates. Then, for each DIRECT dep D
    of this repo whose subtree still pins a non-target P, look for a released
    sibling version of D that already converges on P=target and repoint THIS
    repo's `build.zig.zon` to it. No other repo is mutated; nothing is pushed.
    If a needed converged version of D does not exist yet, the tool fails with
    a clear "upstream not ready — run --cascade" message (exit 1). This is the
    mode the pre-commit hook invokes when `detect-diamond-deps` fires.

CASCADE mode (`--cascade`, maintainer-only):
    Propagate a leaf bump (e.g. a new `tls` release) through the WHOLE local
    sibling ecosystem. Topologically orders every transitive consumer of the
    conflicting package, and for each: checks it out at the base commit the
    --base-from root currently pins (minimal drift), bumps its pins for any
    already-bumped dep to that dep's new tag, refreshes its cache, verifies the
    diamond is gone, commits, creates the lowest-increment patch tag, and
    (with --apply) pushes branch+tag. Finally rewrites the root repo's pins.
    Without --apply it is a DRY RUN that prints the full plan.

Usage
-----
    # pre-commit / local (default): resolve THIS repo's pins, no pushes
    scripts/sync_diamond_deps.py

    # maintainer: plan the ecosystem cascade for a known leaf bump (dry run)
    scripts/sync_diamond_deps.py --cascade \
        --target tls=v0.1.9#0cbbf1a4f0389c46ddde6947979c62d7afbcf076 \
        --base-from .

    # maintainer: actually execute it. --apply now requires an explicit push
    # allowlist (or --all-discovered) and an interactive confirmation, and it
    # verifies the --target's tag/commit integrity first.
    scripts/sync_diamond_deps.py --cascade --apply \
        --target tls=v0.1.9#0cbbf1a4f0389c46ddde6947979c62d7afbcf076 \
        --base-from . \
        --allow-repos tls,geode-client-zig

Supply-chain hardening (GAP-0069 / issue #124)
----------------------------------------------
`--cascade --apply` is a high-blast-radius multi-repo mutator. It is gated by:
  * an interactive push-CONFIRMATION (typed token), bypassable only via --yes /
    $SYNC_DIAMOND_ASSUME_YES; on a non-TTY with no bypass it REFUSES (fail safe);
  * an explicit push ALLOWLIST (--allow-repo / --allow-repos), or --all-discovered
    to deliberately authorize the full set; non-allowlisted repos are SKIPPED;
  * --target INTEGRITY verification (signed/annotated tag + commit binding);
    unsigned/unverifiable targets need --allow-unverified-target;
  * a GUARDED cache delete (only known cache dirs strictly inside the repo);
  * DISCOVERY scope logging — every discovered repo + origin URL is printed;
    the over-broad parent-dir scan is opt-in via --include-parent-dir.
Dry run (`--cascade` without `--apply`) stays fully side-effect-free.

Sibling repos are discovered under the colon-separated $DEVNW_SIBLING_BASES
(default: ~/src/devnw/zig:~/src/devnw/codepros/geode). The parent of the current
repo is scanned only with --include-parent-dir. Each repo is matched by the
`.name` in its `build.zig.zon`.

Exit codes: 0 success / clean, 1 unresolved or error, 2 tooling failure.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Reuse the parser + walker from the sibling detector.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import detect_diamond_deps as ddd  # noqa: E402

SEMVER_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
NAME_RE = re.compile(r"\.name\s*=\s*(?:\.([A-Za-z_][A-Za-z0-9_]*)|\"([^\"]+)\")")
DEVNW_URL_RE = re.compile(
    r"gitlab\.com/devnw/(?:zig|codepros/geode)/([A-Za-z0-9_.-]+?)\.git"
)

# Confirmation token the operator must type at the apply/push gate (control #1).
# Non-trivial so it cannot be hit by an accidental Enter/"y". This is a public,
# operator-typed acknowledgement string — NOT a secret/credential.
PUSH_CONFIRM_TOKEN = "APPLY"  # nosec B105 - confirmation token, not a password
# Environment variable that bypasses the interactive confirmation for CI/automation.
ASSUME_YES_ENV = "SYNC_DIAMOND_ASSUME_YES"
# Only these basenames may be removed by refresh_cache (control #4).
KNOWN_CACHE_DIRS = (".zig-cache", "zig-pkg", "zig-out")


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def run(
    cmd: list[str], cwd: Path | None = None, check: bool = True, capture: bool = True
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        capture_output=capture,
    )


# ---------------------------------------------------------------------------
# zon helpers
# ---------------------------------------------------------------------------
def zon_name(zon_text: str) -> str | None:
    m = NAME_RE.search(zon_text)
    if not m:
        return None
    return m.group(1) or m.group(2)


def zon_direct_deps(zon_path: Path) -> list[tuple[str, str, str | None]]:
    """(dep_field_name, hash, url) for each direct dep of the zon."""
    text = zon_path.read_text(encoding="utf-8", errors="replace")
    block = ddd._find_dependencies_block(text)
    if block is None:
        return []
    return ddd._parse_dep_entries(block)


def devnw_name_from_url(url: str | None) -> str | None:
    if not url:
        return None
    m = DEVNW_URL_RE.search(url)
    if not m:
        return None
    # geode-client-zig.git -> dep field is geode_client_zig; normalize on the
    # repo (URL) name, callers map field<->repo separately.
    return m.group(1)


# ---------------------------------------------------------------------------
# sibling discovery
# ---------------------------------------------------------------------------
@dataclass
class Repo:
    field_name: str  # zon dependency field name (e.g. geode_client_zig)
    repo_name: str  # URL/repo slug (e.g. geode-client-zig)
    path: Path  # local checkout
    url: str  # canonical git+https url (no #ref)


def discover_repos(
    extra_root: Path, include_parent_dir: bool = False
) -> dict[str, Repo]:
    """Map zon-field-name -> Repo for every local DevNW sibling checkout.

    Discovery scope (control #5): the colon-separated $DEVNW_SIBLING_BASES are
    always scanned. The parent directory of the current repo is an OVER-BROAD
    source (it can sweep in unrelated checkouts), so it is only included when
    `include_parent_dir` is True. Every discovered repo is logged with its
    origin URL so the operator can see the blast radius before confirming.
    """
    bases_env = os.environ.get(
        "DEVNW_SIBLING_BASES",
        f"{Path.home()}/src/devnw/zig:{Path.home()}/src/devnw/codepros/geode",
    )
    bases = [Path(b).expanduser() for b in bases_env.split(":") if b]
    if include_parent_dir:
        log(f"discovery: including parent dir of current repo: {extra_root.parent}")
        bases.append(extra_root.parent)
    else:
        log(
            "discovery: parent-dir-of-current-repo inclusion DISABLED "
            "(pass --include-parent-dir to widen scope)"
        )
    repos: dict[str, Repo] = {}
    for base in bases:
        if not base.is_dir():
            continue
        log(f"discovery: scanning base {base}")
        for child in sorted(base.iterdir()):
            zon = child / "build.zig.zon"
            if not (child / ".git").exists() or not zon.exists():
                continue
            try:
                name = zon_name(zon.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
            if not name:
                continue
            repo_slug = child.name  # directory name == repo slug
            url = _url_for(child)
            if name not in repos:
                repos[name] = Repo(
                    field_name=name, repo_name=repo_slug, path=child.resolve(), url=url
                )
                log(f"  discovered {name:24s} {url or '(no origin url)'}  [{child}]")
    return repos


def _url_for(repo_path: Path) -> str:
    try:
        out = run(["git", "remote", "get-url", "origin"], cwd=repo_path).stdout.strip()
    except subprocess.CalledProcessError:
        return ""
    # git@gitlab.com:devnw/zig/tls.git -> git+https://gitlab.com/devnw/zig/tls.git
    m = re.search(
        r"[:/](devnw/(?:zig|codepros/geode)/[A-Za-z0-9_.-]+?)(?:\.git)?$", out
    )
    if not m:
        return ""
    return f"git+https://gitlab.com/{m.group(1)}.git"


# ---------------------------------------------------------------------------
# git / tag helpers
# ---------------------------------------------------------------------------
def latest_patch_tag(repo: Repo) -> tuple[int, int, int]:
    out = run(["git", "tag", "--list", "v*"], cwd=repo.path, check=False).stdout
    best = (0, 0, 0)
    for line in out.splitlines():
        m = SEMVER_TAG_RE.match(line.strip())
        if m:
            t = tuple(int(x) for x in m.groups())
            if t > best:
                best = t  # type: ignore[assignment]
    return best  # type: ignore[return-value]


def remote_tag_exists(repo: Repo, tag: str) -> bool:
    out = run(
        ["git", "ls-remote", "origin", f"refs/tags/{tag}"], cwd=repo.path, check=False
    ).stdout
    return bool(out.strip())


def next_free_patch_tag(repo: Repo) -> str:
    """Lowest-increment patch tag not already used locally or on the remote."""
    major, minor, patch = latest_patch_tag(repo)
    while True:
        patch += 1
        tag = f"v{major}.{minor}.{patch}"
        local = run(
            ["git", "tag", "--list", tag], cwd=repo.path, check=False
        ).stdout.strip()
        if not local and not remote_tag_exists(repo, tag):
            return tag


def pinned_commit(root_zon_text: str, field_name: str) -> str | None:
    block = ddd._find_dependencies_block(root_zon_text)
    if not block:
        return None
    for name, _h, url in ddd._parse_dep_entries(block):
        if name == field_name and url and "#" in url:
            return url.split("#", 1)[1]
    return None


def zig_pkg_hash(consumer_path: Path, url_with_ref: str) -> str | None:
    """`zig fetch <url>` from inside consumer_path; returns the package hash."""
    try:
        cp = run(["zig", "fetch", url_with_ref], cwd=consumer_path, check=True)
    except subprocess.CalledProcessError as e:
        log(f"    zig fetch failed: {e.stderr.strip()[:200]}")
        return None
    out = cp.stdout.strip().splitlines()
    return out[-1].strip() if out else None


def rewrite_pin(
    zon_text: str, field_name: str, new_url: str, new_hash: str
) -> tuple[str, int]:
    """Replace the .url and .hash of `.<field_name> = .{ ... }`.

    Robust to comment-heavy blocks (a single spanning regex breaks when a
    comment between `.{` and `.url` contains a brace): locate the dep marker,
    bound the block by the next dep marker, then replace the first .url/.hash
    inside it.
    """
    marker = re.search(r"\." + re.escape(field_name) + r"\s*=\s*\.\{", zon_text)
    if not marker:
        return zon_text, 0
    start = marker.end()
    nxt = re.search(r"\n\s*\.[A-Za-z_][A-Za-z0-9_]*\s*=\s*\.\{", zon_text[start:])
    end = start + nxt.start() if nxt else len(zon_text)
    block = zon_text[start:end]
    block, nu = re.subn(
        r'(\.url\s*=\s*")[^"]+(")',
        lambda m: m.group(1) + new_url + m.group(2),
        block,
        count=1,
    )
    block, nh = re.subn(
        r'(\.hash\s*=\s*")[^"]+(")',
        lambda m: m.group(1) + new_hash + m.group(2),
        block,
        count=1,
    )
    if nu == 0 or nh == 0:
        return zon_text, 0
    return zon_text[:start] + block + zon_text[end:], 1


def _safe_rmtree_cache(repo_path: Path, cache_dir: str) -> None:
    """Delete a single known cache dir inside repo_path, guarded (control #4).

    Replaces the prior `rm -rf` subprocess. The path is resolved and asserted to
    be (a) absolute, (b) strictly inside the expected repo_path, and (c) named
    one of the known cache directories. Any path that fails the guard raises and
    is never deleted — no symlink-escape, no traversal, no surprise targets.
    """
    if cache_dir not in KNOWN_CACHE_DIRS:
        raise ValueError(f"refusing to delete non-cache dir name: {cache_dir!r}")

    repo_root = repo_path.resolve()
    target = (repo_root / cache_dir).resolve()

    # Guard: must be absolute.
    if not target.is_absolute():
        raise ValueError(f"refusing to delete non-absolute path: {target}")
    # Guard: basename must be a known cache dir name (resolve() can't change it,
    # but assert explicitly so the invariant is enforced post-resolution).
    if target.name not in KNOWN_CACHE_DIRS:
        raise ValueError(f"refusing to delete unexpected basename: {target}")
    # Guard: must be strictly INSIDE repo_root (not equal to it, not outside).
    if target == repo_root or repo_root not in target.parents:
        raise ValueError(f"refusing to delete path outside repo {repo_root}: {target}")

    if not target.exists():
        return
    # Refuse to follow a symlink that masquerades as the cache dir.
    if target.is_symlink():
        raise ValueError(f"refusing to delete symlinked cache path: {target}")
    shutil.rmtree(target)


def refresh_cache(repo_path: Path) -> bool:
    for d in ("zig-pkg", ".zig-cache"):
        _safe_rmtree_cache(repo_path, d)
    cp = run(["zig", "build", "--fetch"], cwd=repo_path, check=False)
    return cp.returncode == 0


def diamond_clean(repo_path: Path) -> bool:
    cp = run(
        [
            sys.executable,
            str(Path(__file__).resolve().parent / "detect_diamond_deps.py"),
            str(repo_path),
        ],
        check=False,
    )
    return cp.returncode == 0


# ---------------------------------------------------------------------------
# ecosystem graph + topo sort
# ---------------------------------------------------------------------------
def ecosystem_edges(repos: dict[str, Repo]) -> dict[str, set[str]]:
    """field_name -> set of devnw dep field_names it directly pins."""
    edges: dict[str, set[str]] = {}
    for name, repo in repos.items():
        deps = set()
        for dep_field, _h, _u in zon_direct_deps(repo.path / "build.zig.zon"):
            if dep_field in repos:
                deps.add(dep_field)
        edges[name] = deps
    return edges


def consumers_of(target: str, edges: dict[str, set[str]]) -> set[str]:
    """All field_names that transitively depend on `target` (excluding target)."""
    rev: dict[str, set[str]] = {n: set() for n in edges}
    for n, deps in edges.items():
        for d in deps:
            rev.setdefault(d, set()).add(n)
    out: set[str] = set()
    stack = [target]
    while stack:
        cur = stack.pop()
        for parent in rev.get(cur, ()):
            if parent not in out:
                out.add(parent)
                stack.append(parent)
    return out


def topo_order(subset: set[str], edges: dict[str, set[str]]) -> list[str]:
    order: list[str] = []
    temp: set[str] = set()
    done: set[str] = set()

    def visit(n: str) -> None:
        if n in done:
            return
        if n in temp:
            raise RuntimeError(f"dependency cycle at {n}")
        temp.add(n)
        for d in sorted(edges.get(n, ())):
            if d in subset:
                visit(d)
        temp.discard(n)
        done.add(n)
        order.append(n)

    for n in sorted(subset):
        visit(n)
    return order


# ---------------------------------------------------------------------------
# cascade
# ---------------------------------------------------------------------------
@dataclass
class Bumped:
    field_name: str
    tag: str
    commit: str
    pkg_hash: str
    url_with_ref: str


def parse_target(spec: str) -> tuple[str, str, str]:
    # tls=v0.1.9#<commit>
    name, rest = spec.split("=", 1)
    ref, commit = rest.split("#", 1)
    return name, ref, commit


def normalize_allowlist(
    allow_repo: list[str] | None, allow_repos: str | None
) -> set[str]:
    """Build the set of repo identifiers the operator explicitly authorized.

    Accepts both repeatable --allow-repo and comma-separated --allow-repos.
    Identifiers may be either the zon field-name or the repo slug; callers match
    against both. Empty/whitespace entries are dropped.
    """
    out: set[str] = set()
    for item in allow_repo or []:
        item = item.strip()
        if item:
            out.add(item)
    if allow_repos:
        for item in allow_repos.split(","):
            item = item.strip()
            if item:
                out.add(item)
    return out


def repo_allowed(repo: Repo, allowlist: set[str]) -> bool:
    """A repo is allowed if either its field name or its slug is on the list."""
    return repo.field_name in allowlist or repo.repo_name in allowlist


def verify_target_integrity(
    target_repo: Repo, tref: str, tcommit: str, allow_unverified: bool
) -> bool:
    """Best-effort integrity check of the --target ref/commit (control #3).

    Tries, in order:
      1. `git tag -v <ref>` (verifies a signed/annotated tag's signature).
      2. Failing a valid signature, confirm the tag object resolves to the
         exact #commit the operator supplied (tamper-evident binding).
    Returns True if verified. If the dep repo is not locally available or no
    signature exists, returns the value of `allow_unverified` (opt-in), after
    WARNING loudly. Never hard-blocks solely on missing local checkout.
    """
    if not target_repo.path.is_dir() or not (target_repo.path / ".git").exists():
        log(
            f"  [integrity] target repo not locally available at "
            f"{target_repo.path}; cannot verify {tref}#{tcommit[:8]}."
        )
        if allow_unverified:
            log("  [integrity] proceeding UNVERIFIED (--allow-unverified-target).")
            return True
        log(
            "  [integrity] REFUSING unverified target (pass "
            "--allow-unverified-target to override)."
        )
        return False

    # 1. Signed/annotated tag signature verification.
    sig = run(["git", "tag", "-v", tref], cwd=target_repo.path, check=False)
    if sig.returncode == 0:
        log(f"  [integrity] OK: {tref} is a verified signed/annotated tag.")
        # Still confirm the tag points at the claimed commit.
    else:
        log(
            f"  [integrity] WARNING: `git tag -v {tref}` did not verify a "
            f"signature (rc={sig.returncode})."
        )

    # 2. Confirm the supplied #commit matches what the tag actually resolves to.
    resolved = run(
        ["git", "rev-list", "-n", "1", tref], cwd=target_repo.path, check=False
    )
    resolved_commit = resolved.stdout.strip() if resolved.returncode == 0 else ""
    # The supplied #commit must be a real pin: a non-empty hex prefix of a
    # sane length. Without this guard an empty or 1-2 char `tcommit` makes the
    # `startswith` binding below vacuously true (e.g. `--target pkg=ref#`),
    # silently accepting whatever commit the tag happens to resolve to.
    _MIN_COMMIT_PIN = 7
    tcommit_is_valid_pin = len(tcommit) >= _MIN_COMMIT_PIN and all(
        c in "0123456789abcdefABCDEF" for c in tcommit
    )
    if resolved_commit:
        if not tcommit_is_valid_pin:
            log(
                f"  [integrity] REFUSING: --target commit pin "
                f"'{tcommit}' is missing or too short; supply at least "
                f"{_MIN_COMMIT_PIN} hex chars (full 40-char SHA preferred)."
            )
            return False
        if resolved_commit == tcommit or resolved_commit.startswith(tcommit):
            log(
                f"  [integrity] tag {tref} resolves to supplied commit "
                f"{tcommit[:8]} — binding confirmed."
            )
            if sig.returncode == 0:
                return True
            # Commit matches but no signature: explicit opt-in still required.
            if allow_unverified:
                log(
                    "  [integrity] commit binding OK but tag UNSIGNED; "
                    "proceeding (--allow-unverified-target)."
                )
                return True
            log(
                "  [integrity] REFUSING: tag is unsigned. Re-run with "
                "--allow-unverified-target to accept the commit-only binding."
            )
            return False
        log(
            f"  [integrity] MISMATCH: tag {tref} resolves to "
            f"{resolved_commit[:8]} but --target claims {tcommit[:8]}."
        )
        return False

    log(f"  [integrity] could not resolve {tref} locally to a commit.")
    if allow_unverified:
        log("  [integrity] proceeding UNVERIFIED (--allow-unverified-target).")
        return True
    log(
        "  [integrity] REFUSING unverified target (pass "
        "--allow-unverified-target to override)."
    )
    return False


def confirm_push(
    push_plan: list[tuple[str, str, str]],
    assume_yes: bool,
) -> bool:
    """Confirmation gate before ANY git push in apply mode (control #1).

    `push_plan` is a list of (repo_name, branch, tag) to be pushed. Prints the
    COMPLETE plan, then:
      - if --yes/--assume-yes or $SYNC_DIAMOND_ASSUME_YES is set: proceed (logged);
      - else if stdin is a TTY: require the operator to type the literal token;
      - else (non-interactive, no bypass): REFUSE (fail safe).
    """
    log("")
    log("#" * 72)
    log("# PUSH CONFIRMATION REQUIRED — the following repos will be MUTATED and")
    log(f"# pushed to their 'origin' remotes ({len(push_plan)} repo(s)):")
    log("#" * 72)
    for repo_name, branch, tag in push_plan:
        log(f"#   {repo_name:28s}  push branch {branch!r} + tag {tag!r}")
    log("#" * 72)

    env_bypass = os.environ.get(ASSUME_YES_ENV, "").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    if assume_yes or env_bypass:
        why = "--yes/--assume-yes" if assume_yes else f"${ASSUME_YES_ENV}"
        log(f"# confirmation bypassed via {why}; proceeding with push.")
        return True

    if not sys.stdin.isatty():
        log(
            "# stdin is not a TTY and no bypass (--yes / "
            f"${ASSUME_YES_ENV}) was set — REFUSING to push (fail safe)."
        )
        return False

    expected = f"yes-push-{len(push_plan)}-repos"
    log(
        f"# To proceed, type exactly '{PUSH_CONFIRM_TOKEN}' or '{expected}' "
        "and press Enter."
    )
    log("# Anything else aborts.")
    try:
        answer = input("confirm> ").strip()
    except (EOFError, KeyboardInterrupt):
        log("# aborted (no confirmation received).")
        return False
    if answer in (PUSH_CONFIRM_TOKEN, expected):
        log("# confirmation accepted; proceeding with push.")
        return True
    log(f"# confirmation token did not match; aborting (got {answer!r}).")
    return False


def cascade(
    root_repo: Path,
    target_spec: str,
    base_from: Path,
    apply: bool,
    *,
    allowlist: set[str] | None = None,
    all_discovered: bool = False,
    assume_yes: bool = False,
    allow_unverified_target: bool = False,
    include_parent_dir: bool = False,
) -> int:
    allowlist = allowlist or set()
    repos = discover_repos(root_repo, include_parent_dir=include_parent_dir)
    tname, tref, tcommit = parse_target(target_spec)
    if tname not in repos:
        log(f"sync-diamond: target '{tname}' has no local sibling checkout")
        return 2
    target_repo = repos[tname]

    # Control #2: in apply+push mode an explicit allowlist (or --all-discovered)
    # is mandatory. Refuse the broad push set unless opted-in.
    if apply and not allowlist and not all_discovered:
        log(
            "sync-diamond: --apply requires an explicit push allowlist. Pass "
            "--allow-repo <name> (repeatable) and/or --allow-repos a,b,c, or "
            "--all-discovered to deliberately authorize EVERY discovered repo."
        )
        return 2

    # Control #3: verify the target ref/commit integrity before adopting it.
    if not verify_target_integrity(target_repo, tref, tcommit, allow_unverified_target):
        log(
            f"sync-diamond: target integrity check failed for {tname} "
            f"{tref}#{tcommit[:8]} — aborting."
        )
        return 2

    # The target's package hash (it must already be pushed at tref/tcommit).
    target_url = f"{target_repo.url}?ref={tref}#{tcommit}"
    thash = zig_pkg_hash(root_repo, target_url)
    if not thash:
        log(
            f"sync-diamond: cannot fetch target {tname} at {tref}#{tcommit[:8]} (is it pushed?)"
        )
        return 2

    edges = ecosystem_edges(repos)
    subset = consumers_of(tname, edges)
    # Only bump consumers that the base-from root ACTUALLY pulls — restrict to
    # the packages present in its resolved transitive graph (not every sibling
    # checkout on disk).
    cache_env = os.environ.get("ZIG_GLOBAL_CACHE_DIR")
    cache_root = Path(cache_env) if cache_env else Path.home() / ".cache" / "zig"
    active = set(ddd.collect_transitive(base_from / "build.zig.zon", cache_root).keys())
    active.add(tname)
    subset &= active
    order = topo_order(subset, edges)

    bumped: dict[str, Bumped] = {
        tname: Bumped(tname, tref, tcommit, thash, target_url),
    }

    log("=" * 72)
    log(f"DIAMOND CASCADE  target={tname} -> {tref}#{tcommit[:8]} ({thash})")
    log(f"mode={'APPLY (will push to remotes)' if apply else 'DRY RUN'}")
    log(f"consumers to bump ({len(order)}): {', '.join(order)}")
    log("=" * 72)

    # Control #2: in apply mode, partition the planned consumers into the set
    # that is authorized to be pushed (allowlist or --all-discovered) and the
    # set that will be SKIPPED. Skipped repos are never mutated or pushed.
    skipped: list[str] = []
    if apply and not all_discovered:
        authorized_order: list[str] = []
        for field in order:
            if repo_allowed(repos[field], allowlist):
                authorized_order.append(field)
            else:
                skipped.append(field)
        if skipped:
            log(
                f"allowlist: SKIPPING {len(skipped)} discovered repo(s) NOT on "
                f"the allowlist: {', '.join(skipped)}"
            )
        order = authorized_order
        if not order:
            log(
                "sync-diamond: nothing left to push after allowlist filtering — "
                "no authorized repos. Aborting."
            )
            return 2

    # Control #1: confirmation gate. In apply mode, present the COMPLETE push
    # plan (every repo + the exact branch and tag) and require explicit
    # confirmation BEFORE any mutation/push happens. Fails safe on non-TTY.
    if apply:
        push_plan = [
            (
                repos[field].repo_name,
                "gap-diamond-sync",
                next_free_patch_tag(repos[field]),
            )
            for field in order
        ]
        if not confirm_push(push_plan, assume_yes):
            log("sync-diamond: push not confirmed — aborting before any mutation.")
            return 2

    base_zon = (base_from / "build.zig.zon").read_text()

    for field in order:
        repo = repos[field]
        log(f"\n--- {field}  ({repo.repo_name}) ---")

        # Determine this repo's minimal base = the commit the root currently pins.
        base_commit = pinned_commit(base_zon, field)
        if not base_commit:
            log(
                f"  {field}: not directly pinned by base-from root; using origin/main HEAD"
            )

        # Which of this repo's direct deps were bumped (need re-pin here)?
        deps_here = {n for (n, _h, _u) in zon_direct_deps(repo.path / "build.zig.zon")}
        to_repin = [d for d in deps_here if d in bumped]
        log(f"  re-pin deps: {', '.join(to_repin) if to_repin else '(none)'}")
        new_tag = next_free_patch_tag(repo)
        log(f"  new tag: {new_tag}")

        if not apply:
            for d in to_repin:
                b = bumped[d]
                log(f"    {d} -> {b.tag}#{b.commit[:8]} ({b.pkg_hash})")
            # We cannot compute this repo's own hash until it's pushed; defer.
            bumped[field] = Bumped(
                field,
                new_tag,
                "<dry-run>",
                "<dry-run>",
                f"{repo.url}?ref={new_tag}#<dry-run>",
            )
            continue

        # APPLY: checkout the minimal base on a working branch.
        branch = "gap-diamond-sync"
        if base_commit:
            run(["git", "fetch", "origin", base_commit], cwd=repo.path, check=False)
            run(["git", "checkout", "-B", branch, base_commit], cwd=repo.path)
        else:
            run(["git", "checkout", "-B", branch, "origin/main"], cwd=repo.path)

        # Rewrite each bumped dep's pin.
        zon_path = repo.path / "build.zig.zon"
        text = zon_path.read_text()
        for d in to_repin:
            b = bumped[d]
            new_text, n = rewrite_pin(text, d, b.url_with_ref, b.pkg_hash)
            if n == 0:
                log(f"  ERROR: could not rewrite pin for {d} in {field}")
                return 1
            text = new_text
        zon_path.write_text(text)

        if not refresh_cache(repo.path):
            log(f"  ERROR: `zig build --fetch` failed for {field}")
            return 1
        if not diamond_clean(repo.path):
            log(
                f"  ERROR: {field} still has a diamond after re-pin (an indirect consumer was missed)"
            )
            return 1

        run(["git", "add", "build.zig.zon"], cwd=repo.path)
        run(
            [
                "git",
                "commit",
                "-m",
                f"chore(deps): converge {tname} onto {tref} (GAP-0838 diamond sync)",
            ],
            cwd=repo.path,
        )
        new_commit = run(["git", "rev-parse", "HEAD"], cwd=repo.path).stdout.strip()
        run(
            [
                "git",
                "tag",
                "-a",
                new_tag,
                "-m",
                f"{new_tag} — converge {tname} {tref} (GAP-0838 diamond sync)",
            ],
            cwd=repo.path,
        )
        run(["git", "push", "origin", branch], cwd=repo.path)
        run(["git", "push", "origin", new_tag], cwd=repo.path)

        url_ref = f"{repo.url}?ref={new_tag}#{new_commit}"
        h = zig_pkg_hash(root_repo, url_ref)
        if not h:
            log(f"  ERROR: could not compute pkg hash for {field}@{new_tag}")
            return 1
        bumped[field] = Bumped(field, new_tag, new_commit, h, url_ref)
        log(f"  pushed {field} {new_tag} ({new_commit[:8]}) hash={h}")

    # Finally rewrite the root repo's own pins.
    log("\n--- root repo re-pin ---")
    root_zon = root_repo / "build.zig.zon"
    text = root_zon.read_text()
    root_deps = {n for (n, _h, _u) in zon_direct_deps(root_zon)}
    for d in sorted(root_deps & set(bumped)):
        b = bumped[d]
        if apply and b.commit == "<dry-run>":
            continue
        log(f"  {d} -> {b.tag}#{str(b.commit)[:8]} ({b.pkg_hash})")
        if apply:
            new_text, n = rewrite_pin(text, d, b.url_with_ref, b.pkg_hash)
            if n == 0:
                log(
                    f"  ERROR: could not rewrite root pin for {d} — fix build.zig.zon "
                    f"by hand: {d} -> {b.url_with_ref} / {b.pkg_hash}"
                )
                return 1
            text = new_text
    if apply:
        root_zon.write_text(text)
        log(
            "  root build.zig.zon updated; run `zig build --fetch && make build` to verify."
        )
    else:
        log("\nDRY RUN complete — re-run with --apply to execute the cascade.")
    return 0


# ---------------------------------------------------------------------------
# local (pre-commit) mode
# ---------------------------------------------------------------------------
def local_resolve(root_repo: Path, apply: bool) -> int:
    cache_env = os.environ.get("ZIG_GLOBAL_CACHE_DIR")
    cache_root = Path(cache_env) if cache_env else Path.home() / ".cache" / "zig"
    graph = ddd.collect_transitive(root_repo / "build.zig.zon", cache_root)
    diamonds = ddd.find_diamonds(graph)
    if not diamonds:
        log("sync-diamond: no diamonds — nothing to do.")
        return 0
    log("sync-diamond: diamond(s) detected:")
    for name, pinned in diamonds:
        versions = sorted({(u or h) for (h, u) in pinned})
        log(f"  {name}: {len(pinned)} hashes -> {versions}")
    log("")
    log(
        "This repo cannot resolve a transitive diamond on its own — the "
        "intermediate libraries must be re-released so a single version "
        "propagates. Run the ecosystem cascade (maintainer):"
    )
    log("")
    for name, _pinned in diamonds:
        log("  scripts/sync_diamond_deps.py --cascade --apply \\")
        log(f"      --target {name}=<highest-version#commit> --base-from .")
    log("")
    log(
        "(highest published version of the conflicting package wins; tls example: --target tls=v0.1.9#<commit>)"
    )
    return 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Resolve Zig diamond deps by converging versions."
    )
    ap.add_argument(
        "--cascade",
        action="store_true",
        help="maintainer mode: bump every transitive consumer across siblings",
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="execute (commit/tag/push); without it, dry run",
    )
    ap.add_argument("--target", help="conflicting pkg bump, e.g. tls=v0.1.9#<commit>")
    ap.add_argument(
        "--base-from",
        default=".",
        help="repo whose current pins define each sibling's minimal base",
    )
    ap.add_argument("--repo", default=".", help="repo to operate on / root for cascade")
    # --- supply-chain hardening flags (GAP-0069 / issue #124) ---
    ap.add_argument(
        "--yes",
        "--assume-yes",
        dest="assume_yes",
        action="store_true",
        help=(
            "bypass the interactive push-confirmation gate (for automation). "
            f"Env ${ASSUME_YES_ENV}=1 has the same effect. Default is to PROMPT; "
            "if stdin is not a TTY and no bypass is set, the tool REFUSES to push."
        ),
    )
    ap.add_argument(
        "--allow-repo",
        action="append",
        default=[],
        metavar="NAME",
        help=(
            "repeatable allowlist of repos (field-name or slug) that --apply may "
            "push to. Discovered repos NOT on the allowlist are reported and "
            "SKIPPED (never mutated/pushed)."
        ),
    )
    ap.add_argument(
        "--allow-repos",
        default=None,
        metavar="a,b,c",
        help="comma-separated allowlist (merged with --allow-repo).",
    )
    ap.add_argument(
        "--all-discovered",
        action="store_true",
        help=(
            "explicitly opt in to pushing EVERY discovered repo. Required by "
            "--apply when no allowlist is given (the safe default refuses)."
        ),
    )
    ap.add_argument(
        "--allow-unverified-target",
        action="store_true",
        help=(
            "adopt the --target commit even when its tag cannot be verified as "
            "signed/annotated (the commit<->tag binding is still checked when "
            "the dep repo is local). Off by default: unsigned/unverifiable "
            "targets are refused."
        ),
    )
    ap.add_argument(
        "--include-parent-dir",
        action="store_true",
        help=(
            "widen sibling discovery to include the parent directory of the "
            "current repo (over-broad; off by default). All discovered repos "
            "are logged with their origin URL regardless."
        ),
    )
    args = ap.parse_args(argv[1:])

    root = Path(args.repo).resolve()
    if not (root / "build.zig.zon").exists():
        log(f"sync-diamond: no build.zig.zon at {root}")
        return 2

    if args.cascade:
        if not args.target:
            log("sync-diamond: --cascade requires --target <pkg>=<vX.Y.Z>#<commit>")
            return 2
        allowlist = normalize_allowlist(args.allow_repo, args.allow_repos)
        return cascade(
            root,
            args.target,
            Path(args.base_from).resolve(),
            args.apply,
            allowlist=allowlist,
            all_discovered=args.all_discovered,
            assume_yes=args.assume_yes,
            allow_unverified_target=args.allow_unverified_target,
            include_parent_dir=args.include_parent_dir,
        )
    return local_resolve(root, args.apply)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
