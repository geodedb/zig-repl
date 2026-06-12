# AppSec Review — Audit Cycle 3 (NEW Findings)

**Project:** devnw/zig/repl — Zig REPL Library
**Date:** 2026-06-12
**Reviewer:** AppSec code reviewer (defensive, evidence-first)
**Scope commit:** `577adef` (branch `main`, clean tree)
**Baseline:** `docs/SECURITY_GAP_ANALYSIS.md` Rev 14 (SF-001..SF-030, 0 open)
**Frameworks:** OWASP Top 10:2025, CIS Controls v8.1.2
**Classification:** INTERNAL — do not distribute outside the project team

---

## 1. Scope & Assumptions

In scope and reviewed: `src/*.zig` (18 files), `tests/*.zig`, `build.zig`, `build.zig.zon`, `.gitlab-ci.yml`, `.pre-commit-config.yaml`, `Makefile` (via grep), `scripts/{detect_diamond_deps,sync_diamond_deps}.py`, `scripts/sync_diamond_deps.sh`, `examples/*` (spot-checked).

Special attention (post-dates 2026-03-25 audit): the Zig 0.16.0 migration (`57afad6 fix: zig 0.16.0 compat`, introducing `src/compat.zig`), the dependency-convergence commits, and the new `scripts/*diamond*` tooling.

Assumptions:

- Trust boundaries per the contract: terminal byte stream (incl. escape sequences), on-disk history/config files, environment variables, completion filesystem traversal. No network listener; no authn/authz.
- Threat model for file permissions = multi-user host where other local users (or other-UID service accounts) should not read a user's REPL config/history. This is the model the resolved findings SF-001/SF-022/SF-023/SF-024 were filed under, so I evaluate against it for regression purposes.
- I did not re-report resolved or Won't-Do items unless I found a concrete new exploit path with evidence. The Won't-Do items SF-026 and SF-027 were re-examined and remain validly Won't-Do (no new path).
- A standard process umask (022) is assumed for the world-readable analysis; this is the default on Linux/macOS interactive shells and was confirmed live (`umask` → `0022`).

**Methodology note:** the audit's regression tables in `SECURITY_GAP_ANALYSIS.md` cite line numbers from commit `f8eab0c`. Since then **all 18 source files changed** (~4.2k lines net added). I re-verified the resolved controls against *current* source rather than trusting the line citations — which is how the regressions below surfaced.

---

## 2. Executive Summary

- **One High-severity regression (NEW-001):** the Zig-0.16 compatibility shim turned `chmod` into a **silent no-op**, and `Config.saveToFile` was rewritten to call `createFile` **without** a `.permissions` argument. The net effect is that persisted config files are created **world-readable (0o644)** and never tightened. I reproduced this live: config path → `0o644`, history path → `0o600`. This regresses the SF-001 / SF-023 controls that were marked Resolved.
- **One Medium regression (NEW-002):** the history pre-existing-file permission enforcement (SF-022 / SF-024) is gone. New history files are correctly 0o600 via `createFile(.permissions=…)`, but an **already-existing** history file is opened and appended to without re-applying 0o600 — the exact TOCTOU the resolved findings closed. The in-code comment now explicitly documents the weaker behavior.
- **One Medium supply-chain finding (NEW-003):** the new maintainer tool `sync_diamond_deps.py --cascade --apply` rewrites `build.zig.zon` pins, then `git commit`/`tag`/`push`es to **every** discovered sibling repo's `origin`, and `rm -rf`'s cache directories — driven by an attacker-influenceable `--target pkg=ref#commit` string and by URLs derived from `git remote` output, with no signature verification and no confirmation prompt.
- **Two Low findings:** an otel pin label/version drift in `build.zig.zon` (NEW-004), and the misleading no-op `compat.chmod` as a latent control-failure that will silently defeat any future caller (NEW-005).
- **One Info finding:** the observability seam is hardcoded `enabled = false` (NEW-006), making the otel feature inert regardless of `-Dwith_otel`. Security-neutral (reduces attack surface) but a correctness gap worth tracking.
- The core terminal-input trust boundary (paste sanitization, history filtering, escape parsing, search) and signal handling remain **sound** and show **no regressions** — see Secure Design Notes.

