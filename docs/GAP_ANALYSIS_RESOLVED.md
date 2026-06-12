# Gap Analysis -- Resolved Gaps

**Project:** Zig REPL Library (`/home/benji/src/gl/devnw/zig/repl`)
**Last updated:** 2026-06-12 (Audit Cycle 3 / Gap Closure -- 7 gaps resolved this cycle (GAP-0066..GAP-0072); 71 of 73 gaps resolved; GAP-0052 and GAP-0073 remain open)

This file tracks gaps that were previously open in `GAP_ANALYSIS.md` and have been resolved.
Gap-IDs are never reused. If a resolved gap regresses, a new Gap-ID is assigned referencing the old one.

---

## Resolved Gaps

| Gap-ID | Title | Resolution Date | Issue |
|--------|-------|-----------------|-------|
| GAP-0001 | README Quick Start will not compile | 2026-03-24 | [#34](https://gitlab.com/devnw/zig/repl/-/issues/34) (closed) |
| GAP-0025 | render.zig has zero unit tests | 2026-03-24 | [#82](https://gitlab.com/devnw/zig/repl/-/issues/82) (closed) |
| GAP-0026 | CI fuzz job has no fuzz targets in source code | 2026-03-24 | [#83](https://gitlab.com/devnw/zig/repl/-/issues/83) (closed) |
| GAP-0027 | Makefile fmt/check missing examples/ | 2026-03-24 | [#85](https://gitlab.com/devnw/zig/repl/-/issues/85) (closed) |
| GAP-0028 | CONTRIBUTING.md tree missing examples/ | 2026-03-24 | [#86](https://gitlab.com/devnw/zig/repl/-/issues/86) (closed) |
| GAP-0032 | ROADMAP.md #19 stale | 2026-03-24 | -- (doc/tracker discrepancy) |
| GAP-0033 | ROADMAP.md #21-24 stale | 2026-03-24 | -- (doc/tracker discrepancy) |
| GAP-0034 | ROADMAP.md staleness notice | 2026-03-24 | -- (process gap) |
| GAP-0002 | README configuration table has 5 wrong entries | 2026-03-24 | [#35](https://gitlab.com/devnw/zig/repl/-/issues/35) (closed) |
| GAP-0003 | License conflict in docs/CONTRIBUTING.md | 2026-03-24 | [#29](https://gitlab.com/devnw/zig/repl/-/issues/29) (closed) |
| GAP-0005 | Core REPL loop untested | 2026-03-24 | [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) (partial) |
| GAP-0006 | Keymap modules have no behavioral tests | 2026-03-24 | [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) (partial) |
| GAP-0007 | False security claim -- fuzz testing | 2026-03-24 | [#27](https://gitlab.com/devnw/zig/repl/-/issues/27) |
| GAP-0008 | Zig version error in docs/CONTRIBUTING.md | 2026-03-24 | [#30](https://gitlab.com/devnw/zig/repl/-/issues/30) (closed) |
| GAP-0009 | repl.zig doc comment has wrong API signature | 2026-03-24 | [#36](https://gitlab.com/devnw/zig/repl/-/issues/36) (closed) |
| GAP-0011 | Bracketed paste has no tests | 2026-03-24 | [#28](https://gitlab.com/devnw/zig/repl/-/issues/28) (closed) |
| GAP-0013 | welcome_fn undocumented in README | 2026-03-24 | [#33](https://gitlab.com/devnw/zig/repl/-/issues/33) (closed) |
| GAP-0014 | writeStyled example wrong in README | 2026-03-24 | [#38](https://gitlab.com/devnw/zig/repl/-/issues/38) (closed) |
| GAP-0015 | Config module disconnected from core | 2026-03-24 | [#39](https://gitlab.com/devnw/zig/repl/-/issues/39) (closed) |
| GAP-0016 | Missing SPDX header in integration.zig | 2026-03-24 | [#40](https://gitlab.com/devnw/zig/repl/-/issues/40) (closed) |
| GAP-0017 | Security contact email inconsistency | 2026-03-24 | [#41](https://gitlab.com/devnw/zig/repl/-/issues/41) (closed) |
| GAP-0020 | XDG/platform path resolution not tested | 2026-03-24 | [#32](https://gitlab.com/devnw/zig/repl/-/issues/32) (closed) |
| GAP-0012 | Vi visual mode is a stub | 2026-03-24 | [#37](https://gitlab.com/devnw/zig/repl/-/issues/37) (closed) |
| GAP-0019 | History deduplication only consecutive | 2026-03-24 | [#24](https://gitlab.com/devnw/zig/repl/-/issues/24) (closed) |
| GAP-0021 | Signal handler infrastructure is dead code | 2026-03-24 | [#45](https://gitlab.com/devnw/zig/repl/-/issues/45) (closed) |
| GAP-0022 | handleSearch() bypasses history filtering | 2026-03-24 | [#72](https://gitlab.com/devnw/zig/repl/-/issues/72) (closed) |
| GAP-0023 | CONTRIBUTING.md project structure tree incomplete | 2026-03-24 | [#73](https://gitlab.com/devnw/zig/repl/-/issues/73) (closed) |
| GAP-0024 | processInput grew to 216 lines (issue #56 worsening) | 2026-03-24 | [#74](https://gitlab.com/devnw/zig/repl/-/issues/74) (closed) |
| GAP-0029 | Issue #62 open but QF-012 marked resolved | 2026-03-24 | [#62](https://gitlab.com/devnw/zig/repl/-/issues/62) (closed) |
| GAP-0030 | Issue #63 open but QF-014 marked won't-do | 2026-03-24 | [#63](https://gitlab.com/devnw/zig/repl/-/issues/63) (closed) |
| GAP-0031 | Issue #64 open but QF-017 marked resolved | 2026-03-24 | [#64](https://gitlab.com/devnw/zig/repl/-/issues/64) (closed) |
| GAP-0036 | GAP-0024 resolution evidence inaccurate -- core.zig exceeds 800-line guideline | 2026-03-24 | [#88](https://gitlab.com/devnw/zig/repl/-/issues/88) (closed) |
| GAP-0037 | GAP_ANALYSIS.md test count and evidence numbers stale | 2026-03-24 | [#89](https://gitlab.com/devnw/zig/repl/-/issues/89) (closed) |
| GAP-0035 | Working tree contains 179 uncommitted tests and all gap resolution evidence | 2026-03-24 | [#87](https://gitlab.com/devnw/zig/repl/-/issues/87) (closed) |
| GAP-0004 | CI pipeline not verified on runners | 2026-03-24 | [#1](https://gitlab.com/devnw/zig/repl/-/issues/1), [#71](https://gitlab.com/devnw/zig/repl/-/issues/71) (closed) |
| GAP-0010 | Windows terminal support incomplete | 2026-03-24 | [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) (closed) |
| GAP-0018 | Undo is not real undo | 2026-03-24 | [#5](https://gitlab.com/devnw/zig/repl/-/issues/5) (closed), [#50](https://gitlab.com/devnw/zig/repl/-/issues/50) (closed) |
| GAP-0038 | CONTRIBUTING.md tree omits undo.zig | 2026-03-24 | [#95](https://gitlab.com/devnw/zig/repl/-/issues/95) (closed) |
| GAP-0039 | README Emacs keybindings missing Ctrl+_ | 2026-03-24 | [#96](https://gitlab.com/devnw/zig/repl/-/issues/96) (closed) |
| GAP-0040 | README Vi keybindings missing u (undo) | 2026-03-24 | [#97](https://gitlab.com/devnw/zig/repl/-/issues/97) (closed) |
| GAP-0041 | core.zig at 874 non-test lines | 2026-03-24 | [#98](https://gitlab.com/devnw/zig/repl/-/issues/98) (closed) |
| GAP-0042 | ARCHITECTURE.md missing 5 modules | 2026-03-24 | [#99](https://gitlab.com/devnw/zig/repl/-/issues/99) (closed) |
| GAP-0043 | ROADMAP.md issue #5 status stale | 2026-03-24 | [#100](https://gitlab.com/devnw/zig/repl/-/issues/100) (closed) |
| GAP-0044 | README Features list missing undo | 2026-03-24 | [#101](https://gitlab.com/devnw/zig/repl/-/issues/101) (closed) |
| GAP-0045 | Delete key triggers undo in Emacs mode | 2026-03-24 | [#102](https://gitlab.com/devnw/zig/repl/-/issues/102) (closed) |
| GAP-0046 | Delete key dead in Vi insert mode | 2026-03-24 | [#103](https://gitlab.com/devnw/zig/repl/-/issues/103) (closed) |
| GAP-0047 | config.zig missing from ARCHITECTURE.md | 2026-03-24 | -- (doc gap) |
| GAP-0048 | ROADMAP.md issue #15 status stale | 2026-03-24 | [#107](https://gitlab.com/devnw/zig/repl/-/issues/107) (closed) |
| GAP-0049 | CONTRIBUTING.md docs/ tree incomplete | 2026-03-24 | [#108](https://gitlab.com/devnw/zig/repl/-/issues/108) (closed) |
| GAP-0050 | README "Current Priorities" lists closed issues #1 and #15 | 2026-03-24 | [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed) |
| GAP-0051 | README Contributing section lists closed issues #15 and #21 | 2026-03-24 | [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed) |
| GAP-0053 | GAP_ANALYSIS.md test count stale (257 → 285) | 2026-03-24 | -- (doc staleness) |
| GAP-0054 | CONTRIBUTING.md project tree missing 10 root-level files | 2026-03-24 | -- (doc gap) |
| GAP-0055 | SECURITY.md CI scanning list missing Gitleaks | 2026-03-24 | -- (doc gap) |
| GAP-0056 | SECURITY.md CI scanning list missing SBOM | 2026-03-24 | -- (doc gap) |
| GAP-0057 | README API Reference missing SyntheticKey type | 2026-03-24 | -- (doc gap) |
| GAP-0058 | Minimum Zig version inconsistency (0.14.0 → 0.15.0) | 2026-03-24 | -- (doc/manifest discrepancy) |
| GAP-0059 | README API Reference missing 8 public items | 2026-03-25 | [#113](https://gitlab.com/devnw/zig/repl/-/issues/113) (closed) |
| GAP-0060 | CHANGELOG.md missing v0.1.1 entry | 2026-03-25 | [#114](https://gitlab.com/devnw/zig/repl/-/issues/114) (closed) |
| GAP-0061 | Copyright year stale | 2026-03-25 | [#115](https://gitlab.com/devnw/zig/repl/-/issues/115) (closed) |
| GAP-0062 | CONTRIBUTING.md Zig version | 2026-03-25 | [#112](https://gitlab.com/devnw/zig/repl/-/issues/112) (closed) |
| GAP-0063 | Duplicate CONTRIBUTING.md | 2026-03-25 | [#116](https://gitlab.com/devnw/zig/repl/-/issues/116) (closed) |
| GAP-0064 | .gitignore cleanup | 2026-03-25 | [#117](https://gitlab.com/devnw/zig/repl/-/issues/117) (closed) |
| GAP-0065 | README format check command | 2026-03-25 | [#118](https://gitlab.com/devnw/zig/repl/-/issues/118) (closed) |
| GAP-0066 | Config files written world-readable (CWE-732) | 2026-06-12 | [#122](https://gitlab.com/devnw/zig/repl/-/issues/122) |
| GAP-0067 | History permission enforcement on pre-existing files removed | 2026-06-12 | [#123](https://gitlab.com/devnw/zig/repl/-/issues/123) |
| GAP-0068 | compat.chmod is a silent no-op | 2026-06-12 | [#126](https://gitlab.com/devnw/zig/repl/-/issues/126) |
| GAP-0069 | sync_diamond_deps --cascade --apply blast radius | 2026-06-12 | [#124](https://gitlab.com/devnw/zig/repl/-/issues/124) |
| GAP-0070 | Observability seam hardcoded enabled=false | 2026-06-12 | [#127](https://gitlab.com/devnw/zig/repl/-/issues/127), [#140](https://gitlab.com/devnw/zig/repl/-/issues/140) |
| GAP-0071 | Docker base image not digest-pinned | 2026-06-12 | [#133](https://gitlab.com/devnw/zig/repl/-/issues/133) |
| GAP-0072 | processInput zero direct tests | 2026-06-12 | [#52](https://gitlab.com/devnw/zig/repl/-/issues/52) |

---

### GAP-0001: README Quick Start Will Not Compile [RESOLVED]

- **Issue:** [#34](https://gitlab.com/devnw/zig/repl/-/issues/34) (closed)
- **Category:** Docs
- **Resolution:** Rewrote Quick Start to use `run_fn` with correct `RunFn` callback signature returning `bool`. Also fixed Terminal Output and Command History sections.
- **Evidence:** `README.md` Quick Start example uses `run_fn` with signature `fn(?*anyopaque, Allocator, []const u8, *HistoryStore) anyerror!bool`
- **Resolved date:** 2026-03-24

### GAP-0002: README Configuration Table Has 5 Wrong Entries [RESOLVED]

- **Issue:** [#35](https://gitlab.com/devnw/zig/repl/-/issues/35) (closed)
- **Category:** Docs
- **Resolution:** Rebuilt configuration table from actual `Repl.Options` struct. All 13 fields now match. Added `history_enabled`, `app_name`, `verbose`, `welcome_fn`. Removed `max_history` and `use_color`. Fixed `execute_fn` -> `run_fn`, `history_file` -> `history_path`, `context` -> `user_context`.
- **Evidence:** Every row in README configuration table corresponds to a real field in `Repl.Options`
- **Resolved date:** 2026-03-24

### GAP-0003: License Conflict in docs/CONTRIBUTING.md [RESOLVED]

- **Issue:** [#29](https://gitlab.com/devnw/zig/repl/-/issues/29) (closed)
- **Category:** Docs
- **Resolution:** Changed `docs/CONTRIBUTING.md:158` from "MIT License" to "Apache-2.0 License".
- **Evidence:** `docs/CONTRIBUTING.md` -- all license references now say Apache-2.0
- **Resolved date:** 2026-03-24

### GAP-0004: CI Pipeline Not Verified on Runners [RESOLVED]

- **Issue:** [#1](https://gitlab.com/devnw/zig/repl/-/issues/1), [#71](https://gitlab.com/devnw/zig/repl/-/issues/71) (closed)
- **Category:** Infrastructure
- **Resolution:** Pipeline 2406048174 passed all 10 jobs on GitLab CI runners at commit `168625f`. Jobs verified: build, test (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall), zig-format, secret_detection, security-gitleaks, sbom-generate, sbom-scan.
- **Evidence:** Pipeline <https://gitlab.com/devnw/zig/repl/-/pipelines/2406048174> -- all 10 jobs green
- **Resolved date:** 2026-03-24

### GAP-0005: Core REPL Loop Untested [RESOLVED]

- **Issue:** [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) (partial -- issue covers broader test goals)
- **Category:** Test
- **Resolution:** Added behavioral tests for processAction, bracketed paste, keymap handling. Test count grew from 45 to 132.
- **Evidence:** `zig build test` -- 132 tests pass. Tests cover processAction key actions, bracketed paste content sanitization, and batch paste insertion.
- **Resolved date:** 2026-03-24

### GAP-0006: Keymap Modules Have No Behavioral Tests [RESOLVED]

- **Issue:** [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) (partial)
- **Category:** Test
- **Resolution:** Added mock TestState and 15+ keymap tests. 25 emacs behavioral tests and 24 vi behavioral tests now exist.
- **Evidence:** `src/keymap_emacs.zig` -- 25 behavioral tests; `src/keymap_vi.zig` -- 24 behavioral tests. Each verifies key mappings produce correct `KeyAction`.
- **Resolved date:** 2026-03-24

### GAP-0007: False Security Claim -- Fuzz Testing [RESOLVED]

- **Issue:** [#27](https://gitlab.com/devnw/zig/repl/-/issues/27)
- **Category:** Security
- **Resolution:** Updated `SECURITY.md:37` to "Fuzz testing for parser inputs (planned, not yet implemented)". Claim now accurately reflects project state.
- **Evidence:** `SECURITY.md` -- fuzz testing line now marked as planned, not implemented
- **Resolved date:** 2026-03-24

### GAP-0008: Zig Version Error in docs/CONTRIBUTING.md [RESOLVED]

- **Issue:** [#30](https://gitlab.com/devnw/zig/repl/-/issues/30) (closed)
- **Category:** Docs
- **Resolution:** Changed `docs/CONTRIBUTING.md:9` from "0.11.0 or later" to "0.14.0 or later".
- **Evidence:** `docs/CONTRIBUTING.md` now states same minimum Zig version as `README.md`
- **Resolved date:** 2026-03-24

### GAP-0009: repl.zig Doc Comment Has Wrong API Signature [RESOLVED]

- **Issue:** [#36](https://gitlab.com/devnw/zig/repl/-/issues/36) (closed)
- **Category:** Docs
- **Resolution:** Updated doc comment to use `run_fn` with correct `RunFn` signature. Fixed `KeyAction` description in Key Types section.
- **Evidence:** `src/repl.zig` doc comment example uses correct field name and callback signature
- **Resolved date:** 2026-03-24

### GAP-0011: Bracketed Paste Has No Tests [RESOLVED]

- **Issue:** [#28](https://gitlab.com/devnw/zig/repl/-/issues/28) (closed)
- **Category:** Test
- **Resolution:** Added tests for paste content sanitization and batch paste insertion.
- **Evidence:** Tests verify text between paste start/end sequences is inserted literally into the buffer
- **Resolved date:** 2026-03-24

### GAP-0013: welcome_fn Undocumented in README [RESOLVED]

- **Issue:** [#33](https://gitlab.com/devnw/zig/repl/-/issues/33) (closed)
- **Category:** Docs
- **Resolution:** Added `welcome_fn` row to README configuration table with type `?WelcomeFn`, default `null`, and description.
- **Evidence:** README configuration table includes `welcome_fn` entry
- **Resolved date:** 2026-03-24

### GAP-0014: writeStyled Example Wrong in README [RESOLVED]

- **Issue:** [#38](https://gitlab.com/devnw/zig/repl/-/issues/38) (closed)
- **Category:** Docs
- **Resolution:** Fixed writeStyled call to include Color argument: `try out.writeStyled(.italic, .default, "Emphasized")`. Also rewrote Terminal Output section to remove wrong callback wrapper pattern.
- **Evidence:** README writeStyled example now matches 3-argument function signature
- **Resolved date:** 2026-03-24

### GAP-0015: Config Module Disconnected from Core [RESOLVED]

- **Issue:** [#39](https://gitlab.com/devnw/zig/repl/-/issues/39) (closed)
- **Category:** Code Quality
- **Resolution:** Chose Option C -- documented the Config vs Repl.Options separation. Added comprehensive module-level doc comment to `src/config.zig` and note in README.
- **Evidence:** `src/config.zig` -- module-level doc comment explains Config vs Options; README Configuration Options section includes relationship note
- **Resolved date:** 2026-03-24

### GAP-0016: Missing SPDX Header in integration.zig [RESOLVED]

- **Issue:** [#40](https://gitlab.com/devnw/zig/repl/-/issues/40) (closed)
- **Category:** Code Quality
- **Resolution:** Added `// SPDX-License-Identifier: Apache-2.0` and copyright line to `tests/integration.zig`.
- **Evidence:** `tests/integration.zig:1` -- SPDX header present
- **Resolved date:** 2026-03-24

### GAP-0017: Security Contact Email Inconsistency [RESOLVED]

- **Issue:** [#41](https://gitlab.com/devnw/zig/repl/-/issues/41) (closed)
- **Category:** Docs
- **Resolution:** Changed `SECURITY.md:14` from `security@codepros.dev` to `security@devnw.com`. All files now use `security@devnw.com`.
- **Evidence:** All security contact references across SECURITY.md, CONTRIBUTING.md, and issue templates use `security@devnw.com`
- **Resolved date:** 2026-03-24

### GAP-0020: XDG/Platform Path Resolution Not Tested [RESOLVED]

- **Issue:** [#32](https://gitlab.com/devnw/zig/repl/-/issues/32) (closed)
- **Category:** Test
- **Resolution:** Added tests for path validation via `isPathSafe` in history and config modules.
- **Evidence:** Tests exercise XDG_DATA_HOME, XDG_CONFIG_HOME, HOME, and fallback path resolution
- **Resolved date:** 2026-03-24

### GAP-0012: Vi Visual Mode Is a Stub [RESOLVED]

- **Issue:** [#37](https://gitlab.com/devnw/zig/repl/-/issues/37) (closed)
- **Category:** Feature
- **Resolution:** Chose Option A -- removed `.visual` from `ViMode` enum. Added doc comment noting visual mode is not yet implemented. This eliminates the confusing stub behavior where `v` in vi mode silently delegated to normal mode.
- **Evidence:** `src/keymap_vi.zig` -- `.visual` variant removed from `ViMode` enum; doc comment documents visual mode as unimplemented
- **Resolved date:** 2026-03-24

### GAP-0019: History Deduplication Only Consecutive [RESOLVED]

- **Issue:** [#24](https://gitlab.com/devnw/zig/repl/-/issues/24) (closed)
- **Category:** Feature
- **Resolution:** Implemented global history deduplication. New `deduplicate_global` field on `HistoryStore`. When enabled, adding a command that already exists in history removes the earlier occurrence before appending the new one. 3 new tests added covering the deduplication behavior.
- **Evidence:** `src/history.zig` -- `deduplicate_global` field; deduplication logic removes earlier duplicates before append. 3 new tests verify global dedup behavior.
- **Resolved date:** 2026-03-24

### GAP-0021: Signal Handler Infrastructure Is Dead Code [RESOLVED]

- **Issue:** [#45](https://gitlab.com/devnw/zig/repl/-/issues/45) (closed)
- **Category:** Security
- **Resolution:** Wired signal handlers into terminal mode lifecycle. `enterRawMode()` now sets `saved_termios = original` and calls `installTerminalSignalHandlers()`. `restoreTerminalMode()` now calls `removeTerminalSignalHandlers()` and sets `saved_termios = null`.
- **Evidence:** `src/platform.zig:193-194` (install handlers in enterRawMode); `src/platform.zig:219-220` (remove handlers in restoreTerminalMode)
- **Resolved date:** 2026-03-24

### GAP-0022: handleSearch() Bypasses History Filtering [RESOLVED]

- **Issue:** [#72](https://gitlab.com/devnw/zig/repl/-/issues/72) (closed)
- **Category:** Bug
- **Resolution:** Changed `appendSlice` to `appendHistoryFiltered` at the search result insertion point. All history-to-buffer paths now consistently use filtered append, preventing terminal escape injection via reverse-i-search.
- **Evidence:** `src/core.zig:883` -- search result now uses `appendHistoryFiltered` instead of `appendSlice`
- **Resolved date:** 2026-03-24

### GAP-0023: CONTRIBUTING.md Project Structure Tree Incomplete [RESOLVED]

- **Issue:** [#73](https://gitlab.com/devnw/zig/repl/-/issues/73) (closed)
- **Category:** Docs
- **Resolution:** Updated `docs/CONTRIBUTING.md` project structure tree to include `repl.zig` (library root/public API re-export module), `text_utils.zig` (shared text processing utilities), `input.zig` (key parsing extracted from core), and `render.zig` (rendering calculations extracted from core).
- **Evidence:** `docs/CONTRIBUTING.md` project structure tree now lists all source files in `src/`
- **Resolved date:** 2026-03-24

### GAP-0024: processInput Grew to 216 Lines (Issue #56 Worsening) [RESOLVED]

- **Issue:** [#74](https://gitlab.com/devnw/zig/repl/-/issues/74) (closed), related to [#56](https://gitlab.com/devnw/zig/repl/-/issues/56)
- **Category:** Code Quality
- **Resolution:** Major refactoring of `processInput` from 215 lines to 53 lines. Extracted helper functions: `resetLineState`, `consumeBracketedPaste`, `appendToMultiLine`, `handleCommandSubmission`, `handleCancellation`. Key parsing moved to `src/input.zig`. Rendering calculations moved to `src/render.zig`. Sanitization functions moved to `src/text_utils.zig`. Further extraction of `handleSearch` to `src/search.zig`, `handleCompletion`, and `handleUnindent` brought `core.zig` to 801 non-test lines (1004 total with inline tests). The original resolution claim of 799 lines was inaccurate; the file was ~885 non-test lines at that time due to subsequently added paste and render tests.
- **Evidence:** `src/core.zig` -- processInput is 53 lines; processAction is 159 lines; non-test production code is 801 lines. New modules: `src/input.zig`, `src/render.zig`, `src/text_utils.zig`, `src/search.zig`. 224/224 tests pass.
- **Resolved date:** 2026-03-24

### GAP-0029: Issue #62 Open but QF-012 Marked Resolved [RESOLVED]

- **Issue:** [#62](https://gitlab.com/devnw/zig/repl/-/issues/62) (closed)
- **Category:** Docs
- **Resolution:** Closed issue #62 with comment citing QF-012 resolution in docs/QUALITY_GAP_ANALYSIS.md. The renderPrompt error handling had been addressed but the issue was left open.
- **Evidence:** Issue #62 closed; QF-012 status in QUALITY_GAP_ANALYSIS.md is "Resolved"
- **Resolved date:** 2026-03-24

### GAP-0030: Issue #63 Open but QF-014 Marked Won't-Do [RESOLVED]

- **Issue:** [#63](https://gitlab.com/devnw/zig/repl/-/issues/63) (closed)
- **Category:** Docs
- **Resolution:** Closed issue #63 with comment citing QF-014 won't-do decision in docs/QUALITY_GAP_ANALYSIS.md. The Vi kill ring silent allocation failure was accepted as intentional behavior.
- **Evidence:** Issue #63 closed; QF-014 status in QUALITY_GAP_ANALYSIS.md is "Won't Do"
- **Resolved date:** 2026-03-24

### GAP-0031: Issue #64 Open but QF-017 Marked Resolved [RESOLVED]

- **Issue:** [#64](https://gitlab.com/devnw/zig/repl/-/issues/64) (closed)
- **Category:** Docs
- **Resolution:** Closed issue #64 with comment citing QF-017 resolution in docs/QUALITY_GAP_ANALYSIS.md. The StatementChecker dead code had been addressed but the issue was left open.
- **Evidence:** Issue #64 closed; QF-017 status in QUALITY_GAP_ANALYSIS.md is "Resolved"
- **Resolved date:** 2026-03-24

### GAP-0025: render.zig Has Zero Unit Tests [RESOLVED]

- **Issue:** [#82](https://gitlab.com/devnw/zig/repl/-/issues/82) (closed)
- **Category:** Test
- **Resolution:** Added 28 unit tests to `src/render.zig` covering all 3 public functions: `tabWidth` (6 tests), `calculateVisualLines` (11 tests), `calculateCursorPosition` (11 tests). Edge cases covered: column boundaries, empty buffer, wrapping, multiple wraps, newlines, tabs, tab causing wrap, terminal_width=0, prompt_len effects.
- **Evidence:** `src/render.zig` -- 28 test blocks. `zig build test --summary all` passes (219 tests).
- **Resolved date:** 2026-03-24

### GAP-0026: CI Fuzz Job Has No Fuzz Targets in Source Code [RESOLVED]

- **Issue:** [#83](https://gitlab.com/devnw/zig/repl/-/issues/83) (closed)
- **Category:** CI-CD
- **Resolution:** Added 5 fuzz targets: 3 in `src/parse.zig` (`fuzz isBalanced`, `fuzz isComplete`, `fuzz needsContinuation`) and 2 in `src/input.zig` (`fuzz parseKeyEvent`, `fuzz getKeyEventLength`). All use `std.testing.fuzz` with seed corpus entries. `SECURITY.md` updated to reflect fuzz testing is implemented.
- **Evidence:** `src/parse.zig` -- 3 fuzz targets; `src/input.zig` -- 2 fuzz targets. `zig build test --fuzz` exercises all targets.
- **Resolved date:** 2026-03-24

### GAP-0027: Makefile fmt/check Targets Missing examples/ Directory [RESOLVED]

- **Issue:** [#85](https://gitlab.com/devnw/zig/repl/-/issues/85) (closed)
- **Category:** Code Quality
- **Resolution:** Added `examples/` to `Makefile` fmt and check targets, and to `.pre-commit-config.yaml` zig-fmt args.
- **Evidence:** `Makefile:12,15` -- `examples/` included in fmt/check targets. `.pre-commit-config.yaml` -- zig-fmt args include `examples/`.
- **Resolved date:** 2026-03-24

### GAP-0028: CONTRIBUTING.md Project Structure Tree Omits examples/ Directory [RESOLVED]

- **Issue:** [#86](https://gitlab.com/devnw/zig/repl/-/issues/86) (closed)
- **Category:** Docs
- **Resolution:** Added `examples/` directory with all 8 files (basic.zig, calculator.zig, colors.zig, completions.zig, history.zig, multiline.zig, shell.zig, vi_mode.zig) to `docs/CONTRIBUTING.md` project structure tree.
- **Evidence:** `docs/CONTRIBUTING.md` project structure tree now includes `examples/` directory listing.
- **Resolved date:** 2026-03-24

### GAP-0032: ROADMAP.md Shows Issue #19 as Open but Issue Is Closed [RESOLVED]

- **Issue:** -- (doc/tracker discrepancy, no separate issue)
- **Category:** Docs
- **Resolution:** Updated `docs/ROADMAP.md` issue #19 status from "Open" to "Closed".
- **Evidence:** `docs/ROADMAP.md` -- issue #19 row shows "Closed" status.
- **Resolved date:** 2026-03-24

### GAP-0033: ROADMAP.md Shows Issues #21, #22, #23, #24 as Open but All Closed [RESOLVED]

- **Issue:** -- (doc/tracker discrepancy, no separate issue)
- **Category:** Docs
- **Resolution:** Updated `docs/ROADMAP.md` issues #21, #22, #23, #24 statuses from "Open" to "Closed".
- **Evidence:** `docs/ROADMAP.md` -- all four rows show "Closed" status.
- **Resolved date:** 2026-03-24

### GAP-0034: ROADMAP.md Bulk Staleness (Systemic Process Gap) [RESOLVED]

- **Issue:** -- (process gap, no separate issue)
- **Category:** Other
- **Resolution:** Added authoritative-source notice to top of `docs/ROADMAP.md` stating that the GitLab issue tracker is the authoritative source and ROADMAP.md may be stale. Fixed all stale statuses via GAP-0032 and GAP-0033.
- **Evidence:** `docs/ROADMAP.md` -- authoritative-source notice present at top of file.
- **Resolved date:** 2026-03-24

### GAP-0036: GAP-0024 Resolution Evidence Inaccurate -- core.zig Exceeds 800-Line Guideline [RESOLVED]

- **Issue:** [#88](https://gitlab.com/devnw/zig/repl/-/issues/88) (closed)
- **Category:** Code Quality
- **Resolution:** Corrected GAP-0024 and QF-001 evidence to state actual line counts. Extracted `handleSearch` to `src/search.zig`, `handleCompletion` and `handleUnindent` as private helpers in core.zig, and `processAction` reduced to 159 lines. `core.zig` is now 801 non-test lines (1004 total with inline tests), at the 800-line guideline boundary.
- **Evidence:** `wc -l src/core.zig` = 1004; non-test production code ends at line 801; `docs/GAP_ANALYSIS_RESOLVED.md` and `docs/QUALITY_GAP_ANALYSIS.md` corrected.
- **Resolved date:** 2026-03-24

### GAP-0037: GAP_ANALYSIS.md Test Count and Evidence Numbers Stale [RESOLVED]

- **Issue:** [#89](https://gitlab.com/devnw/zig/repl/-/issues/89) (closed)
- **Category:** Docs
- **Resolution:** Updated GAP-0004 evidence line test count from "219/132 tests" to "224 tests". Header line 8 already corrected to 224 in previous sync. Historical counts in GAP_ANALYSIS_RESOLVED.md left as-is (point-in-time snapshots).
- **Evidence:** `docs/GAP_ANALYSIS.md:8` shows "224 tests"; GAP-0004 impact line shows "224 tests".
- **Resolved date:** 2026-03-24

### GAP-0010: Windows Terminal Support Incomplete [RESOLVED]

- **Issue:** [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) (closed)
- **Category:** Feature
- **Severity:** Medium
- **Resolution:** Replaced all `std.posix.getenv` calls with cross-platform comptime-branched alternatives. Implemented real `GetConsoleScreenBufferInfo` for terminal dimensions, `PeekConsoleInputW` for input detection, and `ENABLE_VIRTUAL_TERMINAL_PROCESSING`/`ENABLE_VIRTUAL_TERMINAL_INPUT` for ANSI escape support. Windows cross-compilation now succeeds (`zig build -Dtarget=x86_64-windows` exits 0).
- **Evidence:** 241/241 tests pass on Linux. Windows cross-compilation succeeds (was failing before). 6 new tests added. Files modified: `src/platform.zig`, `src/completion.zig`, `examples/colors.zig`, `examples/shell.zig`.
- **Residual note:** Runtime testing on actual Windows hardware pending Windows CI runner setup. All APIs have proper error handling with fallback values.
- **Resolved date:** 2026-03-24

### GAP-0018: Undo Is Not Real Undo [RESOLVED]

- **Issue:** [#5](https://gitlab.com/devnw/zig/repl/-/issues/5) (closed), [#50](https://gitlab.com/devnw/zig/repl/-/issues/50) (closed)
- **Category:** Feature
- **Severity:** Low
- **Resolution:** Created `src/undo.zig` with bounded `UndoStack` (max 100 entries). Integrated into `ReplState` in `src/core.zig` -- snapshots buffer before destructive actions, `.undo` action pops and restores. Added Ctrl+_ binding in emacs mode (`src/keymap_emacs.zig`). Vi mode `u` binding unchanged (already mapped to `.undo`).
- **Evidence:** 241/241 tests pass. 11 new tests (10 undo stack unit tests, 1 emacs keymap test). Memory safety verified via `testing.allocator` leak detection. Files modified: `src/core.zig`, `src/keymap_emacs.zig`. Files created: `src/undo.zig`.
- **Resolved date:** 2026-03-24

### GAP-0035: Working Tree Contains 179 Uncommitted Tests and All Gap Resolution Evidence [RESOLVED]

- **Issue:** [#87](https://gitlab.com/devnw/zig/repl/-/issues/87) (closed)
- **Category:** CI-CD
- **Resolution:** All 26 changed/new files committed in `eb7fa46` and pushed to `origin/main`. Commit includes source refactoring (input.zig, render.zig, text_utils.zig, search.zig extractions), 179 new tests, documentation updates, and CI infrastructure improvements. 5,093 insertions, 861 deletions across 26 files.
- **Evidence:** `git log --oneline -1` shows `eb7fa46` at HEAD. `git status` shows clean working tree. `zig build test --summary all` reports 224/224 tests passing.
- **Resolved date:** 2026-03-24

### GAP-0038: CONTRIBUTING.md Project Structure Tree Omits undo.zig [RESOLVED]

- **Issue:** [#95](https://gitlab.com/devnw/zig/repl/-/issues/95) (closed)
- **Category:** Docs
- **Resolution:** Added `src/undo.zig` and `src/text_utils.zig` to the project structure tree in `docs/CONTRIBUTING.md`.
- **Evidence:** `docs/CONTRIBUTING.md` project structure tree now lists all `src/*.zig` files including `undo.zig` and `text_utils.zig`.
- **Resolved date:** 2026-03-24

### GAP-0039: README Emacs Keybindings Missing Ctrl+_ [RESOLVED]

- **Issue:** [#96](https://gitlab.com/devnw/zig/repl/-/issues/96) (closed)
- **Category:** Docs
- **Resolution:** Added `Ctrl+_` / `Undo` row to the README.md Emacs keybindings table.
- **Evidence:** `README.md` Emacs keybindings table includes Ctrl+_ -> Undo.
- **Resolved date:** 2026-03-24

### GAP-0040: README Vi Keybindings Missing u (Undo) [RESOLVED]

- **Issue:** [#97](https://gitlab.com/devnw/zig/repl/-/issues/97) (closed)
- **Category:** Docs
- **Resolution:** Added `u` / `Undo` row to the README.md Vi normal mode keybindings table.
- **Evidence:** `README.md` Vi keybindings table includes `u` -> Undo.
- **Resolved date:** 2026-03-24

### GAP-0041: core.zig at 874 Non-Test Lines [RESOLVED]

- **Issue:** [#98](https://gitlab.com/devnw/zig/repl/-/issues/98) (closed)
- **Category:** Code Quality
- **Resolution:** Documented justification for 874-line exception in `docs/ARCHITECTURE.md`. The file is well-structured with clear sections (state management, input processing, action dispatch, rendering). Further splitting would increase inter-module coupling without reducing complexity. The 800-line guideline is a soft target; core.zig at 874 lines is within acceptable tolerance given its central role.
- **Evidence:** `docs/ARCHITECTURE.md` documents the exception with rationale.
- **Resolved date:** 2026-03-24

### GAP-0042: ARCHITECTURE.md Missing 5 Modules (35% of Codebase) [RESOLVED]

- **Issue:** [#99](https://gitlab.com/devnw/zig/repl/-/issues/99) (closed)
- **Category:** Docs
- **Resolution:** Added all 5 missing modules (`undo.zig`, `input.zig`, `render.zig`, `search.zig`, `text_utils.zig`) to the ARCHITECTURE.md module diagram and Key Components section. Documented interaction arrows for all new modules.
- **Evidence:** `docs/ARCHITECTURE.md` module diagram now lists all 14 `src/*.zig` files; Key Components section covers all modules.
- **Resolved date:** 2026-03-24

### GAP-0043: ROADMAP.md Issue #5 Status Stale [RESOLVED]

- **Issue:** [#100](https://gitlab.com/devnw/zig/repl/-/issues/100) (closed)
- **Category:** Docs
- **Resolution:** Updated `docs/ROADMAP.md` issue #5 (undo/redo) status from "Open" to "Closed". Verified #1 and #15 statuses are accurate.
- **Evidence:** `docs/ROADMAP.md` -- all issue statuses match their actual GitLab state.
- **Resolved date:** 2026-03-24

### GAP-0044: README Features List Missing Undo [RESOLVED]

- **Issue:** [#101](https://gitlab.com/devnw/zig/repl/-/issues/101) (closed)
- **Category:** Docs
- **Resolution:** Added "Undo/redo support" to the README.md Features bullet list.
- **Evidence:** `README.md` Features section now mentions undo/redo capability.
- **Resolved date:** 2026-03-24

### GAP-0045: Delete Key Triggers Undo Instead of Delete-Forward in Emacs Mode [RESOLVED]

- **Issue:** [#102](https://gitlab.com/devnw/zig/repl/-/issues/102) (closed)
- **Category:** Bug
- **Severity:** High
- **Resolution:** Introduced `SyntheticKey` constants in `src/input.zig` with `delete=0x04` to distinguish the Delete key (ESC[3~) from Ctrl+_(undo). The Emacs keymap now maps `SyntheticKey.delete` to `delete_char_forward` while Ctrl+_ continues to map to `.undo`. Integration tests verify both behaviors.
- **Evidence:** `src/input.zig` -- `SyntheticKey.delete = 0x04`; `src/keymap_emacs.zig` -- maps delete to `delete_char_forward`; `tests/integration.zig` -- Delete key and Ctrl+_ tests. 257/257 tests pass.
- **Resolved date:** 2026-03-24

### GAP-0046: Delete Key Does Nothing in Vi Insert Mode [RESOLVED]

- **Issue:** [#103](https://gitlab.com/devnw/zig/repl/-/issues/103) (closed)
- **Category:** Bug
- **Severity:** High
- **Resolution:** Same root cause fix as GAP-0045. `SyntheticKey.delete=0x04` in `src/input.zig` replaces the dead `0x1f` binding. Vi insert mode now maps `SyntheticKey.delete` to `delete_char_forward`. Dead `0x1f` binding removed. Integration tests verify Vi Delete behavior.
- **Evidence:** `src/keymap_vi.zig` -- maps `SyntheticKey.delete` to `delete_char_forward`; dead `0x1f` binding removed; `tests/integration.zig` -- Vi Delete key tests. 257/257 tests pass.
- **Resolved date:** 2026-03-24

### GAP-0047: config.zig Missing from ARCHITECTURE.md [RESOLVED]

- **Issue:** -- (doc gap, no platform issue needed)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Added `config.zig` to the ARCHITECTURE.md module diagram (middle tier alongside history.zig and platform.zig) and added a Key Components subsection describing Config, loadDefault/loadFromFile/saveToFile, getDefaultConfigPath, and the consumer-facing API pattern.
- **Evidence:** `docs/ARCHITECTURE.md` -- config.zig box in diagram, Key Components section with 6 bullet points. 257/257 tests pass.
- **Resolved date:** 2026-03-24

### GAP-0048: ROADMAP.md Issue #15 Status Stale [RESOLVED]

- **Issue:** [#107](https://gitlab.com/devnw/zig/repl/-/issues/107) (closed)
- **Category:** Docs
- **Resolution:** Updated `docs/ROADMAP.md` issue #15 status from "Open" to "Closed".
- **Evidence:** `docs/ROADMAP.md` -- issue #15 row shows "Closed" status.
- **Resolved date:** 2026-03-24

### GAP-0049: CONTRIBUTING.md docs/ Tree Incomplete [RESOLVED]

- **Issue:** [#108](https://gitlab.com/devnw/zig/repl/-/issues/108) (closed)
- **Category:** Docs
- **Resolution:** Added all 5 missing gap analysis files to the `docs/` section of the project structure tree in `docs/CONTRIBUTING.md`: GAP_ANALYSIS.md, GAP_ANALYSIS_RESOLVED.md, PERF_GAP_ANALYSIS.md, QUALITY_GAP_ANALYSIS.md, SECURITY_GAP_ANALYSIS.md.
- **Evidence:** `docs/CONTRIBUTING.md` -- docs/ section now lists all 8 files under docs/.
- **Resolved date:** 2026-03-24

### GAP-0050: README "Current Priorities" Lists Closed Issues #1 and #15 [RESOLVED]

- **Issue:** [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed, combined with GAP-0051)
- **Category:** Docs
- **Resolution:** Removed closed issues #1, #15, and #21 from README.md "Current Priorities" and "Contributing" sections. Replaced with currently open issues.
- **Evidence:** `README.md` -- all issues listed in Current Priorities table are open in GitLab.
- **Resolved date:** 2026-03-24

### GAP-0051: README Contributing Section Lists Closed Issues #15 and #21 [RESOLVED]

- **Issue:** [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed, combined with GAP-0050)
- **Category:** Docs
- **Resolution:** Removed closed issues #15 and #21 from README Contributing help-needed section. Replaced with currently open issues.
- **Evidence:** `README.md` -- all issues listed in Contributing help-needed section are open in GitLab.
- **Resolved date:** 2026-03-24

### GAP-0053: GAP_ANALYSIS.md Test Count Stale (257 -> 285) [RESOLVED]

- **Issue:** -- (doc staleness)
- **Category:** Docs
- **Resolution:** Updated GAP_ANALYSIS.md header test count from "257 tests" to "285 tests" to reflect the 28 new processAction unit tests added in QF-026/QF-066 work.
- **Evidence:** `docs/GAP_ANALYSIS.md:8` -- "285 tests"
- **Resolved date:** 2026-03-24

### GAP-0054: CONTRIBUTING.md Project Tree Missing 10 Root-Level Files [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Docs
- **Resolution:** Added build.zig.zon, Makefile, LICENSE, CHANGELOG.md, SECURITY.md, CODE_OF_CONDUCT.md, CODEOWNERS, NOTICE, SUPPORT.md, and README.md to the CONTRIBUTING.md project structure tree.
- **Evidence:** `docs/CONTRIBUTING.md:150-160` -- all root-level files listed
- **Resolved date:** 2026-03-24

### GAP-0055: SECURITY.md CI Scanning List Missing Gitleaks [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Security
- **Resolution:** Added "Gitleaks: Enhanced secrets detection" to the CI/CD Security Scanning list in SECURITY.md. Pipeline evidence confirms security-gitleaks job runs.
- **Evidence:** `SECURITY.md` CI/CD Security Scanning section lists Gitleaks
- **Resolved date:** 2026-03-24

### GAP-0056: SECURITY.md CI Scanning List Missing SBOM [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Security
- **Resolution:** Added "SBOM: Software Bill of Materials generation and scanning" to the CI/CD Security Scanning list in SECURITY.md. Pipeline evidence confirms sbom-generate and sbom-scan jobs run.
- **Evidence:** `SECURITY.md` CI/CD Security Scanning section lists SBOM
- **Resolved date:** 2026-03-24

### GAP-0057: README API Reference Missing SyntheticKey Type [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Docs
- **Resolution:** Added SyntheticKey to the README Core Types section: "SyntheticKey - Named constants for special keys (Insert, Delete, Page Up, Page Down)".
- **Evidence:** `README.md:303` -- SyntheticKey listed in Core Types
- **Resolved date:** 2026-03-24

### GAP-0058: Minimum Zig Version Inconsistency (build.zig.zon vs Docs) [RESOLVED]

- **Issue:** -- (doc/manifest discrepancy)
- **Category:** Docs
- **Resolution:** Updated build.zig.zon `.minimum_zig_version` from "0.14.0" to "0.15.0" and README status table from "0.14.0+" to "0.15.x" to match the actual Zig 0.15.2 installed and required by the codebase.
- **Evidence:** `build.zig.zon:5` -- `"0.15.0"`; `README.md:10` -- "0.15.x"
- **Resolved date:** 2026-03-24

### GAP-0059: README API Reference Missing 8 Public Items [RESOLVED]

- **Issue:** [#113](https://gitlab.com/devnw/zig/repl/-/issues/113) (closed)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Added Config, CompleteFn, terminalWriter, getStdinHandle, getStdoutHandle, getStderrHandle, isStderrTty, and version constants (version, version_major, version_minor, version_patch) to README.md API Reference section.
- **Evidence:** `README.md` API Reference section now documents all public exports from `src/repl.zig`
- **Resolved date:** 2026-03-25

### GAP-0060: CHANGELOG.md Missing v0.1.1 Entry and Broken Links [RESOLVED]

- **Issue:** [#114](https://gitlab.com/devnw/zig/repl/-/issues/114) (closed)
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Added `## [0.1.1] - 2026-01-26` section with CI/CD changes. Fixed [Unreleased] link to compare v0.1.1...HEAD, added [0.1.1] comparison link, and fixed [0.1.0] link to releases page.
- **Evidence:** `CHANGELOG.md` -- v0.1.1 section present; all comparison links use correct tag-based URLs
- **Resolved date:** 2026-03-25

### GAP-0061: Copyright Year 2024-2025 Stale in Source Files and LICENSE [RESOLVED]

- **Issue:** [#115](https://gitlab.com/devnw/zig/repl/-/issues/115) (closed)
- **Category:** Docs (Legal)
- **Severity:** Low
- **Resolution:** Updated copyright year from "2024-2025" to "2024-2026" in all src/_.zig (15 files), examples/_.zig (8 files), tests/integration.zig, build.zig, LICENSE, .gitleaks.toml, and CODEOWNERS. Entity name discrepancy (CodePros vs DevNW LLC) left as maintainer decision.
- **Evidence:** `grep -r "2024-2025"` returns only GAP_ANALYSIS.md references to the old state
- **Resolved date:** 2026-03-25

### GAP-0062: CONTRIBUTING.md:9 Says "0.14.0" Instead of "0.15.0" [RESOLVED]

- **Issue:** [#112](https://gitlab.com/devnw/zig/repl/-/issues/112) (closed)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `docs/CONTRIBUTING.md:9` from "Zig (0.14.0 or later)" to "Zig 0.15.0 or later" to match `build.zig.zon` `.minimum_zig_version`.
- **Evidence:** `docs/CONTRIBUTING.md:9` -- "Zig 0.15.0 or later"
- **Resolved date:** 2026-03-25

### GAP-0063: Root CONTRIBUTING.md Duplicates docs/CONTRIBUTING.md [RESOLVED]

- **Issue:** [#116](https://gitlab.com/devnw/zig/repl/-/issues/116) (closed)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Replaced root CONTRIBUTING.md content with a short redirect to docs/CONTRIBUTING.md. No unique content from the root file needed merging.
- **Evidence:** `CONTRIBUTING.md` -- 3-line redirect to `docs/CONTRIBUTING.md`
- **Resolved date:** 2026-03-25

### GAP-0064: .gitignore Contains Irrelevant Go/Python/Rust/Docker/Node Rules [RESOLVED]

- **Issue:** [#117](https://gitlab.com/devnw/zig/repl/-/issues/117) (closed)
- **Category:** Code Quality
- **Severity:** Low
- **Resolution:** Rewrote .gitignore from 206 lines to ~35 lines containing only Zig build artifacts, editor/IDE files, OS artifacts, secrets, and temporary files. Removed all Go, Python, Rust, Docker, and Node.js rules.
- **Evidence:** `.gitignore` -- contains only Zig-relevant rules
- **Resolved date:** 2026-03-25

### GAP-0065: README Building Section Incomplete Format Check Command [RESOLVED]

- **Issue:** [#118](https://gitlab.com/devnw/zig/repl/-/issues/118) (closed)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated both README.md and docs/CONTRIBUTING.md format check commands from `zig fmt --check src/` to `zig fmt --check src/ tests/ examples/ build.zig` matching the Makefile check target.
- **Evidence:** `README.md` and `docs/CONTRIBUTING.md` both show the complete format check command
- **Resolved date:** 2026-03-25

### GAP-0066: Config Files Written World-Readable -- No-op chmod + Missing .permissions (CWE-732) [RESOLVED]

- **Issue:** [#122](https://gitlab.com/devnw/zig/repl/-/issues/122)
- **Category:** Security
- **Severity:** High
- **Resolution:** Config persistence now writes with restrictive permissions. `src/config.zig` sets `.permissions = 0o600` on create and performs an atomic save (write to temp file, then rename) so the config file is never world-readable at any point. Added a test asserting the saved config file mode is `0o600` (SF-001/SF-023 regression closed).
- **Evidence:** commit ec9a1dc -- `src/config.zig` save path uses `.permissions = 0o600` + atomic temp-write/rename; permission-assertion test added
- **Resolved date:** 2026-06-12

### GAP-0067: History Permission Enforcement on Pre-existing Files Removed [RESOLVED]

- **Issue:** [#123](https://gitlab.com/devnw/zig/repl/-/issues/123)
- **Category:** Security
- **Severity:** Medium
- **Resolution:** History save re-tightens permissions on pre-existing files via `compat.chmod`, restoring enforcement for files that already existed on disk (not just newly created ones). Added tests covering the pre-existing-file path (SF-022/SF-024 regression closed).
- **Evidence:** commit ec9a1dc -- history save path calls `compat.chmod` to re-tighten pre-existing file permissions; tests added
- **Resolved date:** 2026-06-12

### GAP-0068: compat.chmod Is a Silent No-op [RESOLVED]

- **Issue:** [#126](https://gitlab.com/devnw/zig/repl/-/issues/126)
- **Category:** Security
- **Severity:** Low
- **Resolution:** Replaced the no-op `compat.chmod` shim with a real `setPermissions` implementation so permission tightening actually takes effect for all callers. Added a test verifying the resulting file mode.
- **Evidence:** commit ec9a1dc -- `compat.chmod` now performs a real `setPermissions` call; mode-verification test added
- **Resolved date:** 2026-06-12

### GAP-0069: sync_diamond_deps --cascade --apply Blast Radius [RESOLVED]

- **Issue:** [#124](https://gitlab.com/devnw/zig/repl/-/issues/124)
- **Category:** Security
- **Severity:** Medium
- **Resolution:** Hardened `sync_diamond_deps.py --cascade --apply` against unbounded blast radius: added an interactive confirmation gate, an allowlist of permitted target remotes, target verification before any push, and guarded deletes (no unconditional `rm -rf` from untrusted input).
- **Evidence:** commit 5eae04d -- `scripts/sync_diamond_deps.py` adds confirmation/allowlist/target-verify/guarded-delete controls
- **Resolved date:** 2026-06-12

### GAP-0070: Observability Seam Hardcoded enabled=false [RESOLVED]

- **Issue:** [#127](https://gitlab.com/devnw/zig/repl/-/issues/127), [#140](https://gitlab.com/devnw/zig/repl/-/issues/140)
- **Category:** Code Quality
- **Severity:** Low
- **Resolution:** Restored the observability seam so `enabled` is driven by `build_options.with_otel` instead of a hardcoded `false`. The `-Dwith_otel` build flag now has effect, and a CI `test-with-otel` job exercises the enabled path so it cannot silently rot.
- **Evidence:** commit cf50500 -- `enabled = build_options.with_otel`; CI `test-with-otel` job added
- **Resolved date:** 2026-06-12

### GAP-0071: Docker Base Image Not Digest-Pinned [RESOLVED]

- **Issue:** [#133](https://gitlab.com/devnw/zig/repl/-/issues/133)
- **Category:** CI-CD
- **Severity:** Low
- **Resolution:** Pinned the CI Docker base image `debian:bookworm-slim` to an immutable digest (`sha256:96e378d7e6531ac9a15ad505478fcc2e69f371b10f5cdf87857c4b8188404716`) via a `$DEBIAN_IMAGE` variable, removing the floating tag for reproducible builds.
- **Evidence:** commit cf50500 -- CI config pins `debian:bookworm-slim@sha256:96e378d7...4716` through `$DEBIAN_IMAGE`
- **Resolved date:** 2026-06-12

### GAP-0072: processInput Zero Direct Tests [RESOLVED]

- **Issue:** [#52](https://gitlab.com/devnw/zig/repl/-/issues/52)
- **Category:** Test
- **Severity:** Medium
- **Resolution:** Extracted a testable `processReadBuffer` from `processInput` and added direct tests driven by a mock stdin, giving the input loop real coverage. 18 new core tests added covering the read/parse path.
- **Evidence:** commit d039c05 -- `processReadBuffer` extracted from `processInput`; 18 mock-stdin core tests added
- **Resolved date:** 2026-06-12

---

## Won't Do / Deferred

_No Won't-Do items in the main gap tracker. 71 of 73 gaps have been resolved. Two gaps remain open: GAP-0052 (blocked on #31 -- release signing CI enforcement) and GAP-0073 (deferred -- API docs not generated/published, tracked on #20)._
