# Security Gap Analysis

**Project:** devnw/zig/repl -- Zig REPL Library
**Date:** 2026-03-24 (Phase 12 gap closure)
**Auditor:** Security Reviewer (automated + manual code review)
**Scope:** Full source tree at commit `f8eab0c` (branch: main)
**Classification:** INTERNAL -- Do not distribute outside the project team
**Revision:** 9 (Phase 12 gap closure -- SF-023 resolved)

---

## Overall Assessment

**No Critical or High severity findings. Zero open findings. 23 total SF-IDs tracked.**

The Zig REPL library maintains a sound security posture for a v0.1.0 release. The codebase
is memory-safe by default (Zig's safety checks), has no external C dependencies, and
uses minimal attack surface. Since the initial audit (2026-03-23), **17 of 22 findings
have been resolved**, with 3 marked Won't Do, 1 confirmed No Action Needed, and 0 open.

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
- Supply chain pinning for CI/CD dependencies (SF-012 -- Won't Do, external tooling)

---

## Audit Progression

| Metric | Initial (2026-03-23) | Re-audit (2026-03-24) | Post-closure (2026-03-24) | Phase 3 (2026-03-24) | Phase 4 (2026-03-24) | Phase 5 (2026-03-24) | Phase 9 (2026-03-24) | Phase 10 (2026-03-24) | Phase 11 (2026-03-24) | Delta (Phase 10 to 11) |
|--------|----------------------|-----------------------|---------------------------|----------------------|----------------------|----------------------|----------------------|-----------------------|-----------------------|------------------------|
| Total findings | 12 | 15 (cumulative) | 15 | 20 | 20 | 20 | 22 | 22 | 22 | 0 |
| Open | 12 | 6 | 0 | 2 | 0 | 0 | 2 | 2 | 0 | -2 |
| Resolved | 0 | 8 | 10 | 13 | 15 | 15 | 15 | 15 | 17 | +2 |
| Won't Do | 0 | 0 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 0 |
| No Action Needed | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 |
| Reclassified | 0 | 1 (SF-002 -> SF-014) | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 |
| Medium severity (open) | 4 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Low severity (open) | 8 | 3 | 0 | 2 | 0 | 0 | 2 | 2 | 0 | -2 |
| Manual findings reviewed | -- | -- | -- | -- | -- | 5 (MF-001..005) | 5 + NC-001, NC-002 re-confirmed | All prior findings re-verified | SF-021, SF-022 resolved | +2 resolved |

---

## Summary

| Severity | Total | Open | Resolved | Won't Do | No Action | SLA |
|----------|-------|------|----------|----------|-----------|-----|
| Critical | 0 | 0 | 0 | 0 | 0 | 7 days |
| High | 0 | 0 | 0 | 0 | 0 | 30 days |
| Medium | 6 | 0 | 5 | 0 | 0 | 90 days |
| Low | 17 | 0 | 13 | 3 | 1 | 180 days |
| Info | 0 | 0 | 0 | 0 | 0 | Backlog |
| **Total** | **22** | **0** | **17** | **3** | **1** | |

Note: SF-002 was reclassified as SF-014 with updated analysis. It is counted once (as SF-014, resolved).

### Zero open findings. No Critical, High, Medium, or Low findings remain open.

---

## Stack-Ranked Findings Table

### Open Findings (Phase 11)

_No open findings. All 22 SF-IDs are resolved, won't do, or no action needed._

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

### No Action Needed

| SF-ID | Severity | Risk Score | Finding | Reason |
|-------|----------|------------|---------|--------|
| SF-004 | Low | 15 | CONTRIBUTING.md license mismatch (root copy) | No action needed -- root `CONTRIBUTING.md` was checked and contains no MIT reference. It already references Apache-2.0 correctly. The `docs/CONTRIBUTING.md` copy was previously corrected (GAP-0003). |

### Resolved Findings

| SF-ID | Severity | Risk Score | Finding | Component | CWE / OWASP | Resolution | Verified |
|-------|----------|------------|---------|-----------|-------------|------------|----------|
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
OPEN (2 findings):
8   [==]          SF-021  Static mutable home_dir_buf (thread safety)  [OPEN]
8   [==]          SF-022  History file TOCTOU on permissions            [OPEN]

RESOLVED (15 findings):
50  [==========]  SF-014  Signal handler dead code                 [RESOLVED]
45  [=========]   SF-001  History/config world-readable            [RESOLVED]
40  [========]    SF-005  Bracketed paste forgery                  [RESOLVED]
35  [=======]     SF-009  Terminal escape injection                [RESOLVED]
35  [=======]     SF-013  Search bypasses history filtering        [RESOLVED]
25  [=====]       SF-007  Env var path injection                   [RESOLVED]
20  [====]        SF-003  @intCast overflow (32-bit)               [RESOLVED]
20  [====]        SF-016  Paste buffer flush-and-continue          [RESOLVED]
15  [===]         SF-020  CI hash pinned in repo                   [RESOLVED]
15  [===]         SF-018  renderPrompt buffer_full flag             [RESOLVED]
15  [===]         SF-010  Silent output truncation                 [RESOLVED]
10  [==]          SF-017  Search display input filter documented   [RESOLVED]
10  [==]          SF-019  Vi de/e underflow guard restructured     [RESOLVED]
10  [==]          SF-006  catch unreachable                        [RESOLVED]
10  [==]          SF-011  False fuzz claim                         [RESOLVED]

WON'T DO (3 findings):
20  [====]        SF-012  CI pinned by mutable tag                 [WON'T DO]
15  [===]         SF-008  File path traversal (by design)          [WON'T DO]
10  [==]          SF-015  Paste sanitization fragmentation         [WON'T DO]

NO ACTION NEEDED (1 finding):
15  [===]         SF-004  License mismatch in docs (root)          [NO ACTION]
```

---

## CWE Coverage

| CWE ID | CWE Name | Count | Findings | Status |
|--------|----------|-------|----------|--------|
| CWE-404 | Improper Resource Shutdown or Release | 1 | SF-014 | Resolved |
| CWE-362 | Race Condition (Shared Resource) | 1 | SF-021 | **Open** |
| CWE-367 | TOCTOU Race Condition | 1 | SF-022 | **Open** |
| CWE-116 | Improper Encoding or Escaping | 3 | SF-009, SF-013, SF-017 | All Resolved |
| CWE-130 | Length Parameter Inconsistency | 3 | SF-010, SF-016, SF-018 | All Resolved |
| CWE-191 | Integer Underflow | 1 | SF-019 | Resolved |
| CWE-494 | Download Without Integrity Check | 1 | SF-020 | Resolved |
| CWE-74 | Injection | 2 | SF-005, SF-015 | SF-005 Resolved, SF-015 Won't Do |
| CWE-829 | Untrusted Control Sphere | 1 | SF-012 | Won't Do |
| CWE-22 | Path Traversal | 1 | SF-008 | Won't Do (by design) |
| CWE-732 | Incorrect Permission Assignment | 1 | SF-001 | Resolved |
| CWE-426 | Untrusted Search Path | 1 | SF-007 | Resolved |
| CWE-190 | Integer Overflow | 1 | SF-003 | Resolved |
| CWE-248 | Uncaught Exception | 1 | SF-006 | Resolved |
| N/A | Documentation | 2 | SF-004, SF-011 | SF-011 Resolved, SF-004 No Action |

---

## Findings by Area

### Terminal / Platform (4 findings, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-014 | 50 | Signal handler dead code -- now wired into enterRawMode/restoreTerminalMode | **Resolved** |
| SF-018 | 15 | renderPrompt fixed buffer -- buffer_full flag stops writes on overflow | **Resolved** |
| SF-010 | 15 | Silent output truncation >4096 bytes | Resolved |
| SF-006 | 10 | catch unreachable on init | Resolved |

### Input Handling / Completion (7 findings, 1 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-005 | 40 | Bracketed paste end-marker forgery | Resolved |
| SF-009 | 35 | Terminal escape injection from history | Resolved |
| SF-013 | 35 | Search result bypasses history filtering | **Resolved** |
| SF-016 | 20 | Paste buffer flush-and-continue for arbitrarily large pastes | **Resolved** |
| SF-017 | 10 | Search display -- input filter documented as intentional guard | **Resolved** |
| SF-015 | 10 | Paste sanitization fragmentation gap (theoretical) | **Won't Do** |
| SF-021 | 8 | Static mutable `home_dir_buf` without thread safety (Windows-only) | **Open** |

### File System / Access Control (4 findings, 1 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-001 | 45 | History/config files world-readable | Resolved |
| SF-007 | 25 | Env var path injection | Resolved |
| SF-008 | 15 | File path completion traversal | **Won't Do** (by design) |
| SF-022 | 8 | History file TOCTOU on permissions | **Open** |

### Vi Keymap (1 finding, 0 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-019 | 10 | Vi de/e command fragile underflow guard | **Resolved** |

### History (2 findings, 1 open)

| SF-ID | Risk | Summary | Status |
|-------|------|---------|--------|
| SF-003 | 20 | @intCast overflow on 32-bit | Resolved |
| SF-022 | 8 | History file TOCTOU on permissions (also in File System section) | **Open** |

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
| SF-021 | Change `var home_dir_buf` to `threadlocal var home_dir_buf` | 5 min | **Open** |
| SF-022 | Add `file.chmod(0o600)` after opening existing history files | 15 min | **Open** |
| SF-019 | Restructured while-loop condition to `end + 1 < state.buffer.items.len` | 15 min | Resolved |
| SF-017 | Added safety comment documenting input filter as intentional guard | 30 min | Resolved |
| SF-020 | Pinned SHA-256 hashes in `.gitlab-ci.yml` variables; removed `index.json` fetch | 30 min | Resolved |

### Medium (1-5 days) -- ALL RESOLVED

| SF-ID | Fix | Effort | Status |
|-------|-----|--------|--------|
| SF-016 | Flush-and-continue: paste buffer flushes to edit buffer when full | 1-2 hours | Resolved |
| SF-018 | buffer_full flag: writes stop cleanly on overflow, cursor positioning skipped | 2-4 hours | Resolved |

### Strategic (> 5 days)

No strategic items. All open findings are small, self-contained hardening tasks.

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

**No immediate actions required.** Two Low/suspected findings (SF-021, SF-022) are open
but neither requires urgent remediation. Both have 180-day SLAs (due 2026-09-20).

**Phase 10 validation audit summary:**
- SF-021 and SF-022 remain at Low/suspected, risk scores unchanged at 8
- All 15 resolved findings verified with no regressions
- All trust boundaries (paste, key parsing, signals, history, config, search, env vars) reviewed and secure
- Quality findings (handleCompletion cursor, Vi o/O cursor, duplicate catch "") assessed -- none exploitable
- 0 new security findings, 0 regressions
- No GitLab issues created (no new security findings)

**No credentials, secrets, or actively exploitable remote vulnerabilities were found.**

---

*Last updated: 2026-03-24 (Phase 10 -- validation audit; 0 new findings, 0 regressions; SF-021/SF-022 unchanged; all 15 resolved verified; trust boundaries secure; quality findings non-exploitable)*