Overall confidence: High on NEW-001 (reproduced) and NEW-002/004/005/006 (direct source evidence); Medium on NEW-003 (severity depends on the maintainer's runtime environment).

---

## 3. Findings Table

| ID | Severity | Confidence | Title | OWASP 2025 / CIS | Location |
|----|----------|------------|-------|------------------|----------|
| NEW-001 | High | High | Config files written world-readable (no-op chmod + missing `.permissions`) | A04 Cryptographic Failures / A01* ; CIS 3.3 | `src/compat.zig:66-72`, `src/config.zig:163-169` |
| NEW-002 | Medium | High | History permission enforcement on pre-existing files removed (SF-022/SF-024 regression) | A01 Broken Access Control / CIS 3.3 | `src/history.zig:193-201`, `src/history.zig:241-245` |
| NEW-003 | Medium | Medium | `sync_diamond_deps.py --cascade --apply` pushes to all sibling remotes + `rm -rf` from untrusted-ish input, no integrity check/confirmation | A03 Software Supply Chain Failures / A08 ; CIS 16.4, 2.4 | `scripts/sync_diamond_deps.py:360-521,265-271` |
| NEW-004 | Low | High | `build.zig.zon` otel pin: url `ref=v0.1.8` vs hash label `otel-0.1.7-…` drift | A08 Data Integrity / CIS 2.1 | `build.zig.zon:21-22` |
| NEW-005 | Low | High | `compat.chmod` is a silent no-op that defeats callers relying on it (latent control failure) | A09 Logging/Alerting (silent failure) / CIS 16 | `src/compat.zig:66-72` |
| NEW-006 | Info | High | Observability seam hardcoded `enabled=false`; otel feature inert under `-Dwith_otel` | N/A (correctness) | `src/observability.zig:43` |

\* NEW-001 maps primarily to A04 (sensitive data at rest left unprotected) with a Broken-Access-Control flavor; CWE-732.

---

## 4. Finding Details

### NEW-001 — Config files written world-readable (High)

**CWE:** CWE-732 Incorrect Permission Assignment for Critical Resource. **OWASP:** A04:2025 Cryptographic/Sensitive-data-at-rest failure. **CIS:** 3.3 (data access control). **Confidence:** High (reproduced).

**Evidence:**

- `src/compat.zig:66-72` — the chmod shim does nothing:

  ```zig
  pub fn chmod(file: File, mode: std.posix.mode_t) !void {
      _ = file;
      _ = mode;
      // ... "This is intentionally a no-op."
  }
  ```

- `src/config.zig:163` — config file is created with **no `.permissions`**:

  ```zig
  var file = try std.Io.Dir.cwd().createFile(cio, path, .{ .truncate = true });
  ```

- `src/config.zig:166-169` — the only "enforcement" is the no-op:

  ```zig
  if (comptime std.Io.File.Permissions.has_executable_bit) {
      compat.chmod(file, 0o600) catch {};   // no-op
  }
  ```

- There is **no permission test** in `config.zig` (grep confirms only the two lines above mention `0o600`), so the regression passed CI.

**Reproduction (live, umask 022):** A minimal program mirroring `config.zig:163` exactly. Result:

```text
config saveToFile perms = 0o644          <-- world + group readable
history createFile(.permissions=0o600) perms = 0o600
```

The history `createFile(.permissions=…)` path produces 0o600; the config path produces **0o644**.

**Attack path:** On a shared/multi-user host (or any host where another local UID — e.g. a web-server or CI service account — can read the user's home or an `$XDG_CONFIG_HOME`/`$APP_CONFIG`-pointed directory), a consumer application that calls `Config.saveToFile` writes a `0o644` file. Although the current `Config` schema persists only preferences (keymap, colors, max_history), the library advertises this as the persistence API and consumers commonly extend it; more importantly this is a **direct regression** of the control SF-001/SF-023 certified as Resolved. Any sensitive value a consumer adds to the config inherits world-readability. This is the same data-at-rest exposure class the project already rated Medium (SF-001, risk 45) — elevated to High here because the *previously-closed* control is now silently broken and untested, so it will not self-heal.

**Impact:** Local information disclosure of persisted REPL/app configuration to other users/UIDs on the host; erosion of a certified control with no test coverage to catch recurrence.

**Remediation:**

1. Create the file with restrictive perms at creation time, matching the history path:

   ```zig
   var file = try std.Io.Dir.cwd().createFile(cio, path, .{ .truncate = true, .permissions = @enumFromInt(0o600) });
   ```

2. Either implement `compat.chmod` for real (using the 0.16 `File.setPermissions`/`chmod` API) **or** delete it and its call sites so no code is misled into thinking it enforces anything (see NEW-005).
3. Add a regression test mirroring `history.zig`'s "history file permissions are 0o600" test, for `saveToFile`.

**Verification:** `saveToFile` then `statFile(...).permissions.toMode() & 0o777 == 0o600` under umask 022 and umask 077, and with a pre-existing 0o644 file.

---

### NEW-002 — History permission enforcement on pre-existing files removed (Medium)

**CWE:** CWE-732 / CWE-367 (TOCTOU). **OWASP:** A01:2025 Broken Access Control. **CIS:** 3.3. **Confidence:** High.

**Evidence:** `src/history.zig:193-201`:

```zig
const file = std.Io.Dir.cwd().createFile(compat.defaultIo(), path,
    .{ .truncate = false, .permissions = @enumFromInt(0o600) }) catch |err| { ... };
// Permissions are enforced via createFile options on creation.
// For pre-existing files, the OS-level permissions remain as-is.
self.append_handle = file;
```

The `clear()` path at `src/history.zig:241-245` likewise creates with `.permissions=0o600` but does **not** enforce on a pre-existing file. The resolved findings SF-022 (appendLine) and SF-024 (clear) were closed specifically by adding `file.chmod(0o600)` *after* open to tighten pre-existing files; the migration replaced that with the comment above, which documents the weaker behavior.

**Attack path:** Identical preconditions to SF-022 (already accepted as a valid, if low-likelihood, threat by the project): on a multi-user system an attacker who can create `~/.<app>_history` (or a `$APP_HISTORY`-redirected path in a shared dir) pre-creates it at `0o644`. `createFile(.truncate=false, .permissions=0o600)` opens the existing file **without** changing its mode (POSIX `open` does not apply create-mode to an existing file), so subsequent appended history — which can contain sensitive typed commands — lands in a world-readable file. Unlike SF-022's resolution, nothing later tightens it.

**Impact:** Local disclosure of command history to other users/UIDs; regression of two certified-Resolved controls.

**Remediation:** Re-add post-open enforcement for pre-existing files — a working `compat.chmod` (see NEW-001/NEW-005) called after `createFile` in both `appendLine` and `clear`, **or** stat-after-open and refuse/repair if mode is more permissive than 0o600. Restore the SF-022/SF-024 regression intent. Add a test that pre-creates the file at 0o644 and asserts 0o600 after the first append and after `clear()`.

**Verification:** Pre-create at 0o644 → append → `statFile` mode == 0o600.

---

### NEW-003 — `sync_diamond_deps.py --cascade --apply` is a high-blast-radius, unauthenticated multi-repo mutator (Medium)

**CWE:** CWE-829 Inclusion from untrusted control sphere / CWE-494 Download without integrity check / CWE-78-adjacent (argument-controlled git operations). **OWASP:** A03:2025 Software Supply Chain Failures; A08 Software/Data Integrity. **CIS:** 16.4 (trusted third-party components), 2.4 (allowlisted software), 4 (secure config). **Confidence:** Medium (severity is environment-dependent; this is maintainer tooling, not a library runtime path).

**Evidence (`scripts/sync_diamond_deps.py`):**

- `discover_repos()` (130-158) auto-enumerates sibling repos from `$DEVNW_SIBLING_BASES` (default `~/src/devnw/zig:~/src/devnw/codepros/geode`) **plus the parent of the current repo**, keyed by the `.name` field parsed out of each `build.zig.zon`.
- `cascade(..., apply=True)` (360-521) for each consumer: `git checkout -B gap-diamond-sync <base_commit>` (437), rewrites pins (444-451), `rm -rf zig-pkg .zig-cache` + `zig build --fetch` (`refresh_cache`, 265-271), `git commit` (463-471), `git tag -a <next_free_patch_tag>` (473-483), then **`git push origin <branch>` and `git push origin <tag>`** (484-485) — repeated across every transitive consumer, then rewrites the root repo's pins (495-515).
- The target package/version/commit comes straight from the `--target tls=v0.1.9#<commit>` CLI string (`parse_target`, 353-357); the fetched package hash is whatever `zig fetch` returns for that ref (`zig_pkg_hash`, 220-228) — there is **no signature/provenance check** that the commit corresponds to a reviewed release.
- Remote URLs are reconstructed from `git remote get-url origin` via regex (`_url_for`, 161-172); a sibling checkout with a crafted/mistaken remote could redirect a fetch/pin.

**Attack path / weakness rationale:** This tool, when a maintainer runs `--cascade --apply`, will commit, tag, and **push to the `origin` of every sibling repo it auto-discovers on disk** — including repos the maintainer did not intend to touch (anything matching the discovery bases or sitting next to the current repo). A diamond "fix" therefore has a blast radius of *N* remote repositories with a single command and no per-repo confirmation. Combined with: (a) no integrity verification of the `--target` commit beyond "zig could fetch it," and (b) `rm -rf` of cache paths derived from `repo_path` (276 — bounded to known cache dir names, so low direct risk but still destructive), the tool is a meaningful supply-chain integrity hazard if invoked with a wrong/hostile `--target`, a poisoned sibling checkout, or in an unexpected working directory. To the script's credit, all subprocess calls use list-arg form (no `shell=True`), so there is **no classic shell injection** — the issue is over-broad, unverified, irreversible privileged operations, not command injection.

**Impact:** Accidental or coerced pushes of dependency-pin changes and tags across multiple repositories; propagation of an unverified package version through the DevNW ecosystem; destructive cache deletion. Worst case is supply-chain tampering of sibling libraries that downstream consumers then pull.

**Remediation:**

- Require an explicit per-repo allowlist or interactive confirmation before any `git push` in `--apply`; print the full target repo list and require typed confirmation.
- Verify the `--target` commit against a signed tag (`git tag -v`) or a pinned allowlist before adopting it.
- Constrain `discover_repos` to an explicit, configured repo list rather than directory globbing of `~/src` and the repo's parent.
- Replace `rm -rf` with `shutil.rmtree` guarded by an assertion that the path is inside the expected repo and ends in a known cache dir name.
- Document that `--apply` is irreversible and must run in a clean, audited environment; gate it behind an env confirmation flag.

**Verification:** Dry-run (`--cascade` without `--apply`) prints the plan; `--apply` refuses to push without confirmation and without a verified target.

---

### NEW-004 — otel dependency pin label/version drift (Low)

**CWE:** CWE-1104 Use of unmaintained/ambiguous third-party component pin. **OWASP:** A08:2025 Data Integrity. **CIS:** 2.1 (software inventory accuracy). **Confidence:** High.

**Evidence:** `build.zig.zon:21-22`:

```zig
.url  = "git+https://gitlab.com/devnw/zig/otel.git?ref=v0.1.8#a43c52592c3c131019fed264da8d8c532c23a531",
.hash = "otel-0.1.7-B0v3lvwMNADEHMtQzsmbCvC6qxWxlBtVcpdTX-Wb5BnV",
```

The URL `ref` says **v0.1.8** while the Zig package hash label is **otel-0.1.7-…**.

**Weakness rationale:** Zig pins integrity to the `.hash`, so the *content* is fixed and this is **not** an exploitable substitution (the `#<commit>` and `.hash` are authoritative). However, the mismatched human-readable version (`ref=v0.1.8` vs label `0.1.7`) is exactly the ambiguity the project's own `detect_diamond_deps.py` exists to prevent at the ecosystem level, and it makes audit/SBOM mapping unreliable — an auditor cannot tell from the manifest which otel version is actually linked. Given the dep is `lazy=true` and only resolved under `-Dwith_otel=true` (which is itself inert per NEW-006), runtime exposure today is nil.

**Remediation:** Re-pin so the `ref`, the resolved tag's commit, and the hash label agree (run `zig fetch --save` against the intended otel tag and commit the canonical triple). Note the result in the dependency inventory.

**Verification:** `zig fetch <url>` yields a hash whose label version matches the `ref` tag.

---

### NEW-005 — `compat.chmod` silent no-op is a latent control failure (Low)

**CWE:** CWE-684 Incorrect provision of specified functionality / CWE-392 Missing report of error condition. **OWASP:** A09:2025 (security-relevant operation fails silently). **CIS:** 16 (secure dev process). **Confidence:** High.

**Evidence:** `src/compat.zig:66-72` (full body is `_ = file; _ = mode;`). It is `pub`, documented as "Set file permissions (replacement for old file.chmod)," returns `!void` (so callers `catch {}` it expecting it might fail), and is already relied upon by `config.zig:168`. Any current or future caller that writes `compat.chmod(f, 0o600) catch {}` believing it hardens permissions is silently wrong — this is the proximate cause of NEW-001 and the un-fixable state behind NEW-002.

**Weakness rationale:** A security primitive that lies about what it does is worse than an absent one: it invites exactly the regression observed here and will defeat future hardening attempts. The `catch {}` idiom at call sites compounds it by discarding even the error channel.

**Remediation:** Implement it against the Zig 0.16 permissions API, or remove the function and all call sites and force callers to set `.permissions` at `createFile` time (the working pattern). Do not ship a stub named `chmod`.

**Verification:** Grep shows no `compat.chmod` call sites, or `compat.chmod` provably changes file mode in a unit test.

---

### NEW-006 — Observability seam hardcoded `enabled = false` (Info)

**Evidence:** `src/observability.zig:43` — `pub const enabled: bool = false;` with a comment (and commit `0137a67`) explaining it was hardcoded to dodge a Zig-0.16 `build_options` module-dedup error, decoupling it from `build_options.with_otel`. Consequently every seam helper short-circuits to a no-op even under `-Dwith_otel=true`, and `observability_init.zig`/the enabled-mode otel path are effectively dead.

**Rationale & disposition:** This is **security-neutral to mildly positive** — it guarantees the otel/network dependency code never runs, shrinking attack surface and removing the lazy `otel` dependency from the effective runtime. It is recorded as Info because it is a correctness/feature-integrity gap (the documented `-Dwith_otel` capability does nothing), not a vulnerability. No action required from a security standpoint; flag to engineering for feature correctness.

---

## 5. Secure Design Notes (verified safe / done well)

- **Terminal-input trust boundary is solid and shows no regression.** `parseKeyEvent`/`getKeyEventLength` (`src/input.zig`) are a bounded, allocation-free state machine over fixed-size reads, fuzz-tested (`tests` in input.zig), and cannot inject. The reverse-i-search loop (`src/search.zig:31-104`) filters input to printable ASCII `0x20–0x7e` (74), routes history results through `appendHistoryFiltered` (85), and applies `replaceNewlinesForDisplay` (102) — SF-013 and SF-029 fixes are present and intact.
- **History/paste sanitization intact.** `text_utils.appendHistoryFiltered` (230-238) strips control chars (SF-009), and `sanitizePasteContent` (243-265) strips embedded `ESC[200~`/`ESC[201~` markers (SF-005). `core.zig` paste handling uses `flushPasteBuffer`→`sanitizePasteContent` (500-507) and the `buffer_full` overflow guards (278-331) — SF-005/SF-016/SF-018 fixes present.
- **Path validation intact and centralized.** `text_utils.isPathSafe` (96-124) rejects relative paths and `..` components, with thorough tests; `resolveEnvOverridePath` (166-187) bounds-checks env names and validates with `isPathSafe` before use (SF-007).
- **Signal handling improved, no regression.** `src/platform.zig` wires `installTerminalSignalHandlers` into `enterRawMode` (238-239) and `removeTerminalSignalHandlers`/`saved_termios=null` into `restoreTerminalMode` (264-265); the handler uses `std.posix.system.*` for cross-platform async-signal-safe restoration (SF-014/SF-025 resolved and portable). SF-027 (non-atomic `saved_termios`) remains validly Won't-Do — SA_RESETHAND one-shot still in place, no new path.
- **Newly-created history files are correctly 0o600** via `createFile(.permissions=…)` — reproduced live. The regression (NEW-002) is only the *pre-existing-file* enforcement.
- **`keywordProvider` dangling-pointer fix (SF-030) intact** — signature is `*const []const u8` and a test now calls `generate` after return (`completion.zig:134,170,397-`).
- **Diamond scripts use list-arg subprocesses (no `shell=True`/`os.system`)** — no shell-injection surface; the comment-aware `.zon` tokenizer correctly avoids stripping `//` inside URL strings.
- **CI integrity posture is reasonable:** Zig tarballs verified against repo-pinned SHA-256 (SF-020), `sha256sum --check --strict`; secrets/SAST/dependency/SBOM components run; `detect-diamond-deps` runs read-only in pre-commit and the destructive `sync_diamond_deps` is **not** auto-wired into any hook/CI (confirmed).

---

## 6. Coverage Gaps & Questions

- **No build/test execution of the full suite** was performed in this review (read + targeted repro only). The NEW-001 repro used a standalone program mirroring the exact `createFile` call; recommend adding the permission tests proposed above and running `zig build test`.
- **`compat.chmod` real implementation:** is the Zig 0.16 `File`/`Dir` permissions API (`setPermissions`/`Permissions`) usable here? The whole NEW-001/002/005 cluster collapses to "create with `.permissions=0o600` everywhere + implement-or-delete chmod." Confirm the intended API.
- **`has_executable_bit` gate:** `config.zig:167` guards the (no-op) chmod behind `Permissions.has_executable_bit`. On filesystems/platforms lacking that bit the call is skipped entirely — verify the chosen fix doesn't reintroduce a platform-specific gap.
- **Diamond cascade runtime model:** who runs `--apply`, in what environment, and against which sibling set? The NEW-003 severity is bounded by that. If it only ever runs in an isolated, audited maintainer sandbox with a fixed repo list, treat as Low; if it can run on a developer laptop with arbitrary `~/src` siblings, Medium stands.
- **otel pin (NEW-004):** is the intended otel version 0.1.7 or 0.1.8? The manifest is self-contradictory.
- No `docs/THREAT_MODEL.md` / `docs/SECURITY_REQUIREMENTS.md` exist; the file-permission threat model is inferred from prior SF rationale.

### Answers to the 4 contract questions

1. **New findings beyond the 30 tracked SF-IDs?** Yes — six: NEW-001 (High), NEW-002 (Medium), NEW-003 (Medium), NEW-004 (Low), NEW-005 (Low), NEW-006 (Info).
2. **Regressions in previously-resolved findings?** Yes. **SF-001/SF-023** (config world-readable) regressed → NEW-001. **SF-022/SF-024** (history pre-existing-file permission enforcement) regressed → NEW-002. Both were caused by the Zig-0.16 migration replacing real `chmod` calls with a no-op shim. All other resolved controls (SF-005/007/009/013/014/016/018/020/025/029/030) verified intact against current source.
3. **Issues in the recently-added scripts / dependency-pin commits?** Yes — NEW-003 (cascade push/`rm -rf` blast radius, no integrity check/confirmation) and NEW-004 (otel pin label/version drift). `detect_diamond_deps.py` itself is sound and read-only; no shell injection in either script.
4. **CI / supply-chain posture of `.gitlab-ci.yml` and `build.zig.zon`?** Generally good: SHA-256-pinned Zig with `--check --strict`, lazy single dependency, security/SBOM components, and the destructive diamond tool kept out of automated hooks. Weaknesses: CI components and pre-commit hooks remain version/tag-pinned not SHA-pinned (already accepted as SF-012 Won't-Do — no new path found, not re-reported), and the `build.zig.zon` otel pin label/version drift (NEW-004).

---

## 7. Prioritized Next Actions

1. **NEW-001 (High) — fix now.** Add `.permissions = @enumFromInt(0o600)` to `config.zig:163`; implement or delete `compat.chmod`; add a `saveToFile` permission regression test. (Closes the certified-control regression.)
2. **NEW-002 (Medium).** Restore pre-existing-file permission enforcement in `history.zig` `appendLine`/`clear` (working `compat.chmod` after open, or stat-and-repair); add a pre-created-0o644 regression test.
3. **NEW-005 (Low, but root cause of 1&2).** Decide: implement `compat.chmod` against the 0.16 API, or remove it and standardize on `createFile(.permissions=…)` everywhere. Don't ship a `chmod` that no-ops.
4. **NEW-003 (Medium).** Add confirmation + explicit repo allowlist + target signature/allowlist verification before any push in `sync_diamond_deps.py --apply`; harden the `rm -rf`.
5. **NEW-004 (Low).** Re-pin otel so `ref`, commit, and hash label agree; update the dependency inventory.
6. **NEW-006 (Info).** Route to engineering: either restore `enabled = build_options.with_otel` (resolving the module-dedup issue) or document `-Dwith_otel` as currently inert.
7. **Process.** Add the missing permission tests to the suite so a future migration cannot silently regress SF-001/022/023/024 again, and re-verify resolved controls against *current* source (not stale line numbers) in the next cycle.

*No secrets, no RCE, no auth bypass, no remotely-exploitable runtime vulnerability found. The dominant theme this cycle is a permission-hardening regression introduced by the Zig 0.16 compatibility migration, plus a high-blast-radius maintainer supply-chain tool.*
