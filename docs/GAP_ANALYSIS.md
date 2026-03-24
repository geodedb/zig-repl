# Gap Analysis Report

**Project:** Zig REPL Library (`/home/benji/src/gl/devnw/zig/repl`)
**Date:** 2026-03-24 (Phase 8 -- GAP-0004 resolved, CI pipeline verified)
**Previous audit:** 2026-03-24 (Phase 7 close-out, 3 open gaps)
**Auditor:** Principal Engineer Audit (Claude Opus 4.6)
**Zig Version Installed:** 0.15.2
**Build Status:** Tests pass (`zig build test` exits 0, 224 tests)

---

## Summary

- **Total gaps identified (all time):** 37
- **Resolved (all time):** 35 (GAP-0001..GAP-0004, GAP-0005..GAP-0009, GAP-0011..GAP-0017, GAP-0019..GAP-0028, GAP-0029..GAP-0037)
- **Total open gaps:** 2
- **Carried forward (still open):** 2 (GAP-0010, GAP-0018)
- **New gaps (Phase 5):** 3 (GAP-0035, GAP-0036, GAP-0037) -- all 3 resolved, moved to GAP_ANALYSIS_RESOLVED.md
- **New gaps (Phase 3):** 10 (GAP-0025..GAP-0034)
- **Resolved during Phase 1 quick fixes:** 5 (GAP-0027, GAP-0028, GAP-0032, GAP-0033, GAP-0034)
- **Resolved during previous sync:** 3 (GAP-0029, GAP-0030, GAP-0031 -- moved to GAP_ANALYSIS_RESOLVED.md)
- **Resolved and moved this cycle:** 3 (GAP-0035, GAP-0036, GAP-0037 -- moved to GAP_ANALYSIS_RESOLVED.md)

---

## Gap Index (Open Only)

| Gap-ID   | Issue | Severity | Category     | Title                                          |
|----------|-------|----------|--------------|-------------------------------------------------|
| GAP-0010 | [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) | Medium | Feature | Windows terminal support incomplete |
| GAP-0018 | [#5](https://gitlab.com/devnw/zig/repl/-/issues/5), [#50](https://gitlab.com/devnw/zig/repl/-/issues/50) | Low | Feature | Undo is not real undo |

---

_GAP-0035 resolved and moved to [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)._

---

## Medium Gaps

_GAP-0004 resolved and moved to [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)._

### GAP-0010: Windows Terminal Support Incomplete

- **Issue:** [#15](https://gitlab.com/devnw/zig/repl/-/issues/15)
- **Category:** Feature
- **Severity:** Medium
- **Status:** Blocked -- requires Windows platform for development and testing
- **Requirement source:** REQ-022 (Windows support), REQ-023 (terminal dimensions), REQ-024 (input detection)
- **Current state (evidence):**
  - `src/platform.zig:141` -- `getTerminalWidth` returns hardcoded `80` on Windows
  - `src/platform.zig:156` -- `getTerminalHeight` returns hardcoded `24` on Windows
  - `src/platform.zig:169-171` -- `stdinHasMoreData` always returns `false` on Windows
  - No `SetConsoleMode` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING` call for ANSI escape handling
- **Why this is a gap:** Windows users get hardcoded 80x24 dimensions regardless of actual terminal size, no input buffering detection, and potentially broken ANSI output.
- **Impact/Risk:** Poor user experience on Windows. Layout will be wrong in terminals wider/taller than 80x24.
- **Blocker:** Development and testing environment is Linux. Windows platform access needed.
- **Unblock steps:**
  1. Set up Windows development/CI environment
  2. Implement `GetConsoleScreenBufferInfo` for actual dimensions
  3. Implement `WaitForSingleObject` or `PeekConsoleInput` for `stdinHasMoreData`
  4. Call `SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_PROCESSING` for ANSI support
- **Acceptance criteria:** Windows terminal dimensions are dynamically queried and ANSI escape sequences work in Windows Terminal and cmd.exe.

---

## Low Gaps

### GAP-0018: Undo Is Not Real Undo

- **Issue:** [#5](https://gitlab.com/devnw/zig/repl/-/issues/5), [#50](https://gitlab.com/devnw/zig/repl/-/issues/50)
- **Category:** Feature
- **Severity:** Low
- **Status:** Deferred -- tracked in issue #5 for future implementation
- **Requirement source:** REQ-044 (undo functionality)
- **Current state (evidence):**
  - `src/core.zig` -- undo action replaces entire buffer with kill ring contents
  - No undo stack or previous-state tracking exists in the codebase
  - This is a paste operation, not undo
- **Why this is a gap:** The undo action exists in the `KeyAction` enum and is mapped to a keybinding, but its implementation does not perform undo. It destructively replaces the buffer.
- **Impact/Risk:** Users pressing undo (Ctrl+_ in emacs mode) will lose their current buffer contents. Low severity because this is tracked as a known roadmap item.
- **Recommended fix:** Implement an undo stack that records buffer snapshots before destructive operations, as tracked in issue #5.
- **Acceptance criteria:** Pressing undo restores the buffer to its state before the last destructive edit operation.

_GAP-0035, GAP-0036, and GAP-0037 resolved and moved to [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)._

---

## Gap Priority Matrix

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 1 | GAP-0010 (blocked) |
| Low | 1 | GAP-0018 (deferred) |

---

## Recommended Remediation Order

### Phase 1: Quick wins (no blockers) -- COMPLETED
1. ~~**GAP-0027** -- Add `examples/` to Makefile fmt/check targets~~ Resolved
2. ~~**GAP-0028** -- Add `examples/` to CONTRIBUTING.md project structure tree~~ Resolved
3. ~~**GAP-0032** -- Update ROADMAP.md issue #19 status to Closed~~ Resolved
4. ~~**GAP-0033** -- Update ROADMAP.md issues #21, #22, #23, #24 status to Closed~~ Resolved
5. ~~**GAP-0034** -- Add authoritative-source notice to ROADMAP.md~~ Resolved

### Phase 1b: Test gaps (no blockers)
6. ~~**GAP-0025** -- Add unit tests for render.zig (pure functions, easy to test)~~ Resolved

### Phase 2: Infrastructure (blocked)
7. ~~**GAP-0004** -- Verify CI pipeline on runners~~ Resolved (pipeline 2406048174 passed all stages)
8. ~~**GAP-0026** -- Add fuzz targets to source code~~ Resolved

### Phase 3: Platform (blocked)
9. **GAP-0010** -- Windows terminal improvements (blocked on Windows environment)

### Phase 4: Feature work (deferred)
10. **GAP-0018** -- Real undo implementation (tracked in issue #5)

### Phase 5: New gaps (2026-03-24 sync)
11. ~~**GAP-0035** -- Commit and push all working tree changes~~ Resolved (issue #87 closed)
12. ~~**GAP-0036** -- Correct GAP-0024 resolution evidence line counts~~ Resolved (issue #88 closed)
13. ~~**GAP-0037** -- Update stale test counts in GAP_ANALYSIS.md~~ Resolved (issue #89 closed)
