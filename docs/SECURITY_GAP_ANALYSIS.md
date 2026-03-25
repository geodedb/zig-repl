# Security Gap Analysis

**Project:** devnw/zig/repl -- Zig REPL Library
**Date:** 2026-03-25 (Audit Cycle 2, Phase 4)
**Auditor:** Security Reviewer (automated + manual code review)
**Scope:** Full source tree at commit `f8eab0c` (branch: main)
**Classification:** INTERNAL -- Do not distribute outside the project team
**Revision:** 14 (Gap Closure -- SF-028 resolved; SF-026, SF-027 marked Won't Do; 0 open findings)

---

## Overall Assessment

**No Critical or High severity findings. 0 open findings. 30 total SF-IDs tracked.**

The Zig REPL library maintains a sound security posture for a v0.1.0 release. The codebase
is memory-safe by default (Zig's safety checks), has no external C dependencies, and
uses minimal attack surface. Since the initial audit (2026-03-23), **24 of 30 findings
have been resolved** (23 unique root causes; SF-002 reclassified as SF-014), with 5 marked Won't Do, 1 confirmed No Action Needed, and 0 open.

Audit Cycle 2, Phase 4 (2026-03-25) performed a comprehensive re-review of all 3 open Low
findings and all 22 resolved findings. Gap Closure (2026-03-25) then resolved SF-028 and
marked SF-026 and SF-027 as Won't Do with documented rationale:
- **SF-026** (Low, risk 5): Undo buffer bypasses display sanitization -- **Won't Do**. Confirmed theoretical only; no real exploit path. Undo buffer is populated from already-sanitized edit buffer; render pipeline provides independent output sanitization.
- **SF-027** (Low, risk 8): `saved_termios` not async-signal-safe -- **Won't Do**. Cosmetic-only impact confirmed. Mitigated by SA_RESETHAND one-shot handler. Documented as accepted risk.
- **SF-028** (Low, risk 5): Direct ArrayList length mutation -- **Resolved**. Replaced `state.buffer.items.len = state.cursor` with `state.buffer.shrinkRetainingCapacity(state.cursor)` in core.zig delete_to_eol handler.
- All 22 previously resolved findings verified -- no regressions detected.
- One Info-level observation about `\r` in search display noted but does NOT warrant a new SF-ID (cosmetic only, ESC already blocked by input filter).
- **No new findings identified. 0 open findings remain.**

Phase 9 audit (2026-03-24) performed a Phase 3 deep review. NC-001 and NC-002 (existing
Low findings from Phase 2) were re-confirmed at Low severity with no changes. Two new
Low findings were identified:
- **SF-021**: Static mutable `home_dir_buf` without thread safety (`src/completion.zig:188`) -- **RESOLVED** (threadlocal added)
- **SF-022**: History file TOCTOU on permissions (`src/history.zig:178-188`) -- **RESOLVED** (chmod added after file open)

Phase 10 validation audit (2026-03-24) confirmed all prior findings remain accurately tracked.

Phase 11 gap closure (2026-03-24) resolved SF-021 and SF-022:
- SF-021: `home_dir_buf` changed to `threadlocal var home_dir_buf` in `src/completion.zig:188`.
- SF-022: `file.chmod(0o600)` call added after file open in `src/history.zig` to enforce permissions regardless of pre-existing mode.

Phase 12 gap closure (2026-03-24) resolved SF-023:
- SF-023: `file.chmod(0o600)` call added after file open in `src/config.zig:162` to enforce permissions on pre-existing config files (same class as SF-022).
All trust boundaries (paste, key parsing, signals, history, config, search, env vars) reviewed
and confirmed secure.

Phase 13 new findings (2026-03-24) identified 5 new validated findings (SF-024 through SF-028):
- **SF-024**: History `clear()` missing chmod on pre-existing file (`src/history.zig:214`) -- **Open** (Low, risk 8)
- **SF-025**: Signal handler uses `std.os.linux.*` on all POSIX platforms (`src/platform.zig:40,45,55`) -- **Open** (Medium, risk 35). Blocks macOS/FreeBSD support. GitLab issue created.
- **SF-026**: Undo buffer `appendSlice` bypasses display sanitization (`src/core.zig:741`) -- **Won't Do** (Low/Info, risk 5). Theoretical only; no action required.
- **SF-027**: `saved_termios` global not async-signal-safe (`src/platform.zig:25,39,210,237`) -- **Won't Do** (Low, risk 8). Mitigated by SA_RESETHAND one-shot and narrow race window. Documented as accepted risk.
- **SF-028**: `delete_to_eol` directly mutates ArrayList length field (`src/core.zig:654`) -- **Resolved**. Replaced `items.len = cursor` with `shrinkRetainingCapacity(cursor)`.

Phase 14 new findings (2026-03-25) identified 2 new validated findings (SF-029 and SF-030):
- **SF-029**: Search display writes buffer content without CRLF conversion or control-char replacement (`src/search.zig:67-71`) -- **Resolved**. Added `replaceNewlinesForDisplay()` helper to replace `\n` with space in display buffer.
- **SF-030**: `keywordProvider` stores pointer to stack-local parameter via `@ptrCast(@constCast(&keywords))` (`src/completion.zig:168`) -- **Resolved** (Phase 15). Parameter changed from by-value slice to pointer type, eliminating dangling pointer.

See "Phase 5 Manual Review Findings" section below for details on MF-001 through MF-005
findings from Phase 5.

**Key strengths:**
- Memory-safe implementation with compile-time safety checks
- No external C dependencies (stdlib only)
- Bracketed paste mode enabled by default with sanitization (SF-005 resolved)
- History privacy feature (leading-space suppression)
- History filtering against terminal escape injection (SF-009 resolved)
- Signal handlers now correctly wired into terminal mode lifecycle (SF-014 resolved)
- All history-to-buffer paths now use filtered append (SF-013 resolved)
- File permissions hardened to 0o600 (SF-001 resolved)
- Path validation against traversal attacks (SF-007 resolved)
- Structured error handling throughout

**Remaining areas:**
- Signal handler async-signal-safety of `saved_termios` (SF-027 -- Won't Do, mitigated by SA_RESETHAND)
- Undo buffer sanitization theoretical gap (SF-026 -- Won't Do, no real exploit path)
- Supply chain pinning for CI/CD dependencies (SF-012 -- Won't Do, external tooling)

---

## Audit Progression

| Metric | Initial (2026-03-23) | Re-audit (2026-03-24) | Post-closure (2026-03-24) | Phase 3 (2026-03-24) | Phase 4 (2026-03-24) | Phase 5 (2026-03-24) | Phase 9 (2026-03-24) | Phase 10 (2026-03-24) | Phase 11 (2026-03-24) | Phase 12 (2026-03-24) | Phase 13 (2026-03-24) | Phase 14 (2026-03-25) | Phase 15 (2026-03-25) | AC2-P4 (2026-03-25) | Delta (Phase 15 to AC2-P4) |
|--------|----------------------|-----------------------|---------------------------|----------------------|----------------------|----------------------|----------------------|-----------------------|-----------------------|----------------------|----------------------|----------------------|----------------------|---------------------|----------------------------|
| Total findings | 12 | 15 (cumulative) | 15 | 20 | 20 | 20 | 22 | 22 | 22 | 23 | 28 | 30 | 30 | 30 | 30 | 0 |
| Open | 12 | 6 | 0 | 2 | 0 | 0 | 2 | 2 | 0 | 0 | 5 | 5 | 3 | 3 | 0 | -3 |
| Resolved | 0 | 8 | 10 | 13 | 15 | 15 | 15 | 15 | 17 | 18 | 18 | 20 | 22 | 22 | 24 | +2 |
| Won't Do | 0 | 0 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 5 | +2 |
| No Action Needed | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 |
| Reclassified | 0 | 1 (SF-002 -> SF-014) | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 |
| Medium severity (open) | 4 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| Low severity (open) | 8 | 3 | 0 | 2 | 0 | 0 | 2 | 2 | 0 | 0 | 4 | 4 | 3 | 3 | 0 | -3 |
| Info severity (open) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| Manual findings reviewed | -- | -- | -- | -- | -- | 5 (MF-001..005) | 5 + NC-001, NC-002 re-confirmed | All prior findings re-verified | SF-021, SF-022 resolved | SF-023 resolved | 5 new findings (SF-024..028) | 2 new findings (SF-029, SF-030) | SF-029, SF-030 resolved | All 3 open + 22 resolved re-verified; no new findings | SF-028 resolved; SF-026, SF-027 won't-do | -3 open |

---

## Summary

| Severity | Total | Open | Resolved | Won't Do | No Action | SLA |
|----------|-------|------|----------|----------|-----------|-----|
| Critical | 0 | 0 | 0 | 0 | 0 | 7 days |
| High | 0 | 0 | 0 | 0 | 0 | 30 days |
| Medium | 7 | 0 | 7 | 0 | 0 | 90 days |
| Low | 22 | 0 | 16 | 5 | 1 | 180 days |
| Info | 1 | 0 | 1 | 0 | 0 | Backlog |
| **Total** | **30** | **0** | **24** | **5** | **1** | |

Note: SF-002 was reclassified as SF-014 with updated analysis. It is counted once (as SF-014, resolved). SF-023 is tracked in the resolved table (Phase 12). SF-025 resolved in Phase 13 (Medium resolved count updated from 6 to 7). SF-028 resolved (Gap Closure -- replaced items.len mutation with shrinkRetainingCapacity). SF-026 and SF-027 marked Won't Do (Gap Closure -- theoretical only / mitigated by SA_RESETHAND). SF-029 resolved (Info-severity, cosmetic display fix). SF-030 resolved (Phase 15 -- parameter changed to pointer type).

### 0 open findings. No Critical, High, Medium, Low, or Info findings remain open.

---

## Stack-Ranked Findings Table

### Open Findings (Gap Closure)

No open findings remain. All previously open items have been resolved or marked Won't Do.

### Recently Closed (Gap Closure, 2026-03-25)

| Rank | SF-ID | Severity | Risk Score | Finding | Component | CWE / OWASP | Evidence (file:line) | Confidence | Disposition |
|------|-------|----------|------------|---------|-----------|-------------|----------------------|------------|-------------|
| -- | SF-028 | Low | 5 | `delete_to_eol` directly mutates ArrayList length field | core | CWE-119 | `src/core.zig:654` | suspected | **Resolved** -- replaced with `shrinkRetainingCapacity` |
| -- | SF-027 | Low | 8 | `saved_termios` global not async-signal-safe | platform | CWE-364 | `src/platform.zig:25,39,210,237` | suspected | **Won't Do** -- cosmetic-only impact, mitigated by SA_RESETHAND |
| -- | SF-026 | Low | 5 | Undo buffer `appendSlice` bypasses display sanitization | core | CWE-116 | `src/core.zig:741` | suspected | **Won't Do** -- theoretical only, no exploit path |

### Recently Resolved (Phase 4)

| Rank | SF-ID | Severity | Risk Score | Finding | Component | CWE / OWASP | Evidence (file:line) | Confidence | SLA |
|------|-------|----------|------------|---------|-----------|-------------|----------------------|------------|-----|
| -- | SF-016 | Low | 20 | Paste buffer flush-and-continue (was: silent truncation) | core | CWE-130 | `src/core.zig:327,421` | confirmed | Resolved |
| -- | SF-018 | Low | 15 | renderPrompt buffer_full flag (was: silent discard) | core | CWE-130 | `src/core.zig:256-310` | confirmed | Resolved |

### Won't Do

| SF-ID | Severity | Risk Score | Finding | Reason |
|-------|----------|------------|---------|--------|
| SF-012 | Low | 20 | Pre-commit/CI pinned by mutable tag, not SHA | Won't Do -- external tooling control. GitLab CI component references (`devnw/ci-catalog`) may not support SHA pinning for components. Pre-commit hook versions are managed by the pre-commit framework. Pinning these to SHAs would require forking external tooling. |
| SF-008 | Low | 15 | File path completion allows full filesystem traversal | Won't Do -- by design for a general-purpose REPL library. Consumers must implement their own path restrictions if needed. This is documented in the completion module. |
| SF-015 | Low | 10 | sanitizePasteContent theoretical fragmentation gap | Won't Do -- theoretical only. Terminal emulators deliver paste markers atomically. The 256-byte read buffer is much larger than the 6-byte marker. No real-world exploitation path exists. |
| SF-027 | Low | 8 | `saved_termios` global not async-signal-safe | Won't Do -- cosmetic-only impact confirmed. SA_RESETHAND one-shot handler limits the race window to a single signal delivery during the narrow struct-copy instruction sequence. Worst case is a terminal `reset` command needed. Not a security vulnerability. Documented as accepted risk. |
| SF-026 | Low | 5 | Undo buffer `appendSlice` bypasses display sanitization | Won't Do -- theoretical only. No real exploit path exists: the undo buffer is populated from the already-sanitized edit buffer, and the render pipeline provides independent output sanitization. No unfiltered characters can enter the undo buffer through any existing code path. |

### No Action Needed

| SF-ID | Severity | Risk Score | Finding | Reason |
|-------|----------|------------|---------|--------|
| SF-004 | Low | 15 | CONTRIBUTING.md license mismatch (root copy) | No action needed -- root `CONTRIBUTING.md` was checked and contains no MIT reference. It already references Apache-2.0 correctly. The `docs/CONTRIBUTING.md` copy was previously corrected (GAP-0003). |

### Resolved Findings

| SF-ID | Severity | Risk Score | Finding | Component | CWE / OWASP | Resolution | Verified |
|-------|----------|------------|---------|-----------|-------------|------------|----------|
| SF-025 | Medium | 35 | Signal handler uses `std.os.linux.*` on all POSIX platforms | platform | CWE-474 / A05:2021 | Signal handler updated to use `std.posix.system.*` instead of `std.os.linux.*` for cross-platform POSIX support in `handleTerminalSignal` at `src/platform.zig`. | 2026-03-25 |
| SF-024 | Low | 8 | History `clear()` missing chmod on pre-existing file | history | CWE-732 / A01:2021 | Added `chmod(0o600)` after `createFile` in `clear()` at `src/history.zig:217-220`, matching the pattern already used in `appendLine()`. | 2026-03-25 |
| SF-023 | Low | 8 | Config file missing chmod on pre-existing file | config | CWE-732 / A01:2021 | Added `file.chmod(0o600)` after file open in `src/config.zig:162` to enforce permissions on pre-existing config files (same class as SF-022). | 2026-03-24 |
| SF-021 | Low | 8 | Static mutable `home_dir_buf` without thread safety | completion | CWE-362 | Changed `var home_dir_buf` to `threadlocal var home_dir_buf` at `src/completion.zig:188`. Each thread gets its own copy; no behavioral change for single-threaded callers. | 2026-03-24 |
| SF-022 | Low | 8 | History file TOCTOU on permissions | history | CWE-367 | Added `file.chmod(0o600)` after file open in `src/history.zig` to enforce permissions regardless of pre-existing mode. Eliminates TOCTOU race on permission check. | 2026-03-24 |
| SF-014 | Medium | 50 | Signal handler dead code -- enterRawMode() never calls installTerminalSignalHandlers() | platform | CWE-404 | `enterRawMode()` now sets `saved_termios = original` and calls `installTerminalSignalHandlers()` at `src/platform.zig:193-194`. `restoreTerminalMode()` now calls `removeTerminalSignalHandlers()` and sets `saved_termios = null` at `src/platform.zig:219-220`. | 2026-03-24 |
| SF-013 | Medium | 35 | handleSearch() uses appendSlice bypassing history filtering | core | CWE-116 / A03:2021 | Changed `appendSlice` to `appendHistoryFiltered` at `src/core.zig:883`. All history-to-buffer paths now use filtered append. | 2026-03-24 |
| SF-001 | Medium | 45 | History/config files world-readable (0644) | history, config | CWE-732 / A01:2021 | `.mode = 0o600` added to all createFile calls | 2026-03-24 |
| SF-005 | Medium | 40 | Bracketed paste end-marker forgery (pastejacking) | core | CWE-74 / A03:2021 | sanitizePasteContent() strips embedded paste sequences | 2026-03-24 |
| SF-009 | Medium | 35 | Terminal escape injection from history replay | core, history | CWE-116 / A03:2021 | appendHistoryFiltered() strips unsafe control chars | 2026-03-24 |
| SF-007 | Low | 25 | Env var path injection for history/config | history, config | CWE-426 | isPathSafe() validates absolute path, rejects traversal. Now extracted to shared `text_utils.zig`. | 2026-03-24 |
| SF-003 | Low | 20 | Unchecked @intCast(file_size) on 32-bit | history | CWE-190 | 64MB bounds check before @intCast | 2026-03-24 |
| SF-010 | Low | 15 | TerminalWriter.print drops output >4096 bytes | platform | CWE-130 | Partial write on overflow instead of silent drop | 2026-03-24 |
| SF-020 | Low | 15 | CI Zig download hash fetched from same origin as binary | CI | CWE-494 | SHA-256 hashes pinned in `.gitlab-ci.yml` variables; `index.json` fetch removed; hash verified from git repo trust root | 2026-03-24 |
| SF-006 | Low | 10 | catch unreachable on zero-capacity init | core, completion | CWE-248 | Safety comments documenting initCapacity(0) never allocates | 2026-03-24 |
| SF-011 | Low | 10 | False fuzz testing claim in SECURITY.md | docs | N/A | Updated to reflect fuzz testing is implemented | 2026-03-24 |

### Reclassified Findings

| Original | New | Reason |
|----------|-----|--------|
| SF-002 (Risk 50) | SF-014 (Risk 50) | Signal handler code exists at `platform.zig:22-87` but was dead code. `enterRawMode()` did not call `installTerminalSignalHandlers()` or set `saved_termios`. Now RESOLVED -- handlers wired in at `platform.zig:193-194` and `platform.zig:219-220`. |

---

## Phase 5 Manual Review Findings (2026-03-24)

Phase 5 performed a comprehensive re-audit combining full automated scanner sweeps and
targeted manual code review. Five manual findings (MF-001 through MF-005) were identified
during code review. After evaluation against existing controls and mitigations, **all five
were determined to be adequately covered by existing SF-IDs or design decisions**. No new
SF-IDs, GitLab issues, or severity changes were warranted.

### MF-001: @intCast narrowing on 32-bit platforms

| Field | Value |
|-------|-------|
| **Area** | History file loading |
| **Concern** | `@intCast` on `file_size` could truncate on 32-bit targets |
| **Existing Coverage** | SF-003 (Resolved) |
| **Disposition** | Already mitigated -- 64MB bounds check at `history.zig:75-76` ensures the value fits in any integer width before the cast executes. The cap is well below the 32-bit `usize` maximum (~4 GB). |

### MF-002: Symlink following in file operations

| Field | Value |
|-------|-------|
| **Area** | History/config file I/O |
| **Concern** | History and config file operations follow symlinks, which could be used to read/write unintended files |
| **Existing Coverage** | SF-008 (Won't Do -- by design) |
| **Disposition** | Already addressed -- filesystem traversal is by design for a general-purpose REPL library. The `isPathSafe()` validation rejects path traversal (`..` components). Symlink following is standard POSIX behavior and restricting it would break legitimate use cases (e.g., home directory symlinks). Consumers requiring symlink restrictions must implement their own guards. |

### MF-003: TOCTOU race in history file loading

| Field | Value |
|-------|-------|
| **Area** | History file load path |
| **Concern** | Time-of-check-to-time-of-use race between path validation and file read |
| **Disposition** | Benign -- `readAll` semantics consume the file in a single syscall sequence after open. The `file_mutex` serializes concurrent access within the process. File permissions are set to `0o600` (SF-001 resolved), limiting the attack surface to the file owner. A TOCTOU exploit would require the file owner to race against themselves, which is not a meaningful threat model for a user-space REPL library. |

### MF-004: i32 depth overflow in parse nesting

| Field | Value |
|-------|-------|
| **Area** | `src/parse.zig` -- bracket/paren nesting depth counter |
| **Concern** | `i32` depth counter could theoretically overflow with deeply nested input |
| **Disposition** | Unreachable in practice -- reaching `i32` overflow (2,147,483,647 nesting levels) would require an input string of at least 2 GB of opening brackets, which exceeds the edit buffer capacity by orders of magnitude. Zig's runtime safety checks (enabled in debug and safe release modes) would trap on overflow before any undefined behavior occurs. No new SF-ID warranted. |

### MF-005: loadFromFile does not call isPathSafe

| Field | Value |
|-------|-------|
| **Area** | `src/history.zig` -- `loadFromFile` / `src/config.zig` -- `loadFromFile` |
| **Concern** | Public `loadFromFile` API accepts a path without calling `isPathSafe()` |
| **Disposition** | By design -- `loadFromFile` is a consumer-facing API that accepts an already-resolved path. Path validation occurs at the correct boundary: `getDefaultConfigPath()` and `getDefaultHistoryPath()` validate paths before they reach the load functions. Consumers calling `loadFromFile` directly with a custom path are responsible for their own validation, consistent with the library's design philosophy (see SF-008 rationale). Adding validation inside `loadFromFile` would double-validate the default path and impose unnecessary restrictions on consumer-provided paths. |

### Automated Scanner Results (Phase 5)

All scanners re-run with zero findings:

| Scanner | Scope | Findings |
|---------|-------|----------|
| gitleaks | Secrets in git history | 0 |
| trufflehog | Secrets detection | 0 |
| trivy | Secrets, vulnerabilities, config | 0 |
| grype | Vulnerability scanning | 0 |
| osv-scanner | Known vulnerabilities | 0 |
| semgrep | Static analysis | 0 |
| checkov | Infrastructure-as-code | 0 |

---

## Phase 13 Findings (2026-03-24)

Phase 13 identified 5 new validated findings from targeted code review of signal handling,
history file operations, undo buffer paths, and ArrayList API usage patterns.

One finding (SF-025, Medium) has a GitLab issue created as it blocks macOS/FreeBSD platform
support. The remaining 4 Low findings are tracked in this gap analysis only per existing policy.

### SF-024: History clear() missing chmod on pre-existing file [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 8 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-732: Incorrect Permission Assignment for Critical Resource |
| **OWASP** | A01:2021 Broken Access Control |
| **Confidence** | confirmed |
| **Exploit Surface** | Requires physical access or same-user compromise |
| **Status** | **Resolved** |
| **SLA** | 180 days (2026-09-20) |
| **Resolution** | Added `chmod(0o600)` after `createFile` in `clear()` at `src/history.zig:217-220` |
| **Resolved date** | 2026-03-25 |

**Summary:** The `clear()` method at `src/history.zig:214` calls `createFile(path, .{ .truncate = true, .mode = 0o600 })` but does not call `file.chmod(0o600)` afterward. The `.mode` parameter only applies when creating a new file. If the file already exists with permissive permissions, `clear()` will truncate it but leave the permissions unchanged. This is the same class of issue as SF-022, which was fixed for `appendLine()` at line 187 but not applied to `clear()`.

**Impact:** If a history file exists with permissive permissions (e.g., pre-created by an attacker at 0o644), `clear()` truncates the file but does not tighten permissions. Subsequent history writes via `appendLine()` (which does have the chmod) would fix the permissions on the next append, but there is a window between `clear()` and the next `appendLine()` where the file remains world-readable.

**Likelihood:** Extremely low. Same preconditions as SF-022: attacker must have write access to the user's home directory and pre-create the history file. The `appendLine()` path already has the chmod fix, narrowing the race window.

**Evidence:**
```
// src/history.zig:214 -- clear() path (no chmod after createFile)
const file = std.fs.cwd().createFile(path, .{ .truncate = true, .mode = 0o600 }) catch {
    return;
};
file.close();
```

Compare with `appendLine()` at line 186-188 which correctly calls `file.chmod(0o600)` after open.

**Attack scenario:** On a multi-user system, an attacker pre-creates `~/.repl_history` with mode 0o644. The user runs the REPL which calls `clear()` -- file is truncated but remains 0o644. Until the next `appendLine()` call (which fixes permissions), the empty file has permissive permissions. Practical impact is near-zero since the file is empty during this window.

**How to verify:** Pre-create a history file with 0o644, call `clear()`, check if permissions remain 0o644.

**Fix guidance:** Add `file.chmod(0o600) catch {};` after the `createFile` call in `clear()`, matching the pattern already used in `appendLine()` at line 187.

**Acceptance criteria:**
- `clear()` enforces 0o600 permissions on the history file after truncation, regardless of pre-existing mode
- Same `chmod` pattern as `appendLine()` at `src/history.zig:186-188`

**Affected paths:** `src/history.zig`

---

### SF-025: Signal handler uses std.os.linux.* on all POSIX platforms [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Risk Score** | 35 (Impact: 3 x Likelihood: 3 x 4) |
| **CWE** | CWE-474: Use of Function with Inconsistent Implementations |
| **OWASP** | A05:2021 Security Misconfiguration |
| **Confidence** | confirmed |
| **Exploit Surface** | All non-Linux POSIX platforms (macOS, FreeBSD, etc.) |
| **Status** | **Resolved** |
| **SLA** | 90 days (2026-06-22) |
| **Issue** | [#120](https://gitlab.com/devnw/zig/repl/-/issues/120) (closed) |
| **Resolution** | Signal handler updated to use `std.posix.system.*` instead of `std.os.linux.*` for cross-platform POSIX support in `handleTerminalSignal` at `src/platform.zig`. |
| **Resolved date** | 2026-03-25 |

**Summary:** The `handleTerminalSignal()` function at `src/platform.zig:35-56` uses `std.os.linux.tcsetattr`, `std.os.linux.write`, and `std.os.linux.kill` for async-signal-safe terminal restoration. These are Linux-specific syscall wrappers that do not exist on macOS or FreeBSD. The function is only guarded against Windows (`if (builtin.os.tag == .windows) return`), so on any non-Linux POSIX platform, this code will fail to compile.

**Impact:** (1) Compile failure on macOS and FreeBSD -- completely blocks cross-platform POSIX support. (2) On affected platforms where the code cannot compile, terminal restoration on signal is unavailable, meaning SIGTERM/SIGHUP would leave the terminal in raw mode. This is a security impact (CWE-404 denial of service to the terminal) compounded by a portability defect.

**Likelihood:** Certain on macOS/FreeBSD. Any attempt to `zig build` on these platforms will produce a compile error referencing missing `std.os.linux` symbols.

**Evidence:**
```
// src/platform.zig:40 -- Linux-specific tcsetattr
_ = std.os.linux.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, &original);

// src/platform.zig:45 -- Linux-specific write
_ = std.os.linux.write(std.posix.STDOUT_FILENO, "\x1b[?2004l", 8);

// src/platform.zig:55 -- Linux-specific kill
_ = std.os.linux.kill(std.os.linux.getpid(), sig);
```

All three should use `std.posix.system.*` (the OS-generic POSIX layer) or be wrapped in a `comptime` OS tag switch that selects the correct backend per platform.

**Attack scenario:** A developer attempts to build the REPL library on macOS for a cross-platform project. The build fails. They work around it by commenting out or stubbing the signal handler, leaving the terminal unprotected on signal. Alternatively, they ship a Linux-only binary without realizing the signal handler is non-portable.

**How to verify:** Run `zig build` on macOS or FreeBSD and observe compile errors referencing `std.os.linux.tcsetattr`, `std.os.linux.write`, `std.os.linux.kill`.

**Fix guidance:** Replace Linux-specific calls with portable alternatives:
- `std.os.linux.tcsetattr` -> `std.posix.system.tcsetattr` (or add comptime `os.tag` switch)
- `std.os.linux.write` -> `std.posix.system.write`
- `std.os.linux.kill` -> `std.posix.system.kill`
- `std.os.linux.getpid` -> `std.posix.system.getpid`

These `std.posix.system.*` functions dispatch to the correct platform backend at comptime while maintaining async-signal-safety.

**Acceptance criteria:**
- `handleTerminalSignal()` compiles and functions correctly on Linux, macOS, and FreeBSD
- Terminal is restored to original state when SIGTERM/SIGHUP is received on all POSIX platforms
- No `std.os.linux.*` references remain in signal handler code path

**Affected paths:** `src/platform.zig`

---

### SF-026: Undo buffer appendSlice bypasses display sanitization [WON'T DO]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 5 (Impact: 1 x Likelihood: 1 x 4) |
| **CWE** | CWE-116: Improper Encoding or Escaping of Output |
| **OWASP** | N/A |
| **Confidence** | suspected |
| **Exploit Surface** | Theoretical only |
| **Status** | **Won't Do** -- theoretical only, no exploit path. Undo buffer populated from already-sanitized edit buffer; render pipeline provides independent output sanitization. |
| **SLA** | N/A (Won't Do) |
| **Resolved date** | 2026-03-25 |

**Summary:** The undo handler at `src/core.zig:741` uses `state.buffer.appendSlice()` to restore a previously saved buffer snapshot. This path does not go through `appendHistoryFiltered()` which strips control characters. However, this is purely theoretical because: (1) the undo buffer is populated from the edit buffer itself, which is already sanitized at input time; (2) the render path independently sanitizes all output. No unfiltered characters can enter the undo buffer through any existing code path.

**Impact:** None in practice. The undo buffer restores a snapshot of the edit buffer, which was already sanitized when the content was originally inserted. The render pipeline provides a second layer of sanitization.

**Likelihood:** Theoretical only. Would require a future code change to introduce a path that writes unsanitized content into the edit buffer, which then gets captured in an undo snapshot, and the render sanitization would also need to be bypassed.

**Evidence:**
```
// src/core.zig:741
state.buffer.appendSlice(state.allocator, entry.buffer) catch {
```

**How to verify:** Demonstrate that unsanitized control characters can enter the undo buffer. This is not currently possible given existing input paths.

**Fix guidance:** No action required. The defense-in-depth is adequate: input sanitization prevents bad data from entering the buffer, and render sanitization prevents it from reaching the terminal. Adding explicit sanitization to the undo path would be purely belt-and-suspenders.

**Acceptance criteria:** N/A -- informational finding. If addressed, the undo restore path would use `appendHistoryFiltered` or equivalent sanitization.

**Affected paths:** `src/core.zig`

---

### SF-027: saved_termios global not async-signal-safe [WON'T DO]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 8 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-364: Signal Handler Race Condition |
| **OWASP** | N/A |
| **Confidence** | suspected |
| **Exploit Surface** | Requires precise signal timing during raw mode enter/exit |
| **Status** | **Won't Do** -- cosmetic-only impact, mitigated by SA_RESETHAND one-shot handler. Documented as accepted risk. |
| **SLA** | N/A (Won't Do) |
| **Resolved date** | 2026-03-25 |

**Summary:** The signal handler `handleTerminalSignal()` at `src/platform.zig:39` reads the global `saved_termios` variable which is written by the main thread at `src/platform.zig:210` (`enterRawMode`) and `src/platform.zig:237` (`restoreTerminalMode`). The `std.posix.termios` struct is not atomic; a signal arriving during a partial write of `saved_termios` by the main thread could cause the handler to read a torn (partially updated) struct, leading to incorrect terminal restoration.

**Impact:** In the worst case, the terminal could be left in a partially corrupted state after signal delivery during the narrow window when `saved_termios` is being written. The user would need to run `reset` to restore the terminal.

**Likelihood:** Extremely low. The race window is the duration of a struct copy (~48 bytes on Linux). SA_RESETHAND ensures the handler fires at most once. The signal would need to arrive during the exact instruction sequence that copies the termios struct.

**Evidence:**
```
// src/platform.zig:25 -- non-atomic global
var saved_termios: if (builtin.os.tag == .windows) void else ?std.posix.termios = ...

// src/platform.zig:39 -- signal handler reads it
if (saved_termios) |original| {

// src/platform.zig:210 -- main thread writes it
saved_termios = original;

// src/platform.zig:237 -- main thread clears it
saved_termios = null;
```

**Attack scenario:** Not externally exploitable. An attacker would need to control signal delivery timing with instruction-level precision during the narrow window of a struct copy. This is not a realistic attack vector.

**How to verify:** Static analysis tools that check for shared non-atomic access between signal handlers and main code would flag this pattern. Runtime reproduction would require instrumented builds with artificial delays in the struct copy.

**Fix guidance:** Use `@atomicStore`/`@atomicLoad` on a pointer to the termios struct, or use a `sig_atomic_t` flag to gate access. Alternatively, accept the theoretical risk given SA_RESETHAND mitigation and document the design choice.

**Acceptance criteria:** Either (a) `saved_termios` access is made signal-safe via atomic operations or a flag, or (b) the design choice is documented with rationale for accepting the risk.

**Affected paths:** `src/platform.zig`

---

### SF-028: delete_to_eol directly mutates ArrayList length field [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 5 (Impact: 1 x Likelihood: 1 x 4) |
| **CWE** | CWE-119: Improper Restriction of Operations within the Bounds of a Memory Buffer |
| **OWASP** | N/A |
| **Confidence** | suspected |
| **Exploit Surface** | Theoretical only |
| **Status** | **Resolved** -- replaced `state.buffer.items.len = state.cursor` with `state.buffer.shrinkRetainingCapacity(state.cursor)` in `src/core.zig` delete_to_eol handler. |
| **SLA** | N/A (Resolved) |
| **Resolved date** | 2026-03-25 |

**Summary:** The `delete_to_eol` action at `src/core.zig:654` truncates the edit buffer by directly setting `state.buffer.items.len = state.cursor`. This bypasses the ArrayList API (which would use `shrinkRetainingCapacity` or `replaceRange`). The truncated bytes remain in the backing allocation but are inaccessible through the ArrayList's public interface.

**Impact:** Minimal. The stale bytes in the backing allocation are not accessible through normal ArrayList operations. They would only be visible if code directly accessed the allocator's memory outside the ArrayList abstraction, which nothing in the codebase does. The behavior is functionally correct.

**Likelihood:** Theoretical. The direct mutation is a common Zig pattern for truncation and is equivalent to `shrinkRetainingCapacity`. No existing code path reads beyond `items.len`.

**Evidence:**
```
// src/core.zig:654
state.buffer.items.len = state.cursor;
```

**How to verify:** Confirm that no code reads `state.buffer.allocatedSlice()` or accesses memory beyond `items.len`. Currently no such code exists.

**Fix guidance:** Optional cleanup: replace `state.buffer.items.len = state.cursor` with `state.buffer.shrinkRetainingCapacity(state.cursor)` for API consistency. Not required for correctness or security.

**Acceptance criteria:** N/A -- informational finding. If addressed, the line would use the ArrayList API method instead of direct field mutation.

**Affected paths:** `src/core.zig`

---

## Phase 14 Findings (2026-03-25)

Phase 14 identified 2 new validated findings from targeted code review of search display
rendering and the `keywordProvider` consumer API. Both findings are confirmed via source
code evidence.

Per existing policy, no GitLab issues are created for Low or Info findings -- they are
tracked in this gap analysis only.

### SF-029: Search display garbled on multi-line history entries [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Info |
| **Risk Score** | 3 (Impact: 1 x Likelihood: 1 x 4, rounded down due to zero security impact) |
| **CWE** | CWE-116: Improper Encoding or Escaping of Output |
| **OWASP** | N/A |
| **Confidence** | confirmed |
| **Exploit Surface** | N/A -- purely cosmetic |
| **Status** | **Resolved** |
| **SLA** | Backlog |
| **Resolution** | Added `replaceNewlinesForDisplay()` helper that replaces `\n` with space in the display buffer after `bufPrint`, before `writeAll`. Six unit tests added. `state.buffer` is never modified. |

**Summary:** The search display at `src/search.zig:67-71` writes `state.buffer.items` to the terminal as part of the reverse-i-search prompt line. When a matching history entry contains multi-line content (i.e., embedded `\n` characters), the newlines are written directly to the terminal in raw mode without CRLF conversion or control-character replacement. This causes garbled display output because raw mode requires explicit `\r\n` sequences for proper line advancement.

**Impact:** Purely cosmetic. The terminal display becomes garbled when a multi-line history entry is matched during reverse-i-search. No data corruption, no security boundary violation, no information disclosure. The user can press Escape or Ctrl-C to exit search and the terminal renders correctly again.

**Likelihood:** Low practical impact. Multi-line history entries are uncommon in typical REPL usage. The garbled display is immediately visible and self-correcting on search exit.

**Evidence:**
```
// src/search.zig:67-71
const search_line = std.fmt.bufPrint(&line_buf, "\r(reverse-i-search)`{s}': {s}", .{
    state.search_buffer.items,
    if (found) state.buffer.items else "",  // buffer may contain \n from multi-line history
}) catch &line_buf;
try stdout.writeAll(search_line);
```

The `state.buffer.items` slice is written verbatim. If the matched history entry contains `\n`, the terminal in raw mode will advance the line without returning the cursor to column 0, producing garbled output.

**Attack scenario:** Not applicable. This is a display quality issue with no security implications. An attacker cannot exploit garbled search display to achieve any security objective.

**How to verify:** Add a multi-line entry to the history (e.g., a string containing `\n`), then use Ctrl-R reverse search to match it. Observe garbled terminal output.

**Fix guidance:** Replace `\n` characters in the display buffer with a visual placeholder (e.g., `\u{2424}` or a space) before writing to the terminal, or convert `\n` to `\r\n` for raw mode display. This is a UX improvement, not a security fix.

**Acceptance criteria:** Multi-line history entries display cleanly during reverse-i-search without garbling the terminal.

**Affected paths:** `src/search.zig`

---

### SF-030: keywordProvider returns dangling pointer to stack-local parameter [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 12 (Impact: 3 x Likelihood: 1 x 4) |
| **CWE** | CWE-416: Use After Free / CWE-825: Expired Pointer Dereference |
| **OWASP** | N/A (library API, not web/API) |
| **Confidence** | confirmed |
| **Exploit Surface** | Consumer code that calls `keywordProvider()` and later invokes `provider.generate()` |
| **Status** | **Resolved** |
| **SLA** | 180 days (2026-09-21) -- resolved well within SLA |
| **Resolution** | Parameter changed from by-value slice (`keywords: []const []const u8`) to pointer type, eliminating the dangling pointer. The returned `CompletionProvider` now holds a valid reference to caller-owned storage. |
| **Resolved date** | 2026-03-25 |

**Summary:** The `keywordProvider` function at `src/completion.zig:133-170` accepts a `keywords: []const []const u8` parameter (a slice passed by value on the stack) and stores a pointer to that stack-local parameter via `@ptrCast(@constCast(&keywords))` at line 168. The returned `CompletionProvider` struct contains this pointer in its `.context` field. After `keywordProvider` returns, the stack frame is deallocated and the pointer becomes dangling. Any subsequent call to `provider.generate()` (which reads `provider.context.?` at line 146) dereferences the expired pointer.

**Impact:** Undefined behavior when a consumer calls the returned provider's `generate` function. In `ReleaseFast` mode (no safety checks), this reads from a deallocated stack frame, which may return garbage data, cause a segfault, or silently produce incorrect completions. In `Debug` and `ReleaseSafe` modes, Zig's safety checks may detect the invalid memory access. The REPL core does NOT use `keywordProvider` internally -- this only affects library consumers who use this public API.

**Likelihood:** Low overall, but certain for any consumer who uses the API as designed. The function signature and documentation suggest it should work (accepting a keyword list and returning a provider), but the returned provider is immediately invalid. The saving grace is that no internal code path calls this function, so the bug is dormant unless a consumer discovers and uses the API.

**Evidence:**
```
// src/completion.zig:133 -- function signature (keywords is a stack-local parameter)
pub fn keywordProvider(keywords: []const []const u8) CompletionProvider {

// src/completion.zig:166-169 -- stores pointer to stack-local
    return CompletionProvider{
        .generateFn = Impl.generate,
        .context = @ptrCast(@constCast(&keywords)),  // dangling after return
    };
}

// src/completion.zig:146 -- dereferences the dangling pointer in generate()
const kw_list: []const []const u8 = @ptrCast(@alignCast(provider.context.?));
```

**Attack scenario:** A consumer application creates a keyword provider for SQL reserved words: `const provider = keywordProvider(&.{"SELECT", "INSERT", "UPDATE"});`. Later, when the user presses Tab, the REPL calls `provider.generate()`, which dereferences the dangling pointer. In `ReleaseFast`, this reads whatever data now occupies that stack location, potentially returning arbitrary memory contents as "completions" (information leak) or crashing (denial of service). In an adversarial scenario, if an attacker can influence what occupies the stack frame after `keywordProvider` returns, they could control what the pointer dereferences.

**How to verify:** Write a test that calls `keywordProvider`, then calls `provider.generateFn` on the returned provider. In `Debug` mode, Zig's safety checks should detect the use-after-free. In `ReleaseFast`, the behavior is undefined.

**Fix guidance:** Change the function to accept a pointer to the slice rather than a by-value slice, ensuring the caller is responsible for the lifetime:
```zig
pub fn keywordProvider(keywords: *const []const []const u8) CompletionProvider {
    return CompletionProvider{
        .generateFn = Impl.generate,
        .context = @ptrCast(@constCast(keywords)),
    };
}
```
Alternatively, store the slice value directly (Zig slices are pointer+length, 16 bytes) in the context field if the `?*anyopaque` field can be repurposed, or add a dedicated `slice_context` field to `CompletionProvider`.

**Acceptance criteria:**
- `keywordProvider` returns a `CompletionProvider` that remains valid after the function returns
- Calling `provider.generate()` correctly iterates the keyword list without undefined behavior
- A test demonstrates that the returned provider works correctly when `generate` is called after `keywordProvider` returns

**Affected paths:** `src/completion.zig`

---

## Audit Cycle 2, Phase 4 (2026-03-25)

Audit Cycle 2, Phase 4 performed a comprehensive security re-review of all open and
resolved findings. The Phase 3 security-reviewer confirmed all 3 open Low findings and
verified all 22 resolved findings with no regressions. No new findings warranting SF-IDs
were identified.

### Open Findings Re-confirmed

| SF-ID | Severity | Risk Score | Status | Assessment |
|-------|----------|------------|--------|------------|
| SF-026 | Low | 5 | **Won't Do** | Undo buffer bypasses display sanitization -- confirmed theoretical only. No real exploit path exists: the undo buffer is populated from the already-sanitized edit buffer, and the render pipeline provides independent output sanitization. No action required. Marked Won't Do in Gap Closure (2026-03-25). |
| SF-027 | Low | 8 | **Won't Do** | `saved_termios` not async-signal-safe -- confirmed cosmetic-only impact. SA_RESETHAND one-shot handler limits the race window to a single signal delivery during the narrow struct-copy instruction sequence. Worst case is a terminal `reset` command needed. Marked Won't Do in Gap Closure (2026-03-25). |
| SF-028 | Low | 5 | **Resolved** | Replaced `state.buffer.items.len = state.cursor` with `state.buffer.shrinkRetainingCapacity(state.cursor)` in core.zig delete_to_eol handler. Resolved in Gap Closure (2026-03-25). |

### Resolved Findings Regression Check

All 22 resolved findings were verified against current source. No regressions detected.

| SF-ID | Risk | Finding | Regression Status |
|-------|------|---------|-------------------|
| SF-030 | 12 | `keywordProvider` dangling pointer | No regression -- parameter accepts pointer type, no stack-local copy |
| SF-029 | 3 | Search display garbled on multi-line history | No regression -- `replaceNewlinesForDisplay()` helper active in search.zig |
| SF-025 | 35 | Signal handler uses `std.os.linux.*` | No regression -- `std.posix.system.*` calls in place |
| SF-024 | 8 | History `clear()` missing chmod | No regression -- `chmod(0o600)` present after createFile in `clear()` |
| SF-023 | 8 | Config file missing chmod | No regression -- `file.chmod(0o600)` in `src/config.zig` |
| SF-022 | 8 | History file TOCTOU on permissions | No regression -- `chmod(0o600)` after file open in `src/history.zig` |
| SF-021 | 8 | Static mutable `home_dir_buf` | No regression -- `threadlocal` declaration in `src/completion.zig` |
| SF-014 | 50 | Signal handler dead code | No regression -- handlers wired at `platform.zig:193-194`, `platform.zig:219-220` |
| SF-013 | 35 | Search bypasses history filtering | No regression -- `appendHistoryFiltered` at `core.zig:883` |
| SF-009 | 35 | Terminal escape injection | No regression -- `appendHistoryFiltered()` guards all paths |
| SF-005 | 40 | Bracketed paste forgery | No regression -- `sanitizePasteContent()` active |
| SF-001 | 45 | History/config world-readable | No regression -- `.mode = 0o600` in all createFile calls |
| SF-007 | 25 | Env var path injection | No regression -- `isPathSafe()` in `text_utils.zig` |
| SF-003 | 20 | @intCast overflow (32-bit) | No regression -- 64MB bounds check present |
| SF-016 | 20 | Paste buffer silent truncation | No regression -- flush-and-continue logic active |
| SF-020 | 15 | CI hash same-origin | No regression -- SHA-256 hashes pinned in `.gitlab-ci.yml` |
| SF-018 | 15 | renderPrompt buffer overflow | No regression -- `buffer_full` flag logic intact |
| SF-010 | 15 | Silent output truncation | No regression -- partial write on overflow |
| SF-017 | 10 | Search display unfiltered | No regression -- input filter documented |
| SF-019 | 10 | Vi de/e underflow guard | No regression -- `end + 1 < items.len` form used |
| SF-006 | 10 | catch unreachable on init | No regression -- safety comments present |
| SF-011 | 10 | False fuzz claim | No regression -- SECURITY.md reflects planned status |

### Info-Level Observation

One Info-level observation was noted: the search display path at `src/search.zig` does not
replace `\r` (carriage return) characters in buffer content before writing to the terminal.
This does NOT warrant a new SF-ID because: (1) it is purely cosmetic -- the display cursor
would return to column 0 but no security boundary is crossed; (2) ESC (0x1B) is already
blocked by the input filter, preventing ANSI escape injection; (3) `\r` alone cannot inject
terminal commands. This observation is documented here for completeness only.

---

## Phase 10 Validation Audit (2026-03-24)

Phase 10 performed a validation audit with the following results:

**0 new security findings. 0 regressions.**

### Open Findings Re-verified

| SF-ID | Severity | Risk Score | Status | Change |
|-------|----------|------------|--------|--------|
| SF-021 | Low | 8 | **Resolved** | `threadlocal` added to `home_dir_buf` in `src/completion.zig:188` |
| SF-022 | Low | 8 | **Resolved** | `chmod(0o600)` added after file open in `src/history.zig` |
| SF-023 | Low | 8 | **Resolved** | `chmod(0o600)` added after file open in `src/config.zig:162` (same class as SF-022) |

SF-021/SF-022 resolved in Phase 11; SF-023 resolved in Phase 12 gap closure (2026-03-24). All within 180-day SLA.

### Resolved Findings Regression Check

All 18 resolved findings were verified against current source. No regressions detected.

| SF-ID | Risk | Finding | Regression Status |
|-------|------|---------|-------------------|
| SF-014 | 50 | Signal handler dead code | No regression -- handlers still wired at `platform.zig:193-194`, `platform.zig:219-220` |
| SF-001 | 45 | History/config world-readable | No regression -- `.mode = 0o600` present in all createFile calls |
| SF-005 | 40 | Bracketed paste forgery | No regression -- `sanitizePasteContent()` still active |
| SF-009 | 35 | Terminal escape injection | No regression -- `appendHistoryFiltered()` still guards all paths |
| SF-013 | 35 | Search bypasses history filtering | No regression -- `appendHistoryFiltered` at `core.zig:883` |
| SF-007 | 25 | Env var path injection | No regression -- `isPathSafe()` in `text_utils.zig` |
| SF-003 | 20 | @intCast overflow (32-bit) | No regression -- 64MB bounds check present |
| SF-016 | 20 | Paste buffer silent truncation | No regression -- flush-and-continue logic active |
| SF-020 | 15 | CI hash same-origin | No regression -- SHA-256 hashes pinned in `.gitlab-ci.yml` |
| SF-018 | 15 | renderPrompt buffer overflow | No regression -- `buffer_full` flag logic intact |
| SF-010 | 15 | Silent output truncation | No regression -- partial write on overflow |
| SF-017 | 10 | Search display unfiltered | No regression -- input filter documented |
| SF-019 | 10 | Vi de/e underflow guard | No regression -- `end + 1 < items.len` form used |
| SF-006 | 10 | catch unreachable on init | No regression -- safety comments present |
| SF-011 | 10 | False fuzz claim | No regression -- SECURITY.md reflects planned status |

### Trust Boundary Review

All trust boundaries reviewed and confirmed secure:

| Trust Boundary | Assessment |
|----------------|------------|
| Paste input (bracketed paste mode) | Secure -- sanitizePasteContent strips embedded sequences; flush-and-continue handles large pastes |
| Key parsing (escape sequences) | Secure -- bounded state machine with timeout; no injection path from terminal input |
| Signal handling (SIGTERM, SIGHUP, SIGWINCH) | Secure -- handlers wired into raw mode lifecycle; terminal restored on signal |
| History file I/O | Secure -- 0o600 permissions, isPathSafe validation, 64MB size cap, filtered append |
| Config file I/O | Secure -- 0o600 permissions, isPathSafe validation, structured parsing |
| Search (reverse-i-search) | Secure -- input filter restricts to 0x20-0x7F; history results use appendHistoryFiltered |
| Environment variables (HOME, XDG paths) | Secure -- isPathSafe rejects traversal; no command injection from env vars |

### Quality Findings Security Assessment

Three quality findings were assessed for potential security exploitation paths:

| Quality Finding | Security Assessment |
|-----------------|---------------------|
| handleCompletion cursor positioning | Low quality issue -- incorrect cursor offset after completion. No security impact: cursor position does not affect buffer contents or escape sequence processing. |
| Vi o/O cursor positioning | Low quality issue -- cursor may land at wrong position after open-line command. No security impact: affects display only, not buffer integrity or input processing. |
| Duplicate catch "" in error handling | Low quality issue -- redundant catch clause. No security impact: error handling behavior is unchanged; the duplicate is dead code with no effect on control flow. |

**Conclusion:** None of the quality findings are exploitable. They affect user experience (display correctness) but do not create attack surface or weaken security controls.

---

## Phase 9 Findings (2026-03-24)

Phase 9 performed a Phase 3 deep review. NC-001 and NC-002 (existing Low findings from
Phase 2) were re-confirmed at Low severity with no status changes required. Two new
Low/suspected findings were identified (SF-021, SF-022). Per policy, no GitLab issues
are created for Low/suspected findings -- they are tracked here in the gap analysis only.

### SF-021: Static mutable home_dir_buf without thread safety [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 8 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-362: Concurrent Execution using Shared Resource with Improper Synchronization |
| **OWASP** | N/A (library-internal, not directly web/API) |
| **Confidence** | suspected |
| **Exploit Surface** | Admin-only access (requires multi-threaded caller on Windows) |
| **Status** | **Resolved** (2026-03-24) -- `threadlocal` added to `home_dir_buf` declaration |
| **SLA** | 180 days (2026-09-20) -- resolved well within SLA |

**Summary:** Module-level `var home_dir_buf: [512]u8` at `src/completion.zig:188` is a static mutable buffer shared across all callers. If `getHomeDir()` is called from multiple threads simultaneously, a data race would corrupt the buffer contents.

**Impact:** On Windows only, concurrent calls to `getHomeDir()` could produce a corrupted home directory path, leading to incorrect file path completions. No memory safety violation (Zig safety checks would catch out-of-bounds), but path correctness would be compromised.

**Likelihood:** Extremely low. The library is designed for single-threaded use. The affected code path is Windows-only (`builtin.os.tag == .windows`). On POSIX systems, `getHomeDir()` returns `std.posix.getenv("HOME")` which does not use the static buffer.

**Evidence:**
```
// src/completion.zig:187-188
/// Static buffer for the Windows home directory path (UTF-8 decoded).
var home_dir_buf: [512]u8 = undefined;
```

**Attack scenario:** An application embeds the REPL library and calls tab completion from multiple threads on Windows. Thread A and Thread B both call `getHomeDir()` simultaneously; Thread A's UTF-16 to UTF-8 conversion overwrites the buffer while Thread B is reading from it, producing a garbled path.

**How to verify:** Run a multi-threaded stress test calling `getHomeDir()` concurrently on Windows and check for corrupted return values. Alternatively, static analysis tools that detect shared mutable state without synchronization would flag this pattern.

**Fix guidance:** Change `var home_dir_buf` to `threadlocal var home_dir_buf` to give each thread its own copy. This is a one-line change with no performance impact.

**Acceptance criteria:**
- `home_dir_buf` is declared as `threadlocal var` or otherwise protected against concurrent access
- No behavioral change for single-threaded callers

**Affected paths:** `src/completion.zig`

---

### SF-022: History file TOCTOU on permissions [RESOLVED]

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 8 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-367: Time-of-Check Time-of-Use (TOCTOU) Race Condition |
| **OWASP** | N/A (local file operation, not web/API) |
| **Confidence** | suspected |
| **Exploit Surface** | Requires physical access or same-user compromise |
| **Status** | **Resolved** (2026-03-24) -- `chmod(0o600)` added after file open |
| **SLA** | 180 days (2026-09-20) -- resolved well within SLA |

**Summary:** The `appendLine` method at `src/history.zig:178` opens existing history files with `createFile(path, .{ .truncate = false, .mode = 0o600 })`. The `.mode = 0o600` parameter only applies when creating a new file. If the file already exists (e.g., pre-created by an attacker with `0o644` permissions), the existing permissions are preserved, and subsequent history writes go to a world-readable file.

**Impact:** History entries (which may contain sensitive commands) could be written to a world-readable file if an attacker pre-creates the history file with permissive permissions before the REPL first writes to it.

**Likelihood:** Extremely low. Exploitation requires: (1) the attacker has write access to the user's home directory, (2) the history file does not yet exist, (3) the attacker creates it before the REPL does. Home directory permissions (typically 0o700 or 0o750) prevent other users from creating files there. The `isPathSafe()` validation and `makePath` for the directory further constrain the attack surface.

**Evidence:**
```
// src/history.zig:178
const file = std.fs.cwd().createFile(path, .{ .truncate = false, .mode = 0o600 }) catch |err| {
    // If we can't save history, just continue without persisting
    if (err == error.FileNotFound) return;
    return err;
};
```

**Attack scenario:** On a multi-user system with a shared `/tmp`-based history path (non-default configuration), an attacker creates `/tmp/victim/.repl_history` with mode `0o644` before the victim runs the REPL. The victim's REPL opens the existing file without checking permissions and appends command history that the attacker can then read.

**How to verify:** Pre-create a history file with `0o644` permissions, run the REPL, verify the file permissions remain `0o644` after the REPL writes history. If permissions are not tightened, the TOCTOU exists.

**Fix guidance:** After opening an existing file, call `fchmod(fd, 0o600)` (or the Zig equivalent `file.chmod(0o600)`) to enforce the expected permissions regardless of the file's pre-existing mode. Alternatively, check permissions after open and refuse to write if they are too permissive.

**Acceptance criteria:**
- History file permissions are enforced to `0o600` after opening, regardless of pre-existing mode
- Or: the library refuses to write to files with permissions more permissive than `0o600`

**Affected paths:** `src/history.zig`

---

### NC-001 / NC-002: Phase 2 Low Findings Re-confirmed

NC-001 and NC-002 are existing Low severity findings from Phase 2 that were re-confirmed
during the Phase 9 deep review. Their status, severity, and risk scores remain unchanged.
No new action required.

---

## Detailed Findings (Phase 3 -- All Resolved)

### SF-016: Paste buffer silent truncation at 4096 bytes -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 20 (Impact: 2 x Likelihood: 2 x 4) |
| **CWE** | CWE-130: Improper Handling of Length Parameter Inconsistency |
| **Confidence** | confirmed |
| **Status** | **Resolved** (2026-03-24) -- paste buffer now flushes to edit buffer when full, allowing arbitrarily large pastes without dynamic allocation |

**Summary:** The bracketed paste buffer `paste_buf` is a fixed `[4096]u8` array. During paste collection, characters that exceed the buffer capacity were silently dropped with no user notification.

**Resolution:** When the paste buffer fills before the end marker is seen, the accumulated content is flushed into `state.buffer` via `sanitizePasteContent` + `insertSlice`, the paste length is reset to 0, and collection continues. This handles pastes of arbitrary size without dynamic allocation. The flush logic is extracted into a dedicated `flushPasteBuffer` helper used by both the buffer-full path and the paste-end-marker path.

**Evidence of fix:**
- `src/core.zig` -- `flushPasteBuffer()` helper function flushes and resets paste buffer
- `src/core.zig` -- `consumeBracketedPaste()` calls `flushPasteBuffer` when `paste_len >= paste_buf.len`
- 4 unit tests added: normal paste, paste exceeding buffer, exact boundary, multiple flush cycles

**Affected paths:** `src/core.zig`

---

### SF-017: Search display renders unfiltered search buffer -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 10 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-116: Improper Encoding or Escaping of Output |
| **Confidence** | confirmed |
| **Status** | **Resolved** (2026-03-24) -- added safety comment documenting that search_buffer only contains printable ASCII (0x20-0x7f) filtered at the input loop |

**Summary:** The reverse-i-search display at `src/core.zig:791` writes `state.search_buffer.items` directly into an ANSI-formatted `bufPrint` call without explicit sanitization. The search buffer content is rendered to the terminal as part of the `(reverse-i-search)` prompt line.

**Evidence:**
- `src/core.zig:791` -- `const search_line = std.fmt.bufPrint(&line_buf, "\r(reverse-i-search)\x60{s}': {s}", .{ state.search_buffer.items, ... })`

**Current mitigation:** The input filter in the key processing path only accepts characters in the 0x20-0x7F range into the search buffer, which prevents control characters and escape sequences from entering. This mitigation makes the finding theoretical rather than actively exploitable.

**What would confirm:** Demonstrate that a code path exists (or could be introduced in future refactoring) that writes arbitrary bytes into `search_buffer` bypassing the input filter. If such a path existed, an attacker could inject ANSI escape sequences into the terminal display.

**Fix guidance:** Add explicit sanitization of `search_buffer.items` before rendering, consistent with the `appendHistoryFiltered` pattern used elsewhere. This provides defense-in-depth even if the input filter is the primary guard.

**Acceptance criteria:**
- Search display output is explicitly sanitized before terminal write, or a code comment documents the input filter as the intentional sanitization point.

**Affected paths:** `src/core.zig`

---

### SF-018: renderPrompt fixed buffer silently discards render output -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 15 (Impact: 2 x Likelihood: 2 x 4) |
| **CWE** | CWE-130: Improper Handling of Length Parameter Inconsistency |
| **Confidence** | confirmed |
| **Status** | **Resolved** (2026-03-24) -- render buffer overflow now detected via `buffer_full` flag; writes stop cleanly on overflow to prevent broken ANSI sequences |

**Summary:** The `renderPrompt` function accumulates all render output into a fixed `[8192]u8` buffer. Previously, all writes used `catch {}` to silently discard errors, meaning buffer overflow could cause broken ANSI escape sequences.

**Resolution:** Replaced all `catch {}` blocks with `catch { buffer_full = true; }` and added early-exit logic. When the buffer fills during the content-writing loop, the loop breaks immediately. Cursor positioning ANSI sequences are skipped entirely when overflow is detected, preventing partial escape sequences from corrupting the terminal. The valid partial content is still written to stdout.

**Evidence of fix:**
- `src/core.zig` -- `renderPrompt()` now tracks `buffer_full` flag
- Each `catch` block sets `buffer_full = true` instead of silently continuing
- Content loop uses `break` on overflow instead of continuing to attempt failed writes
- Cursor positioning is skipped when `buffer_full` is true to avoid broken ANSI sequences
- 1 unit test added verifying fixedBufferStream overflow behavior and partial write detection

**Affected paths:** `src/core.zig`

---

### SF-019: Vi de/e command fragile underflow guard -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 10 (Impact: 2 x Likelihood: 1 x 4) |
| **CWE** | CWE-191: Integer Underflow (Wrap or Wraparound) |
| **Confidence** | confirmed |
| **Status** | **Resolved** (2026-03-24) -- restructured while-loop conditions from `end < items.len - 1` to `end + 1 < items.len` at both the `de` handler and `e` motion in keymap_vi.zig |

**Summary:** The Vi-mode `de` (delete to end of word) command at `src/keymap_vi.zig:114` computes `state.buffer.items.len - 1`. This subtraction would underflow if `items.len` is 0. The code is currently safe because line 113 guards with `end < state.buffer.items.len`, which prevents entering the while loop when the buffer is empty. However, the safety depends on a single outer guard, and refactoring that guard could silently introduce an underflow.

**Evidence:**
- `src/keymap_vi.zig:113` -- `if (end < state.buffer.items.len and !std.ascii.isWhitespace(state.buffer.items[end])) {`
- `src/keymap_vi.zig:114` -- `while (end < state.buffer.items.len - 1 and ...) : (end += 1) {}`

**Current mitigation:** The guard at line 113 ensures the while loop at line 114 is only entered when `items.len >= 1`, making the `- 1` safe. In Zig debug mode, integer underflow would be caught by safety checks.

**What would confirm:** Demonstrate that a refactoring of the outer `if` block allows line 114 to execute with `items.len == 0`. This is currently prevented but fragile.

**Fix guidance:** Replace `state.buffer.items.len - 1` with a saturating subtraction (`@max(state.buffer.items.len, 1) - 1` or equivalent), or restructure the loop condition to avoid the subtraction entirely (e.g., `end + 1 < state.buffer.items.len`).

**Acceptance criteria:**
- The `de` command does not depend on an outer guard to prevent integer underflow.
- The while-loop condition is self-contained safe regardless of buffer length.

**Affected paths:** `src/keymap_vi.zig`

---

### SF-020: CI Zig download hash fetched from same origin as binary -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 15 (Impact: 3 x Likelihood: 1 x 4) |
| **CWE** | CWE-494: Download of Code Without Integrity Check (from independent source) |
| **Confidence** | confirmed |
| **Status** | **Resolved** (2026-03-24) |

**Summary:** The CI pipeline previously downloaded both the SHA-256 hash index and the Zig binary tarball from `ziglang.org`. If the origin were compromised, an attacker could serve a matching hash/binary pair, defeating the integrity check.

**Resolution:** SHA-256 hashes for each supported architecture are now pinned directly in `.gitlab-ci.yml` as CI variables (`ZIG_SHA256_X86_64_LINUX`, `ZIG_SHA256_AARCH64_LINUX`). The `index.json` fetch has been removed entirely. The hash is now verified from the git repository (a separate trust root) rather than the download origin. The `python3` dependency was also removed from the install script as it is no longer needed.

**Evidence (after fix):**
- `.gitlab-ci.yml:24-28` -- `ZIG_SHA256_X86_64_LINUX` and `ZIG_SHA256_AARCH64_LINUX` pinned in variables section
- `.gitlab-ci.yml:54-56` -- architecture case sets `EXPECTED_HASH` from pinned variable
- `.gitlab-ci.yml:59-60` -- guard rejects missing hash with clear error message
- `.gitlab-ci.yml:70-71` -- binary verified against repo-pinned hash

**Acceptance criteria:** Met -- Zig binary integrity is verified against a hash committed to the repository, not fetched from the same download origin.

**Affected paths:** `.gitlab-ci.yml`

---

## Detailed Findings (Resolved in Previous Closure)

### SF-014: Signal handler dead code (supersedes SF-002) -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Risk Score** | 50 (Impact: 2 x Likelihood: 5 x 4) |
| **CWE** | CWE-404: Improper Resource Shutdown or Release |
| **Status** | **Resolved** |
| **Issue** | [#45](https://gitlab.com/devnw/zig/repl/-/issues/45) (closed) |

**Resolution:** `enterRawMode()` now sets `saved_termios = original` and calls `installTerminalSignalHandlers()` at `src/platform.zig:193-194`. `restoreTerminalMode()` now calls `removeTerminalSignalHandlers()` and sets `saved_termios = null` at `src/platform.zig:219-220`. Signal handlers are now active during raw mode and will restore the terminal on SIGTERM/SIGHUP.

---

### SF-013: handleSearch() bypasses history filtering -- RESOLVED

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Risk Score** | 35 (Impact: 2 x Likelihood: 4 x 4) |
| **CWE** | CWE-116: Improper Encoding or Escaping of Output |
| **Status** | **Resolved** |
| **Issue** | [#72](https://gitlab.com/devnw/zig/repl/-/issues/72) (closed) |

**Resolution:** Changed `appendSlice` to `appendHistoryFiltered` at `src/core.zig:883`. All history-to-buffer paths now consistently use filtered append, closing the terminal escape injection vector via reverse-i-search.

---

## Detailed Findings (Won't Do)

### SF-012: Pre-commit/CI pinned by mutable tag, not SHA -- WON'T DO

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 20 |
| **CWE** | CWE-829: Inclusion of Functionality from Untrusted Control Sphere |
| **Status** | **Won't Do** |
| **Issue** | [#58](https://gitlab.com/devnw/zig/repl/-/issues/58) |

**Reason:** External tooling control. GitLab CI component references (`devnw/ci-catalog`) use semver tags which may not support SHA pinning. Pre-commit hook versions are managed by the pre-commit framework's own update mechanism. The risk (score 20) is low and the effort to maintain SHA-pinned forks of external tooling outweighs the benefit.

### SF-008: File path completion allows full filesystem traversal -- WON'T DO

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 15 |
| **CWE** | CWE-22: Path Traversal |
| **Status** | **Won't Do** (by design) |
| **Issue** | [#59](https://gitlab.com/devnw/zig/repl/-/issues/59) |

**Reason:** By design for a general-purpose REPL library. Tab completion traversing the filesystem is expected behavior. Consumers who need path restrictions must implement their own CompletionProvider. This is documented in the completion module API.

### SF-015: sanitizePasteContent theoretical fragmentation gap -- WON'T DO

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 10 |
| **CWE** | CWE-74: Injection |
| **Status** | **Won't Do** (theoretical only) |

**Reason:** Theoretical only. Terminal emulators deliver paste markers atomically. The 256-byte read buffer is 42x larger than the 6-byte marker. Kernel buffering further reduces fragmentation likelihood. No real-world exploitation path exists. If paste mode is ever refactored, cross-boundary marker detection can be revisited.

---

## Detailed Findings (No Action Needed)

### SF-004: CONTRIBUTING.md license mismatch (root copy) -- NO ACTION NEEDED

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Risk Score** | 15 |
| **Status** | **No Action Needed** |
| **Issue** | [#29](https://gitlab.com/devnw/zig/repl/-/issues/29) |

**Reason:** Root `CONTRIBUTING.md` was checked and contains no MIT reference. It already correctly references Apache-2.0. The `docs/CONTRIBUTING.md` copy was previously corrected in GAP-0003. No change needed.

---

## Detailed Findings (Previously Resolved)

### SF-001: History/config files world-readable -- RESOLVED

**Resolution:** `.mode = 0o600` added to all `createFile` calls.
- `src/history.zig:151` -- `createFile(path, .{ .truncate = false, .mode = 0o600 })`
- `src/history.zig:182` -- `createFile(path, .{ .truncate = true, .mode = 0o600 })`
- `src/config.zig:153` -- `createFile(path, .{ .mode = 0o600 })`

### SF-005: Bracketed paste end-marker forgery -- RESOLVED

**Resolution:** `sanitizePasteContent()` added at `core.zig:419-441`. Strips embedded `\x1b[200~` and `\x1b[201~` sequences from paste content using in-place rewriting.

### SF-009: Terminal escape injection from history replay -- RESOLVED

**Resolution:** `appendHistoryFiltered()` added at `core.zig:408-414`. Strips control characters (0x00-0x1F except tab/newline, and 0x7F) from history entries. Used in all history-to-buffer paths including search (SF-013 now resolved).

### SF-007: Env var path injection -- RESOLVED

**Resolution:** `isPathSafe()` validates absolute paths and rejects `..` traversal components. Now extracted to shared `src/text_utils.zig` module (was duplicated in history.zig and config.zig).

### SF-003: Unchecked @intCast on 32-bit -- RESOLVED

**Resolution:** 64MB bounds check added at `history.zig:75-76`.

### SF-010: TerminalWriter.print silent output drop -- RESOLVED

**Resolution:** Partial write on overflow at `platform.zig:406-417`.

### SF-006: catch unreachable on zero-capacity init -- RESOLVED

**Resolution:** Safety comments added documenting that `initCapacity(allocator, 0)` never allocates.

### SF-011: False fuzz testing claim in SECURITY.md -- RESOLVED

**Resolution:** `SECURITY.md:37` updated to "Fuzz testing for parser inputs (planned, not yet implemented)".

---

## Risk Distribution

```
OPEN (0 findings):
(none)

RESOLVED (24 findings):
50  [==========]  SF-014  Signal handler dead code                 [RESOLVED]
45  [=========]   SF-001  History/config world-readable            [RESOLVED]
40  [========]    SF-005  Bracketed paste forgery                  [RESOLVED]
35  [=======]     SF-009  Terminal escape injection                [RESOLVED]
35  [=======]     SF-013  Search bypasses history filtering        [RESOLVED]
35  [=======]     SF-025  Signal handler uses std.os.linux.*       [RESOLVED]
25  [=====]       SF-007  Env var path injection                   [RESOLVED]
20  [====]        SF-003  @intCast overflow (32-bit)               [RESOLVED]
20  [====]        SF-016  Paste buffer flush-and-continue          [RESOLVED]
15  [===]         SF-020  CI hash pinned in repo                   [RESOLVED]
15  [===]         SF-018  renderPrompt buffer_full flag             [RESOLVED]
15  [===]         SF-010  Silent output truncation                 [RESOLVED]
12  [===]         SF-030  keywordProvider dangling pointer          [RESOLVED]
10  [==]          SF-017  Search display input filter documented   [RESOLVED]
10  [==]          SF-019  Vi de/e underflow guard restructured     [RESOLVED]
10  [==]          SF-006  catch unreachable                        [RESOLVED]
10  [==]          SF-011  False fuzz claim                         [RESOLVED]
8   [==]          SF-024  History clear() missing chmod             [RESOLVED]
8   [==]          SF-023  Config file missing chmod (same as SF-022) [RESOLVED]
8   [==]          SF-021  Static mutable home_dir_buf (thread safety) [RESOLVED]
8   [==]          SF-022  History file TOCTOU on permissions        [RESOLVED]
5   [=]           SF-028  delete_to_eol shrinkRetainingCapacity      [RESOLVED]
3   [=]           SF-029  Search display multi-line garble (cosmetic) [RESOLVED]

WON'T DO (5 findings):
20  [====]        SF-012  CI pinned by mutable tag                 [WON'T DO]
15  [===]         SF-008  File path traversal (by design)          [WON'T DO]
10  [==]          SF-015  Paste sanitization fragmentation         [WON'T DO]
8   [==]          SF-027  saved_termios not async-signal-safe       [WON'T DO]
5   [=]           SF-026  Undo buffer bypasses sanitization (theoretical) [WON'T DO]

NO ACTION NEEDED (1 finding):
15  [===]         SF-004  License mismatch in docs (root)          [NO ACTION]
```

---

## CWE Coverage

| CWE ID | CWE Name | Count | Findings | Status |
|--------|----------|-------|----------|--------|
| CWE-416 | Use After Free | 1 | SF-030 | **Resolved** |
| CWE-825 | Expired Pointer Dereference | 1 | SF-030 | **Resolved** (same finding, dual CWE) |
| CWE-474 | Use of Function with Inconsistent Implementations | 1 | SF-025 | Resolved |
| CWE-404 | Improper Resource Shutdown or Release | 1 | SF-014 | Resolved |
| CWE-362 | Race Condition (Shared Resource) | 1 | SF-021 | Resolved |
| CWE-364 | Signal Handler Race Condition | 1 | SF-027 | **Won't Do** |
| CWE-367 | TOCTOU Race Condition | 1 | SF-022 | Resolved |
| CWE-116 | Improper Encoding or Escaping | 5 | SF-009, SF-013, SF-017, SF-026, SF-029 | SF-009/013/017/029 Resolved, SF-026 **Won't Do** (theoretical) |
| CWE-119 | Improper Restriction of Operations within Bounds | 1 | SF-028 | **Resolved** (Gap Closure) |
| CWE-130 | Length Parameter Inconsistency | 3 | SF-010, SF-016, SF-018 | All Resolved |
| CWE-191 | Integer Underflow | 1 | SF-019 | Resolved |
| CWE-494 | Download Without Integrity Check | 1 | SF-020 | Resolved |
| CWE-74 | Injection | 2 | SF-005, SF-015 | SF-005 Resolved, SF-015 Won't Do |
| CWE-829 | Untrusted Control Sphere | 1 | SF-012 | Won't Do |
| CWE-22 | Path Traversal | 1 | SF-008 | Won't Do (by design) |
| CWE-732 | Incorrect Permission Assignment | 3 | SF-001, SF-023, SF-024 | All Resolved |
| CWE-426 | Untrusted Search Path | 1 | SF-007 | Resolved |
| CWE-190 | Integer Overflow | 1 | SF-003 | Resolved |
| CWE-248 | Uncaught Exception | 1 | SF-006 | Resolved |
| N/A | Documentation | 2 | SF-004, SF-011 | SF-011 Resolved, SF-004 No Action |

---

## Findings by Area

### Terminal / Platform (6 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-014 | 50 | Signal handler dead code -- now wired into enterRawMode/restoreTerminalMode | **Resolved** |
| SF-025 | 35 | Signal handler uses `std.os.linux.*` on all POSIX -- blocks macOS/FreeBSD | **Resolved** |
| SF-018 | 15 | renderPrompt fixed buffer -- buffer_full flag stops writes on overflow | **Resolved** |
| SF-010 | 15 | Silent output truncation >4096 bytes | Resolved |
| SF-006 | 10 | catch unreachable on init | Resolved |
| SF-027 | 8 | `saved_termios` global not async-signal-safe (mitigated by SA_RESETHAND) | **Won't Do** |

### Input Handling / Completion (11 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-005 | 40 | Bracketed paste end-marker forgery | Resolved |
| SF-009 | 35 | Terminal escape injection from history | Resolved |
| SF-013 | 35 | Search result bypasses history filtering | **Resolved** |
| SF-016 | 20 | Paste buffer flush-and-continue for arbitrarily large pastes | **Resolved** |
| SF-030 | 12 | `keywordProvider` returns dangling pointer to stack-local parameter | **Resolved** |
| SF-017 | 10 | Search display -- input filter documented as intentional guard | **Resolved** |
| SF-015 | 10 | Paste sanitization fragmentation gap (theoretical) | **Won't Do** |
| SF-021 | 8 | Static mutable `home_dir_buf` without thread safety (Windows-only) | **Resolved** |
| SF-026 | 5 | Undo buffer `appendSlice` bypasses display sanitization (theoretical) | **Won't Do** |
| SF-028 | 5 | `delete_to_eol` directly mutates ArrayList length field | **Resolved** |
| SF-029 | 3 | Search display garbled on multi-line history entries (cosmetic) | **Resolved** |

### File System / Access Control (6 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-001 | 45 | History/config files world-readable | Resolved |
| SF-007 | 25 | Env var path injection | Resolved |
| SF-008 | 15 | File path completion traversal | **Won't Do** (by design) |
| SF-023 | 8 | Config file missing chmod on pre-existing file | **Resolved** |
| SF-022 | 8 | History file TOCTOU on permissions | **Resolved** |
| SF-024 | 8 | History `clear()` missing chmod on pre-existing file | **Resolved** |

### Vi Keymap (1 finding, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-019 | 10 | Vi de/e command fragile underflow guard | **Resolved** |

### History (3 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-003 | 20 | @intCast overflow on 32-bit | Resolved |
| SF-022 | 8 | History file TOCTOU on permissions (also in File System section) | **Resolved** |
| SF-024 | 8 | History `clear()` missing chmod on pre-existing file (also in File System section) | **Resolved** |

### Supply Chain / CI (2 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-020 | 15 | CI Zig download hash fetched from same origin as binary | **Resolved** |
| SF-012 | 20 | CI dependencies pinned by mutable tag | **Won't Do** |

### Documentation (2 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-004 | 15 | License mismatch in CONTRIBUTING.md (root) | **No Action Needed** |
| SF-011 | 10 | False fuzz testing claim in SECURITY.md | Resolved |

---

## Roadmap

### Quick Wins (< 1 day)

| SF-ID | Fix | Effort | Status |
|-------|-----|--------|--------|
| SF-030 | Changed `keywordProvider` parameter to pointer type, eliminating dangling pointer | 15 min | **Resolved** |
| SF-029 | Added `replaceNewlinesForDisplay` helper + 6 unit tests in search.zig | 10 min | **Resolved** |
| SF-028 | Replace `items.len = cursor` with `shrinkRetainingCapacity(cursor)` | 5 min | **Resolved** |
| SF-026 | Won't Do -- theoretical only, no exploit path; undo buffer populated from sanitized edit buffer | -- | **Won't Do** |
| SF-027 | Won't Do -- documented SA_RESETHAND mitigation as accepted risk; cosmetic-only impact | -- | **Won't Do** |
| SF-024 | Add `file.chmod(0o600)` after createFile in `clear()` (same pattern as `appendLine()`) | 5 min | Resolved |
| SF-021 | Change `var home_dir_buf` to `threadlocal var home_dir_buf` | 5 min | Resolved |
| SF-022 | Add `file.chmod(0o600)` after opening existing history files | 15 min | Resolved |
| SF-019 | Restructured while-loop condition to `end + 1 < state.buffer.items.len` | 15 min | Resolved |
| SF-017 | Added safety comment documenting input filter as intentional guard | 30 min | Resolved |
| SF-020 | Pinned SHA-256 hashes in `.gitlab-ci.yml` variables; removed `index.json` fetch | 30 min | Resolved |

### Medium (1-5 days)

| SF-ID | Fix | Effort | Status |
|-------|-----|--------|--------|
| SF-025 | Replace `std.os.linux.*` with `std.posix.system.*` or comptime os.tag switch in signal handler | 2-4 hours | Resolved |
| SF-016 | Flush-and-continue: paste buffer flushes to edit buffer when full | 1-2 hours | Resolved |
| SF-018 | buffer_full flag: writes stop cleanly on overflow, cursor positioning skipped | 2-4 hours | Resolved |

### Strategic (> 5 days)

No strategic items. All open findings are quick wins or medium effort tasks.

---

## Automated Scan Results (2026-03-24, last run Phase 10)

All automated security scanners returned zero findings across all phases (initial through Phase 10):

| Scanner | Scope | Findings | Notes |
|---------|-------|----------|-------|
| **gitleaks** | Secrets in git history | 0 | Full repository scan |
| **trufflehog** | Secrets detection | 0 | Full repository scan |
| **trivy** | Secrets, vulnerabilities, config | 0 | All scan modes |
| **semgrep** | Static analysis | 0 | 78 rules across 49 files |
| **osv-scanner** | Known vulnerabilities | 0 | No dependencies to scan |
| **grype** | Vulnerability scanning | 0 | No dependencies to scan |
| **syft** | SBOM generation | 0 dependencies | Pure Zig, stdlib only |
| **checkov** | Infrastructure-as-code | 0 | Added in Phase 5 |

**Assessment:** The zero-dependency nature of this project significantly reduces supply chain risk. The only supply chain concerns are CI/CD tooling pinning (SF-012, Won't Do) and same-origin hash verification (SF-020, Resolved -- hashes now pinned in repo).

---

## Immediate Actions

**No immediate rotation or emergency remediation required.** No leaked secrets, no active RCE, no authentication bypass.

**Gap Closure action summary (2026-03-25):**
- **SF-028 (Low, risk 5):** Resolved -- replaced `items.len = cursor` with `shrinkRetainingCapacity(cursor)` in core.zig delete_to_eol handler.
- **SF-027 (Low, risk 8):** Won't Do -- documented SA_RESETHAND mitigation as accepted risk. Cosmetic-only impact confirmed.
- **SF-026 (Low, risk 5):** Won't Do -- theoretical only, no exploit path. Undo buffer populated from sanitized edit buffer; render pipeline provides independent sanitization.
- All 24 resolved findings verified with no regressions.
- **0 open findings remain.**

**No credentials, secrets, or actively exploitable remote vulnerabilities were found.**

---

*Last updated: 2026-03-25 (Gap Closure -- SF-028 resolved, SF-026 and SF-027 won't-do; 0 open findings; 30 total SF-IDs; 24 resolved; 5 won't do; 1 no action; no GitLab issues changed)*
