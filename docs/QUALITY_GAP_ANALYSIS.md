# Quality Gap Analysis -- Zig REPL Library

**Project**: gitlab.com/devnw/zig/repl
**Last updated**: 2026-03-25 (Phase 23 closure -- 4 resolved: QF-084, QF-085, QF-086, QF-087)
**Audit phase**: Phase 23 closure
**Total findings**: 85 (4 won't-do, 66 resolved, 1 accepted, 13 open, 1 partial)

---

## Summary

### Severity Distribution (Open/Partial/Accepted Only)

| Severity | Count | PriorityScore Range |
|----------|-------|---------------------|
| Critical | 0     | --                  |
| High     | 2     | 60-85               |
| Medium   | 1     | 40 (accepted)       |
| Low      | 12    | 12-20               |

### Severity Distribution (All, Including Resolved)

| Severity | Count (Total) | Open | Partial | Won't Do | Accepted | Resolved |
|----------|---------------|------|---------|----------|----------|----------|
| Critical | 6             | 0    | 0       | 0        | 0        | 6        |
| High     | 13            | 1    | 1       | 0        | 0        | 11       |
| Medium   | 25            | 0    | 0       | 2        | 1        | 22       |
| Low      | 41            | 12   | 0       | 1        | 0        | 28       |

### Top Open/Partial/Accepted Risks

1. **Core REPL loop test coverage (partial)** (QF-026, Score 85) -- `processAction` now has 27 dedicated unit tests covering all non-I/O KeyAction variants. `processInput` still needs mock stdin/stdout infrastructure (issue #52).
2. **search.zig zero test coverage** (QF-067, Score 60) -- 73 lines, 0 test blocks. All code paths (ESC exit, Ctrl-C cancel, backspace, printable input, history match/miss) untested. Issue [#119](https://gitlab.com/devnw/zig/repl/-/issues/119).
3. **core.zig at ~878 non-test lines** (QF-050, Score 40) -- Growth justified by undo integration; documented in ARCHITECTURE.md size note. Accepted.
4. **platform.zig regressed to 908 lines** (QF-083, Score 20) -- Was 796 after QF-042; regressed past 800-line guideline. Continuing regression.
5. **parseKeyEvent depth-7 nesting** (QF-073, Score 20) -- input.zig L40-105: 7 levels of nested if statements. Refactor to early-return pattern.

Phase 23 closure resolved all 4 findings from Phase 23 intake (QF-084 through QF-087): QF-084 (doc comments added to 6 public functions in completion.zig, config.zig, core.zig), QF-085 (6 new tests for config.zig: loadFromFile, saveToFile, round-trip, getDefaultConfigPath), QF-086 (resolveEnvOverridePath extracted to text_utils.zig, deduplicating ~50 lines), QF-087 (handleSearch ESC/Ctrl+C reset history_index to null; Enter preserves position). Phase 23 intake added 4 new findings (QF-084 through QF-087) from quality-reviewer. All Low severity. Phase 21 added 15 new validated findings (QF-067 through QF-083; QF-068 rejected as duplicate of PF-038). 1 High (search.zig test gap), 14 Low (readability, consistency, correctness). Phase 20 resolved QF-065 (isStderrTty re-export) and QF-066 (delete_char_forward test). Phase 19 added 27 processAction unit tests (QF-026 Deferred->Partial); closed QF-018 and QF-019 as Won't Do (intentional consumer-facing APIs). Phase 18 resolved QF-064. Phase 17 resolved QF-058 through QF-063 and accepted QF-050.

---

## Stack-Ranked Findings Table

### Open Findings

| Rank | QF-ID | Severity | Score | Category | Finding | Component | Evidence | Issue | Fix Summary | Owner | Effort | Status |
|------|-------|----------|-------|----------|---------|-----------|----------|-------|-------------|-------|--------|--------|
| 1 | QF-026 | High | 85 | Testing | Core loop test coverage partial | core.zig | `processAction`: 27 dedicated tests covering all non-I/O KeyAction variants; `processInput`: 0 direct tests (needs mock stdin/stdout) | [#52](https://gitlab.com/devnw/zig/repl/-/issues/52) | Phase 1 done: 27 processAction tests added. Phase 2 remains: mock harness for processInput | Maintainers | L | Partial |
| 2 | QF-067 | High | 60 | Testing | search.zig zero test coverage (73 lines, 0 tests) | search.zig | `wc -l src/search.zig` = 73; `grep -c "^test " src/search.zig` = 0; 7 untested code paths (ESC exit, Ctrl-C cancel, backspace, printable input, history match/miss, truncation) | [#119](https://gitlab.com/devnw/zig/repl/-/issues/119) | Add 8+ tests covering all code paths using TestState mock pattern | Maintainers | S | Open |
| 3 | QF-050 | Medium | 40 | Readability | core.zig at ~878 non-test lines (growth justified by undo integration) | core.zig | `wc -l src/core.zig` = 1554; first test at L879; non-test boundary at ~L878 | [#90](https://gitlab.com/devnw/zig/repl/-/issues/90) (closed) | Growth justified by undo integration; documented in ARCHITECTURE.md size note | Maintainers | -- | Accepted |
| 4 | QF-069 | Low | 20 | Readability | 9 unreachable `catch {}` on shrinking replaceRange | core.zig, keymap_vi.zig | core.zig:636,646,661,775,785,831; keymap_vi.zig:243,253,264 -- `replaceRange(..., &.{})` cannot fail when shrinking (no allocation needed) | -- | All 9 `catch {}` changed to `catch unreachable` with safety comment | Maintainers | S | Resolved |
| 5 | QF-073 | Low | 20 | Readability | parseKeyEvent depth-7 nesting | input.zig | L40-105: `if (data[0] == 0x1b) { if (data.len > 1) { if (data[1] == '[') { if (data.len > 2) { if (data.len > 3 ...) } } } }` -- 7 levels of nesting | -- | Refactor to early-return pattern or extract helper functions for ESC sequence families | Maintainers | S | Open |
| 6 | QF-083 | Low | 20 | Readability | platform.zig regressed to 908 lines | platform.zig | `wc -l src/platform.zig` = 908; was 796 after QF-042 fix; 108 lines over 800-line guideline | -- | Extract platform-specific helpers or test utilities to reduce below 800 lines | Maintainers | S | Open |
| 7 | QF-085 | Low | 20 | Testing | config.zig has only 3 tests for 240 non-test lines | config.zig | 3 test blocks for 240 non-test lines; `loadFromFile`, `saveToFile`, `getDefaultConfigPath` completely untested; round-trip and edge-case tests needed | -- | 6 new tests added: loadFromFile, saveToFile, round-trip, getDefaultConfigPath; `src/config.zig` now has 9 test blocks | Maintainers | S | Resolved |
| 8 | QF-070 | Low | 16 | Readability | processAction regrown to 169 lines | core.zig | L597-765: `processAction` was reduced to 159 lines (QF-051) but has regrown to 169 lines | -- | Monitor; extract if it grows past 180 lines | Maintainers | S | Open |
| 9 | QF-071 | Low | 16 | Readability | generateFilePathCandidates 87 lines | completion.zig | L191-277: single function with tilde expansion, absolute path, relative path, directory iteration, and sorting | -- | Extract tilde expansion and path resolution into helper functions | Maintainers | S | Open |
| 10 | QF-072 | Low | 16 | Readability | renderPrompt 86 lines | core.zig | L263-348: prompt rendering with buffer overflow handling, cursor positioning, ANSI escape sequences | -- | Extract cursor positioning logic into render.zig helper | Maintainers | S | Open |
| 11 | QF-074 | Low | 16 | Readability | isBalanced 115 lines | parse.zig | L36-150: single function tracking 5 state variables (paren/bracket/brace depth, string modes, comment modes) | -- | Extract comment-skipping and string-skipping into helpers | Maintainers | S | Open |
| 12 | QF-077 | Low | 16 | Readability | handlePendingOperator 104 lines | keymap_vi.zig | L221-324: handles d/c/r operators with word/line motions | -- | Extract per-operator helpers (handleDeleteOperator, handleChangeOperator) | Maintainers | S | Open |
| 13 | QF-082 | Low | 16 | Correctness | search.zig ignores multi-byte key sequences | search.zig | L27: `var search_buf: [256]u8`; L30: processes byte-by-byte via `for (search_buf[0..n]) \|c\|`; multi-byte ESC sequences (e.g., arrow keys) not recognized, individual bytes fall through to printable/control handlers | -- | Add ESC sequence detection to skip multi-byte sequences instead of processing each byte independently | Maintainers | S | Open |
| 14 | QF-086 | Low | 16 | Duplication | getDefaultHistoryPath and getDefaultConfigPath structural duplication (~50 lines) | history.zig, config.zig | history.zig:276-326 and config.zig:195-239 share ~50 lines of structural duplication (env var check + isPathSafe + platform dispatch) | -- | `resolveEnvOverridePath` extracted to `src/text_utils.zig`; both `history.zig` and `config.zig` now call the shared helper | Maintainers | S | Resolved |
| 15 | QF-075 | Low | 12 | Readability | config.zig loadFromFile depth-6 nesting | config.zig | L121-138: `if (std.mem.eql(u8, key, "keymap") ...) { if (Keymap.fromString(value)) ... } else if ...` -- chain of 7 `else if` comparisons nested inside key/value parsing | -- | Extract config key dispatch to a lookup table or switch on hash | Maintainers | S | Open |
| 16 | QF-076 | Low | 12 | Readability | handleInsertMode 69 lines | keymap_vi.zig | L326-394: maps keys to actions in Vi insert mode | -- | Monitor; near the 50-line guideline but structurally simple (single switch) | Maintainers | S | Open |
| 17 | QF-078 | Low | 12 | Readability | processInput 77 lines | core.zig | L350-426: was 53 lines (QF-002); regrown to 77 lines due to undo snapshot integration | -- | Monitor; under 80 lines but trending upward | Maintainers | S | Open |
| 18 | QF-079 | Low | 12 | Readability | history.zig append 69 lines | history.zig | L126-194: handles dedup, max entries, file persistence with mutex | -- | Extract file persistence to a private helper | Maintainers | S | Open |
| 19 | QF-084 | Low | 12 | Documentation | 6 public functions missing `///` doc comments | completion.zig, config.zig, core.zig | completion.zig:32 (init), completion.zig:39 (deinit), completion.zig:116 (generate), config.zig:59 (Keymap.fromString), config.zig:77 (Format.fromString), core.zig:248 (ReplState.deinit) | -- | `///` doc comments added to all 6 public functions in `src/completion.zig`, `src/config.zig`, `src/core.zig` | Maintainers | S | Resolved |
| 20 | QF-087 | Low | 12 | Correctness | handleSearch does not reset state.history_index on exit | search.zig | search.zig:34-36 (ESC), 39-43 (Enter, Ctrl+C): exits search without resetting `state.history_index`; Up/Down history navigation starts from stale position. Cross-ref QF-067 (zero tests) | -- | Split ESC from Enter/newline: ESC and Ctrl+C now reset `state.history_index = null`; Enter preserves found position. 6 unit tests added for `replaceNewlinesForDisplay`. | Maintainers | S | Resolved |
| 21 | QF-080 | Low | 12 | Consistency | Vi 'O' `catch {}` inconsistent with QF-061 fix | keymap_vi.zig | L131: `state.buffer.insert(state.allocator, 0, '\n') catch {};` -- QF-061 changed Vi `o` from `catch {}` to `catch return .vi_insert_mode`; `O` was not updated to match | -- | Changed `catch {}` to `catch return .vi_insert_mode` at keymap_vi.zig:131 for consistency with `o` handler | Maintainers | S | Resolved |
| 3 | QF-053 | High | 60 | ErrorHandling | flushPasteBuffer `catch {}` on insertSlice silently loses paste + cursor invariant violated | core.zig | L470: `insertSlice(...) catch {}`; L471: `cursor += sanitized.len` runs regardless of insert success | [#93](https://gitlab.com/devnw/zig/repl/-/issues/93) | Changed `catch {}` to `catch return` so cursor advancement is guarded on insertSlice success | Maintainers | S | Resolved |
| 4 | QF-052 | Medium | 48 | Correctness | handleSearch reads 256 bytes but processes only search_buf[0], discarding bytes 1..n | core.zig | L802-808: `const n = try stdin.read(&search_buf)` then `const c = search_buf[0]`; bytes 1..n lost | [#92](https://gitlab.com/devnw/zig/repl/-/issues/92) | Wrapped character processing in `for (search_buf[0..n])` loop; all bytes now processed | Maintainers | S | Resolved |
| 7 | QF-051 | Medium | 36 | Readability | processAction 231 lines; .complete (47 LOC, depth 6) and .reverse_tab (27 LOC, depth 6) | core.zig | L563-793: `awk '/^fn processAction/,/^}/' | wc -l` = 231; .complete L721-766; .reverse_tab L583-608 | [#91](https://gitlab.com/devnw/zig/repl/-/issues/91) | Extracted handleCompletion() and handleUnindent(); processAction now 159 lines (target was <180) | Maintainers | S | Resolved |
| 8 | QF-054 | Low | 28 | Build | apt-get runs redundantly in all 7 CI jobs referencing install-zig anchor | .gitlab-ci.yml | L49: `apt-get update && apt-get install -y curl xz-utils` outside cache guard; 7 refs at L83,90,99,110,121,132,143 | [#94](https://gitlab.com/devnw/zig/repl/-/issues/94) | Moved apt-get inside cache guard with `command -v` check; runs only when Zig not cached and tools missing | Maintainers | S | Resolved |
| -- | QF-004 | Medium | 45 | Readability | handleNormalMode reduced to 158 lines | keymap_vi.zig | Extracted `handlePendingOperator` (d/c/r operators); handleNormalMode reduced from 257 to 158 lines | [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Extracted `handlePendingOperator` function; handleNormalMode now 158 lines (target was <200) | Maintainers | M | Resolved |
| -- | QF-048 | Medium | 40 | Build | CI downloads Zig tarball 7x per pipeline, no cache | .gitlab-ci.yml | 7 `*install-zig` refs (lines 79,86,95,106,117,128,139); no `cache:` block; ~315 MB/pipeline | [#84](https://gitlab.com/devnw/zig/repl/-/issues/84) | Add `cache:` block with `key: zig-${ZIG_VERSION}` and `paths: [zig-${ZIG_VERSION}/]` | Maintainers | S | Resolved |
| -- | QF-046 | Medium | 36 | Testing | render.zig zero test blocks for 2 pure functions | render.zig | 92 lines, 0 test blocks; `calculateVisualLines` (L18), `calculateCursorPosition` (L48) | [#80](https://gitlab.com/devnw/zig/repl/-/issues/80) | Add 8+ tests covering wrap boundaries, tabs, newlines, term_width=0 | Maintainers | S | Resolved |
| -- | QF-047 | Medium | 36 | Testing | input.zig 1 test covering 2 of ~12 code paths | input.zig | 128 lines, 1 test block (L119); covers ASCII 'a' + ESC[A only; ~10 branches untested | [#81](https://gitlab.com/devnw/zig/repl/-/issues/81) | Add 10+ tests covering all branch families (ESC[n~, ESC[1;nX, ESCO, Alt, Ctrl, bare ESC) | Maintainers | S | Resolved |
| -- | QF-049 | Low | 24 | Build | Makefile/pre-commit omit examples/ from fmt targets | Makefile, .pre-commit-config.yaml | `Makefile:12-15` runs `zig fmt src/ tests/ build.zig`; `.pre-commit-config.yaml:107` same; `examples/` has 8 .zig files (2043 lines) not covered | -- | Add `examples/` to fmt/check args in both Makefile and pre-commit | Maintainers | S | Resolved |
| -- | QF-042 | Low | 20 | Readability | platform.zig 812 lines (12 over 800 limit) | platform.zig | `wc -l src/platform.zig` = 812; last 18 lines (L795-812) are test blocks | -- | Merged 2 constant-accessor tests + trimmed redundant test comments; now 796 lines | Maintainers | S | Resolved |
| -- | QF-044 | Low | 16 | Readability | renderPrompt bare `[8192]u8` magic number | core.zig | L257: `var render_buf: [8192]u8 = undefined;` -- no named constant | -- | Extract to `const RENDER_BUF_SIZE = 8192;` (cf. platform.zig WRITE_BUF_SIZE pattern) | Maintainers | S | Resolved |
| -- | QF-045 | Low | 16 | Readability | paste_buf bare `[4096]u8` magic number | core.zig | L321: `var paste_buf: [4096]u8 = undefined;` and L379 parameter type -- no named constant | -- | Extract to `const PASTE_BUF_SIZE = 4096;` (cf. platform.zig PRINT_BUF_SIZE pattern) | Maintainers | S | Resolved |
| -- | QF-043 | Low | 16 | Duplication | Vi 'e' motion shared via findEndOfWord helper | keymap_vi.zig | Extracted `findEndOfWord` helper; both `de` operator and `e` motion now call it; 10 tests added | -- | Extracted shared `findEndOfWord(buf, cursor)` helper with 10 dedicated tests | Maintainers | S | Resolved |

### Won't Do

| QF-ID | Severity | Score | Category | Finding | Reason |
|-------|----------|-------|----------|---------|--------|
| QF-034 | Medium | 65 | Duplication | Vi insert Ctrl-key dispatch duplicated from Emacs | Won't Do -- Vi handler has state mutation (mode transitions, pending operators) that Emacs lacks. Coupling the two would add complexity without reducing risk. The duplication is intentional to allow independent evolution. |
| QF-018 | Medium | 45 | DeadCode | Config.saveToFile/loadFromFile never called internally | Won't Do -- Intentional consumer-facing API; documented in config.zig module doc comments (lines 16-30) and Config vs Options design notes. Not dead code. |
| QF-019 | Low | 25 | DeadCode | Format enum never used at runtime | Won't Do -- Intentional consumer-facing API; documented in config.zig doc comments (line 67-70). Format is part of the public Config struct, persisted/parsed by saveToFile/loadFromFile. |
| QF-014 | Medium | 45 | ErrorHandling | Vi kill ring `catch {}` on alloc | Won't Do -- The `catch {}` is intentional and documented. If alloc fails, the delete operation still succeeds (text is removed); only the kill ring storage fails. Propagating the error would make delete unreliable. |

### Resolved Findings

| Rank | QF-ID | Severity | Score | Category | Finding | Component | Issue | Resolution | Status |
|------|-------|----------|-------|----------|---------|-----------|-------|------------|--------|
| -- | QF-069 | Low | 20 | Readability | 9 unreachable `catch {}` on shrinking replaceRange | core.zig, keymap_vi.zig | -- | All 9 `catch {}` changed to `catch unreachable` with safety comment | Resolved |
| -- | QF-080 | Low | 12 | Consistency | Vi 'O' `catch {}` inconsistent with QF-061 fix | keymap_vi.zig | -- | Changed `catch {}` to `catch return .vi_insert_mode` at keymap_vi.zig:131 | Resolved |
| -- | QF-066 | High | 60 | Testing | processAction delete_char_forward untested | core.zig | -- | Added dedicated test for delete_char_forward action; verifies character removal at cursor and cursor stability | Resolved |
| -- | QF-065 | Low | 20 | APIContract | repl.zig missing isStderrTty re-export | repl.zig | -- | Added `pub const isStderrTty = platform.isStderrTty;` re-export to repl.zig public API | Resolved |
| -- | QF-064 | Low | 8 | Cleanup | Unused `builtin` import in core.zig | core.zig | -- | Deleted unused `const builtin = @import("builtin")` at line 13 | Resolved |
| -- | QF-058 | High | 60 | ErrorHandling | handleCompletion insertSlice catch {} advances cursor on OOM | core.zig | [#110](https://gitlab.com/devnw/zig/repl/-/issues/110) | Changed `catch {}` to `catch return` at core.zig:834 | Resolved |
| -- | QF-059 | Medium | 48 | Correctness | delete_word (Alt+D) missing kill ring save | core.zig | [#111](https://gitlab.com/devnw/zig/repl/-/issues/111) | Added kill ring save to .delete_word handler | Resolved |
| -- | QF-060 | Low | 24 | Consistency | Inconsistent try vs catch {} for kill_ring.appendSlice | core.zig | -- | Changed try to catch {} for consistency | Resolved |
| -- | QF-061 | Low | 20 | ErrorHandling | Vi `o` cursor advance after append catch {} | keymap_vi.zig | -- | Changed `catch {}` to `catch return .vi_insert_mode` | Resolved |
| -- | QF-062 | Low | 16 | ErrorHandling | allocator.dupe catch "" loses prefix on OOM | core.zig | -- | Changed `catch ""` to `catch return` | Resolved |
| -- | QF-063 | Low | 8 | Cleanup | Unused import history_mod in search.zig | search.zig | -- | Deleted unused import line | Resolved |
| -- | QF-011 | Critical | 95 | ErrorHandling | file.read() partial read bug | history.zig | [#43](https://gitlab.com/devnw/zig/repl/-/issues/43) | Replaced with readAll | Resolved |
| -- | QF-020 | Critical | 95 | APIContract | README wrong API signatures | README.md | [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | README rewritten to match actual API | Resolved |
| -- | QF-028 | Critical | 95 | Documentation | README Quick Start won't compile | README.md | [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | Quick Start aligned with run_fn pattern | Resolved |
| -- | QF-010 | Critical | 90 | ErrorHandling | TerminalWriter.print silently discards >4096 | platform.zig | [#48](https://gitlab.com/devnw/zig/repl/-/issues/48) | Partial write on overflow | Resolved |
| -- | QF-029 | Critical | 90 | Documentation | README config table wrong | README.md | [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | Table rebuilt from Repl.Options struct | Resolved |
| -- | QF-032 | Critical | 90 | Reliability | Signal handler infrastructure is dead code | platform.zig | [#45](https://gitlab.com/devnw/zig/repl/-/issues/45) | enterRawMode() now sets saved_termios and calls installTerminalSignalHandlers(); restoreTerminalMode() removes handlers. Evidence: `src/platform.zig:193-194`, `src/platform.zig:219-220` | Resolved |
| -- | QF-021 | High | 75 | APIContract | repl.zig doc comment wrong API | repl.zig | [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | Doc comments updated | Resolved |
| -- | QF-007 | High | 75 | Duplication | findWordStart duplicated 3x | core.zig | [#54](https://gitlab.com/devnw/zig/repl/-/issues/54) | Extracted to text_utils.zig | Resolved |
| -- | QF-002 | High | 70 | Readability | processInput 216 lines (worsened from 181) | core.zig | [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Refactored from 215 to 53 lines. Extracted: resetLineState, consumeBracketedPaste, appendToMultiLine, handleCommandSubmission, handleCancellation. Key parsing to input.zig, rendering to render.zig. | Resolved |
| -- | QF-033 | High | 70 | Duplication | isPathSafe duplicated verbatim 29 lines | history.zig, config.zig | -- | Extracted to `src/text_utils.zig`. Both history.zig and config.zig now import from shared module. 29 duplicate lines removed from each. | Resolved |
| -- | QF-022 | High | 70 | APIContract | KeyAction docs wrong | README.md | [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | Clarified as internal; callback returns bool | Resolved |
| -- | QF-008 | High | 70 | Duplication | findWordEnd duplicated 2x | core.zig | [#54](https://gitlab.com/devnw/zig/repl/-/issues/54) | Extracted to text_utils.zig | Resolved |
| -- | QF-030 | High | 70 | Documentation | No "why" on undo being kill-ring-replace | core.zig | [#50](https://gitlab.com/devnw/zig/repl/-/issues/50) | Doc comment with issue link added | Resolved |
| -- | QF-009 | Medium | 70 | Duplication | Format enum still duplicated | core.zig, config.zig | [#54](https://gitlab.com/devnw/zig/repl/-/issues/54) | Already unified: core.zig re-exports Format from config.zig. Not a real duplication. | Resolved |
| -- | QF-024 | Medium | 65 | Reliability | No signal handlers for terminal cleanup | core.zig | -- | Resolved via QF-032/GAP-0021 fix. Signal handlers now installed in enterRawMode() and removed in restoreTerminalMode(). Evidence: `src/platform.zig:193-194`, `src/platform.zig:219-220` | Resolved |
| -- | QF-012 | Medium | 65 | ErrorHandling | renderPrompt error swallowed | core.zig | -- | BrokenPipe detection added | Resolved |
| -- | QF-035 | Medium | 60 | Consistency | Vi dw/db/de use orderedRemove loops | keymap_vi.zig | -- | Replaced orderedRemove loops with single `replaceRange` calls at `src/keymap_vi.zig:91,103,121` | Resolved |
| -- | QF-005 | Medium | 60 | Readability | Magic 4096 in print buffer | platform.zig | [#48](https://gitlab.com/devnw/zig/repl/-/issues/48) | Extracted to PRINT_BUF_SIZE constant | Resolved |
| -- | QF-001 | Medium | 55 | Readability | core.zig 1114 lines (worsened from 969) | core.zig | [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Reduced from 1114 to 801 non-test lines (1004 total) by extracting input.zig, render.zig, text_utils.zig, search.zig, plus handleCompletion/handleUnindent helpers. At 800-line guideline boundary. | Resolved |
| -- | QF-025 | Medium | 60 | Testing | Keymap tests are no-ops | keymap_emacs.zig, keymap_vi.zig | [#52](https://gitlab.com/devnw/zig/repl/-/issues/52) | Behavioral tests added | Resolved |
| -- | QF-036 | Medium | 50 | Build | Pre-commit zig-fmt covers only src/ and build.zig | .pre-commit-config.yaml | -- | Added `tests/` directory to pre-commit zig-fmt hook args | Resolved |
| -- | QF-003 | Medium | 50 | Readability | processAction 228-line switch | core.zig | [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Resolved as part of GAP-0024 refactoring. processAction reduced alongside processInput extraction. | Resolved |
| -- | QF-023 | Medium | 50 | APIContract | Config not integrated with Options | config.zig | -- | Documented as intentional design | Resolved |
| -- | QF-037 | Low | 45 | Build | Makefile fmt/check targets reference nonexistent lib/ | Makefile | -- | Removed `lib/` references and `2>/dev/null` error suppression from Makefile | Resolved |
| -- | QF-013 | Medium | 40 | ErrorHandling | History append failure silently discarded | core.zig | -- | Verbose warning added | Resolved |
| -- | QF-038 | Low | 40 | DeadCode | CompletionProvider and keywordProvider have zero callers | completion.zig | -- | Documented as consumer-facing API with doc comments explaining intended usage | Resolved |
| -- | QF-017 | Medium | 40 | DeadCode | StatementChecker never used | parse.zig | -- | Dead code removed | Resolved |
| -- | QF-039 | Low | 35 | DeadCode | parse.trimTrailing and hasBackslashContinuation dead | parse.zig | -- | Documented as consumer-facing API with doc comments explaining intended usage | Resolved |
| -- | QF-031 | Low | 35 | Documentation | Config lacks integration docs | config.zig | -- | Module doc comment added | Resolved |
| -- | QF-040 | Low | 30 | Duplication | TestState struct duplicated between keymaps | keymap_emacs.zig, keymap_vi.zig | -- | Documented as intentional: Vi and Emacs TestState have different field requirements (Vi has mode, pending_operator; Emacs does not). Coupling would add complexity. | Resolved |
| -- | QF-027 | Low | 25 | Reliability | handleSearch 1024-byte buffer | core.zig | -- | Expanded to 4096 with graceful truncation | Resolved |
| -- | QF-041 | Low | 25 | APIContract | config.saveToFile accepts unused allocator | config.zig | -- | Doc comment added to `saveToFile` explaining allocator is reserved for future use (dynamic serialization buffer) | Resolved |
| -- | QF-048 | Medium | 40 | Build | CI downloads Zig tarball 7x per pipeline, no cache | .gitlab-ci.yml | [#84](https://gitlab.com/devnw/zig/repl/-/issues/84) | Global `cache:` block added with `key: zig-${ZIG_VERSION}` and `paths: [zig-${ZIG_VERSION}/]`; existing download guard skips when cached | Resolved |
| -- | QF-042 | Low | 20 | Readability | platform.zig 812 lines (12 over 800 limit) | platform.zig | -- | Merged 2 constant-accessor tests into 1 + removed 8 redundant test comments; 812 -> 796 lines | Resolved |
| -- | QF-006 | Low | 20 | Readability | Magic tab_stop=8 | core.zig | -- | Named constant TAB_STOP added | Resolved |
| -- | QF-016 | Low | 15 | ErrorHandling | catch unreachable on initCapacity(0) | core.zig | -- | Safety comments added | Resolved |

---

## Findings by Category

### Reliability (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-032 | 90 | Critical | Signal handler infrastructure is dead code | Resolved |
| QF-026 | 85 | High | Core loop test coverage -- processAction: 27 tests; processInput: needs mock harness | Partial |
| QF-024 | 65 | Medium | No signal handlers for terminal cleanup (resolved via QF-032) | Resolved |

### Readability / Complexity (11 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-002 | 70 | High | processInput 216 lines -> 53 lines | Resolved |
| QF-001 | 55 | Medium | core.zig 1114 lines -> 801 lines | Resolved |
| QF-050 | 40 | Medium | core.zig at ~878 non-test lines -- growth justified by undo integration, documented in ARCHITECTURE.md | Accepted |
| QF-003 | 50 | Medium | processAction 228-line switch | Resolved |
| QF-051 | 36 | Medium | processAction 231 lines -> 159 lines; handleCompletion/handleUnindent extracted | Resolved |
| QF-004 | 45 | Medium | handleNormalMode 257 lines -> 158 lines (extracted handlePendingOperator) | Resolved |
| QF-057 | 24 | Low | Magic values for synthetic key codes -- SyntheticKey constants defined in input.zig | Resolved |
| QF-069 | 20 | Low | 9 unreachable `catch {}` changed to `catch unreachable` on shrinking replaceRange across core.zig and keymap_vi.zig | Resolved |
| QF-073 | 20 | Low | parseKeyEvent depth-7 nesting in input.zig:40-105 | Open |
| QF-083 | 20 | Low | platform.zig regressed to 908 lines (was 796 after QF-042) | Open |
| QF-070 | 16 | Low | processAction regrown to 169 lines (core.zig:597-765) | Open |
| QF-071 | 16 | Low | generateFilePathCandidates 87 lines (completion.zig:191-277) | Open |
| QF-072 | 16 | Low | renderPrompt 86 lines (core.zig:263-348) | Open |
| QF-074 | 16 | Low | isBalanced 115 lines (parse.zig:36-150) | Open |
| QF-077 | 16 | Low | handlePendingOperator 104 lines (keymap_vi.zig:221-324) | Open |
| QF-042 | 20 | Low | platform.zig 812 lines -> 796 lines (under 800 guideline) | Resolved |
| QF-075 | 12 | Low | config.zig loadFromFile depth-6 nesting (L121-138) | Open |
| QF-076 | 12 | Low | handleInsertMode 69 lines (keymap_vi.zig:326-394) | Open |
| QF-078 | 12 | Low | processInput regrown to 77 lines (core.zig:350-426) | Open |
| QF-079 | 12 | Low | history.zig append 69 lines (L126-194) | Open |
| QF-044 | 16 | Low | renderPrompt bare `[8192]u8` magic number | Resolved |
| QF-045 | 16 | Low | paste_buf bare `[4096]u8` magic number | Resolved |

### Duplication (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-086 | 16 | Low | getDefaultHistoryPath and getDefaultConfigPath structural duplication (~50 lines) in history.zig and config.zig -- `resolveEnvOverridePath` extracted to text_utils.zig | Resolved |
| QF-033 | 70 | High | isPathSafe extracted to text_utils.zig | Resolved |
| QF-009 | 70 | Medium | Format enum unified (core.zig re-exports from config.zig) | Resolved |
| QF-034 | 65 | Medium | Vi insert Ctrl-key dispatch duplicated from Emacs | Won't Do |
| QF-040 | 30 | Low | TestState struct duplication documented as intentional | Resolved |
| QF-043 | 16 | Low | Vi 'e' motion shared via findEndOfWord helper | Resolved |

### Testing (1 open finding)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-067 | 60 | High | search.zig zero test coverage (73 lines, 0 tests) -- [#119](https://gitlab.com/devnw/zig/repl/-/issues/119) | Open |
| QF-085 | 20 | Low | config.zig: 6 new tests added for loadFromFile, saveToFile, round-trip, getDefaultConfigPath | Resolved |
| QF-066 | 60 | High | processAction delete_char_forward untested -- dedicated test added | Resolved |
| QF-026 | 85 | High | Core loop test coverage -- processAction: 27 tests; processInput: needs mock harness | Partial |
| QF-056 | 36 | Medium | Integration tests for undo: 10 tests added covering full type->undo->verify flows | Resolved |
| QF-025 | 60 | Medium | Keymap tests are no-ops | Resolved |
| QF-048 | 40 | Medium | CI cache added: global `cache:` block with `key: zig-${ZIG_VERSION}` | Resolved |
| QF-046 | 36 | Medium | render.zig: 26 tests added covering tabWidth, calculateVisualLines, calculateCursorPosition | Resolved |
| QF-047 | 36 | Medium | input.zig: 46 tests added covering all branch families (regular, ctrl, arrows, ESC[n~, ESC[1;nX, ESCO, Alt, bare ESC, getKeyEventLength) | Resolved |

### ErrorHandling (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-015 | 80 | High | .undo replaces buffer with kill ring -- real undo stack implemented (GAP-0018) | Resolved |
| QF-058 | 60 | High | handleCompletion insertSlice catch {} advances cursor on OOM -- changed to catch return | Resolved |
| QF-053 | 60 | High | flushPasteBuffer `catch return` guards cursor on OOM | Resolved |
| QF-014 | 45 | Medium | Vi kill ring catch {} on alloc | Won't Do |
| QF-061 | 20 | Low | Vi `o` cursor advance after append catch {} -- changed to catch return | Resolved |
| QF-062 | 16 | Low | allocator.dupe catch "" loses prefix on OOM -- changed to catch return | Resolved |
| QF-055 | 8 | Low | UndoStack.push memory leak on append failure -- errdefer added | Resolved |

### Correctness (1 open finding)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-059 | 48 | Medium | delete_word (Alt+D) missing kill ring save -- kill ring save added | Resolved |
| QF-052 | 48 | Medium | handleSearch now processes all bytes from stdin.read via `for (search_buf[0..n])` loop | Resolved |
| QF-082 | 16 | Low | search.zig ignores multi-byte key sequences (arrow keys processed as individual bytes) | Open |
| QF-087 | 12 | Low | handleSearch ESC and Ctrl+C now reset `state.history_index = null`; Enter preserves found position | Resolved |

### Consistency (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-060 | 24 | Low | Inconsistent try vs catch {} for kill_ring.appendSlice -- changed to catch {} for consistency | Resolved |
| QF-035 | 60 | Medium | Vi dw/db/de orderedRemove replaced with replaceRange | Resolved |
| QF-080 | 12 | Low | Vi 'O' `catch {}` changed to `catch return .vi_insert_mode` for consistency with QF-061 fix for 'o' (keymap_vi.zig:131) | Resolved |

### Build / CI (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-048 | 40 | Medium | CI downloads Zig tarball 7x per pipeline, no cache | Resolved |
| QF-054 | 28 | Low | apt-get moved inside cache guard with command -v check | Resolved |
| QF-036 | 50 | Medium | Pre-commit zig-fmt now includes tests/ directory | Resolved |
| QF-049 | 24 | Low | Makefile/pre-commit omit examples/ from fmt targets | Resolved |
| QF-037 | 45 | Low | Makefile lib/ references and error suppression removed | Resolved |

### Cleanup (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-063 | 8 | Low | Unused import `history_mod` in search.zig -- deleted | Resolved |
| QF-064 | 8 | Low | Unused `builtin` import in core.zig -- deleted | Resolved |

### Dead Code (2 won't-do findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-018 | 45 | Medium | Config.saveToFile/loadFromFile -- intentional consumer API | Won't Do |
| QF-038 | 40 | Low | CompletionProvider and keywordProvider -- documented as consumer API | Resolved |
| QF-019 | 25 | Low | Format enum -- intentional consumer API | Won't Do |
| QF-039 | 35 | Low | parse.trimTrailing and hasBackslashContinuation -- documented as consumer API | Resolved |

### API Contract (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-065 | 20 | Low | repl.zig missing isStderrTty re-export -- added pub const re-export | Resolved |
| QF-041 | 25 | Low | config.saveToFile allocator documented as reserved for future use | Resolved |

### Documentation (0 open findings)

| QF-ID | Score | Severity | Summary | Status |
|-------|-------|----------|---------|--------|
| QF-084 | 12 | Low | 6 public functions now have `///` doc comments in completion.zig, config.zig, core.zig | Resolved |

---

## Roadmap

### Quick Wins (< 1 day)

| QF-ID | Score | Fix | Issue | Status |
|-------|-------|-----|-------|--------|
| QF-067 | 60 | Add 8+ test blocks to search.zig covering all 7 code paths | [#119](https://gitlab.com/devnw/zig/repl/-/issues/119) | Open |
| QF-069 | 20 | All 9 `catch {}` changed to `catch unreachable` + safety comment on shrinking replaceRange | -- | Resolved |
| QF-073 | 20 | Refactor parseKeyEvent to early-return pattern to reduce nesting | -- | Open |
| QF-083 | 20 | Extract helpers from platform.zig to reduce below 800 lines | -- | Open |
| QF-085 | 20 | 6 new tests added: loadFromFile, saveToFile, round-trip, getDefaultConfigPath in config.zig | -- | Resolved |
| QF-070 | 16 | Monitor processAction; extract if >180 lines | -- | Open |
| QF-071 | 16 | Extract tilde expansion from generateFilePathCandidates | -- | Open |
| QF-072 | 16 | Extract cursor positioning from renderPrompt into render.zig | -- | Open |
| QF-074 | 16 | Extract comment/string skipping from isBalanced | -- | Open |
| QF-077 | 16 | Extract per-operator helpers from handlePendingOperator | -- | Open |
| QF-082 | 16 | Add ESC sequence detection to search.zig byte loop | -- | Open |
| QF-086 | 16 | `resolveEnvOverridePath` extracted to text_utils.zig; both history.zig and config.zig deduplicated | -- | Resolved |
| QF-075 | 12 | Simplify loadFromFile key dispatch (lookup table or hash) | -- | Open |
| QF-076 | 12 | Monitor handleInsertMode; near 50-line guideline but structurally simple | -- | Open |
| QF-078 | 12 | Monitor processInput; under 80 lines but trending upward | -- | Open |
| QF-079 | 12 | Extract file persistence from history.zig append | -- | Open |
| QF-084 | 12 | `///` doc comments added to 6 public functions in completion.zig, config.zig, core.zig | -- | Resolved |
| QF-087 | 12 | Split ESC from Enter/newline; ESC and Ctrl+C reset `history_index = null`; Enter preserves position. 6 tests added for display helper. | -- | Resolved |
| QF-080 | 12 | Changed Vi 'O' `catch {}` to `catch return .vi_insert_mode` for consistency | -- | Resolved |
| QF-058 | 60 | Changed `catch {}` to `catch return` on insertSlice in handleCompletion (1 line) | [#110](https://gitlab.com/devnw/zig/repl/-/issues/110) | Resolved |
| QF-059 | 48 | Added kill_ring save + last_was_kill flag to .delete_word handler (4 lines) | [#111](https://gitlab.com/devnw/zig/repl/-/issues/111) | Resolved |
| QF-050 | 40 | Growth justified by undo integration; documented in ARCHITECTURE.md size note | [#90](https://gitlab.com/devnw/zig/repl/-/issues/90) | Accepted |
| QF-060 | 24 | Changed L651,657 from `try` to `catch {}` for kill_ring.appendSlice consistency | -- | Resolved |
| QF-061 | 20 | Changed Vi `o` append `catch {}` to `catch return .vi_insert_mode` (1 line) | -- | Resolved |
| QF-062 | 16 | Changed allocator.dupe `catch ""` to `catch return` in completion prefix (1 line) | -- | Resolved |
| QF-063 | 8 | Deleted unused `const history_mod = @import("history.zig")` in search.zig | -- | Resolved |
| QF-053 | 60 | Changed `catch {}` to `catch return`; cursor guarded on insertSlice success | [#93](https://gitlab.com/devnw/zig/repl/-/issues/93) | Resolved |
| QF-052 | 48 | Wrapped search byte processing in `for (search_buf[0..n])` loop | [#92](https://gitlab.com/devnw/zig/repl/-/issues/92) | Resolved |
| QF-050 | 40 | Previously resolved at 801 lines; regressed to ~878 due to undo integration; accepted with ARCHITECTURE.md documentation | [#90](https://gitlab.com/devnw/zig/repl/-/issues/90) | Accepted |
| QF-051 | 36 | Extracted handleCompletion() and handleUnindent(); processAction 159 lines | [#91](https://gitlab.com/devnw/zig/repl/-/issues/91) | Resolved |
| QF-054 | 28 | Moved apt-get inside cache guard with `command -v` check | [#94](https://gitlab.com/devnw/zig/repl/-/issues/94) | Resolved |
| QF-048 | 40 | Add `cache:` block to `.gitlab-ci.yml` for Zig installation directory | [#84](https://gitlab.com/devnw/zig/repl/-/issues/84) | Resolved |
| QF-046 | 36 | Add 8+ test blocks to render.zig for pure functions | [#80](https://gitlab.com/devnw/zig/repl/-/issues/80) | Resolved |
| QF-047 | 36 | Add 10+ test blocks to input.zig covering all branch families | [#81](https://gitlab.com/devnw/zig/repl/-/issues/81) | Resolved |
| QF-049 | 24 | Add `examples/` to Makefile fmt/check and pre-commit zig-fmt args | -- | Resolved |
| QF-042 | 20 | Merged constant tests + trimmed redundant comments; 812 -> 796 lines | -- | Resolved |
| QF-044 | 16 | Extract `const RENDER_BUF_SIZE = 8192` in core.zig | -- | Resolved |
| QF-045 | 16 | Extract `const PASTE_BUF_SIZE = 4096` in core.zig | -- | Resolved |
| QF-057 | 24 | Defined `SyntheticKey` constants in input.zig (insert=0x02, delete=0x04, page_up=0x05, page_down=0x06); keymaps import named constants | [#106](https://gitlab.com/devnw/zig/repl/-/issues/106) | Resolved |
| QF-043 | 16 | Extracted shared `findEndOfWord` helper; both `de` and `e` use it | -- | Resolved |
| QF-055 | 8 | Added `errdefer self.allocator.free(buf_copy)` after dupe in push() | [#104](https://gitlab.com/devnw/zig/repl/-/issues/104) | Resolved |

### Medium (1-5 days)

| QF-ID | Score | Fix | Issue | Status |
|-------|-------|-----|-------|--------|
| QF-056 | 36 | Added 10 integration tests for undo: basic, after delete/paste, stack exhaustion, cursor restore, multiline, sequential, word deletion, kill ring | [#105](https://gitlab.com/devnw/zig/repl/-/issues/105) | Resolved |
| QF-004 | 45 | Extracted `handlePendingOperator`; handleNormalMode 257 -> 158 lines | [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Resolved |

### Strategic (> 5 days)

| QF-ID | Score | Fix | Issue | Status |
|-------|-------|-----|-------|--------|
| QF-026 | 85 | Phase 1 done (27 processAction tests). Phase 2: mock harness for processInput | [#52](https://gitlab.com/devnw/zig/repl/-/issues/52) | Partial |
| QF-015 | 80 | Real undo stack in src/undo.zig; integrated into core.zig (GAP-0018) | [#5](https://gitlab.com/devnw/zig/repl/-/issues/5) | Resolved |

### Won't Do (intentional consumer APIs)

| QF-ID | Score | Fix | Issue | Status |
|-------|-------|-----|-------|--------|
| QF-018 | 45 | Intentional consumer-facing API; documented in config.zig | -- | Won't Do |
| QF-019 | 25 | Intentional consumer-facing API; documented in config.zig | -- | Won't Do |

---

## Issue Cross-Reference

| Issue | Title | Quality Findings |
|-------|-------|-----------------|
| [#43](https://gitlab.com/devnw/zig/repl/-/issues/43) | Bug: history.zig file.read() partial read | QF-011 (Resolved) |
| [#46](https://gitlab.com/devnw/zig/repl/-/issues/46) | Bug: README and doc comments wrong API | QF-020, QF-028, QF-029, QF-021, QF-022 (all Resolved) |
| [#48](https://gitlab.com/devnw/zig/repl/-/issues/48) | Bug: TerminalWriter.print silently discards >4096 bytes | QF-010, QF-005 (both Resolved) |
| [#50](https://gitlab.com/devnw/zig/repl/-/issues/50) | Bug: .undo replaces buffer with kill ring | QF-015 (Resolved), QF-030 (Resolved) |
| [#52](https://gitlab.com/devnw/zig/repl/-/issues/52) | Zero test coverage for core REPL loop | QF-026 (Partial), QF-025 (Resolved) |
| [#54](https://gitlab.com/devnw/zig/repl/-/issues/54) | Refactor: deduplicate findWordStart/End and enums | QF-007, QF-008, QF-009 (all Resolved) |
| [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) | Refactor: processInput complexity | QF-002, QF-003, QF-001 (Resolved), QF-004 (Resolved) |
| [#80](https://gitlab.com/devnw/zig/repl/-/issues/80) | Testing: render.zig zero test blocks for 2 pure functions | QF-046 (Resolved) |
| [#81](https://gitlab.com/devnw/zig/repl/-/issues/81) | Testing: input.zig 1 test covering 2 of ~12 code paths | QF-047 (Resolved) |
| [#84](https://gitlab.com/devnw/zig/repl/-/issues/84) | Build: CI downloads Zig tarball 7x per pipeline, no cache | QF-048 (Resolved) |
| [#90](https://gitlab.com/devnw/zig/repl/-/issues/90) | Quality: core.zig regressed to ~850 non-test lines | QF-050 (Accepted, issue closed) |
| [#91](https://gitlab.com/devnw/zig/repl/-/issues/91) | Quality: processAction 231 lines -- extract handleCompletion and handleUnindent | QF-051 (Resolved, issue closed) |
| [#92](https://gitlab.com/devnw/zig/repl/-/issues/92) | Bug: handleSearch reads 256 bytes but processes only first byte | QF-052 (Resolved, issue closed) |
| [#93](https://gitlab.com/devnw/zig/repl/-/issues/93) | Bug: flushPasteBuffer silently loses pasted content on OOM | QF-053 (Resolved, issue closed) |
| [#94](https://gitlab.com/devnw/zig/repl/-/issues/94) | Build: apt-get runs redundantly in all 7 CI jobs | QF-054 (Resolved, issue closed) |
| [#104](https://gitlab.com/devnw/zig/repl/-/issues/104) | QF-055: UndoStack.push memory leak on append failure | QF-055 (Resolved) |
| [#105](https://gitlab.com/devnw/zig/repl/-/issues/105) | QF-056: No integration tests for undo functionality | QF-056 (Resolved) |
| [#106](https://gitlab.com/devnw/zig/repl/-/issues/106) | QF-057: Magic values for synthetic key codes | QF-057 (Resolved) |
| [#110](https://gitlab.com/devnw/zig/repl/-/issues/110) | Bug: handleCompletion insertSlice catch {} advances cursor on OOM (QF-058) | QF-058 (Resolved, issue closed) |
| [#111](https://gitlab.com/devnw/zig/repl/-/issues/111) | Bug: delete_word (Alt+D) missing kill ring save (QF-059) | QF-059 (Resolved, issue closed) |
| [#119](https://gitlab.com/devnw/zig/repl/-/issues/119) | QF-067: search.zig zero test coverage (73 lines, 0 tests) | QF-067 (Open) |

### Pre-existing Related Issues

| Existing Issue | Related Findings |
|----------------|-----------------|
| [#1](https://gitlab.com/devnw/zig/repl/-/issues/1) Set up CI/CD pipeline | QF-048, QF-054 |
| [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) Add comprehensive unit tests | QF-026, QF-046, QF-047, QF-056 |
| [#4](https://gitlab.com/devnw/zig/repl/-/issues/4) Set up test coverage reporting | QF-026 |
| [#5](https://gitlab.com/devnw/zig/repl/-/issues/5) Implement full undo/redo stack | QF-015 (Resolved), QF-055 (Resolved), QF-056 (Resolved) |
| [#19](https://gitlab.com/devnw/zig/repl/-/issues/19) Improve signal handling | QF-024 (Resolved), QF-032 (Resolved) |
| [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) Write API documentation | QF-020, QF-021, QF-022 (all Resolved) |
| [#39](https://gitlab.com/devnw/zig/repl/-/issues/39) Config module disconnected | QF-023 (Resolved), QF-018 (Won't Do) |
| [#56](https://gitlab.com/devnw/zig/repl/-/issues/56) Refactor: processInput complexity | QF-002, QF-003, QF-001 (Resolved), QF-050 (Accepted), QF-051 (Resolved) |
| [#71](https://gitlab.com/devnw/zig/repl/-/issues/71) CI stale comment / build stages | QF-048, QF-054 |

---

## Trend Analysis

### Phase 4 -> Phase 5

| Metric | Phase 4 (2026-03-24) | Phase 5 (2026-03-24 post-closure) | Delta |
|--------|----------------------|-----------------------------------|-------|
| Total findings | 41 | 41 | 0 |
| Open findings | 21 | 5 (+1 partial, +2 won't-do) | -16 resolved |
| Resolved findings | 20 | 34 | +14 |
| Won't Do | 0 | 2 | +2 |
| Partial | 0 | 1 | +1 |
| Critical (open) | 1 | 0 | -1 |
| High (open) | 4 | 2 | -2 |
| Highest open score | 90 | 85 | -5 |
| core.zig size | 1114 lines | 799 lines | -315 (improved) |
| processInput size | 216 lines | 53 lines | -163 (improved) |

**Key observations:**
- 16 additional findings resolved in gap closure wave (14 closed + 2 won't-do).
- Critical findings reduced to 0 (QF-032 signal handlers resolved).
- core.zig reduced from 1114 to 799 lines (under 800-line guideline) via extraction of input.zig, render.zig, and text_utils.zig.
- processInput refactored from 216 to 53 lines (75% reduction).
- 2 findings marked Won't-Do with documented rationale (QF-034 Ctrl-key dispatch, QF-014 kill ring catch).
- Remaining open items are all deferred/strategic: test harness (QF-026), real undo (QF-015), and consumer API documentation (QF-018/019).

### Phase 5 -> Phase 6

| Metric | Phase 5 (2026-03-24 post-closure) | Phase 6 (2026-03-24 quality-reviewer) | Delta |
|--------|-----------------------------------|---------------------------------------|-------|
| Total findings | 41 | 49 | +8 new |
| Open findings | 5 (+1 partial, +2 won't-do) | 13 (+1 partial, +2 won't-do) | +8 new open |
| Resolved findings | 34 | 34 | 0 |
| Won't Do | 2 | 2 | 0 |
| Partial | 1 | 1 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 2 | 2 | 0 |
| Medium (open) | 2 | 5 | +3 |
| Low (open) | 1 | 6 | +5 |
| Highest open score | 85 | 85 | 0 |
| New issues created | -- | 3 (#80, #81, #84) | +3 |

### Phase 6 -> Phase 10 (Final Closure)

| Metric | Phase 6 (2026-03-24 quality-reviewer) | Phase 10 (2026-03-24 final) | Delta |
|--------|---------------------------------------|----------------------------|-------|
| Total findings | 49 | 49 | 0 |
| Open findings | 13 | 4 (deferred) | -9 resolved |
| Resolved findings | 34 | 43 | +9 |
| Won't Do | 2 | 2 | 0 |
| Deferred | -- | 4 | -- |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 2 | 2 (deferred) | 0 |
| Highest open score | 85 | 85 (QF-026, deferred) | 0 |

**Key observations:**
- 9 additional findings resolved in final closure wave (QF-004, QF-042..QF-049).
- All remaining open items are explicitly deferred with documented rationale.
- QF-004 (handleNormalMode 261 lines) resolved via handlePendingOperator extraction (158 lines).
- QF-046/QF-047 resolved: render.zig has 28 tests, input.zig has 48 tests.
- QF-048 resolved: CI Zig caching added.
- QF-049 resolved: examples/ added to fmt/check targets.
- No regressions. Codebase quality continues to improve.

### Phase 10 -> Phase 11 (Quality Reviewer Incremental)

| Metric | Phase 10 (2026-03-24 final) | Phase 11 (2026-03-24 quality-reviewer) | Delta |
|--------|----------------------------|----------------------------------------|-------|
| Total findings | 49 | 54 | +5 new |
| Open findings | 4 (deferred) | 9 (4 deferred + 5 new open) | +5 new open |
| Resolved findings | 43 | 43 | 0 |
| Won't Do | 2 | 2 | 0 |
| Deferred | 4 | 4 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 2 (deferred) | 3 (2 deferred + 1 new) | +1 |
| Medium (open) | 1 (deferred) | 4 (1 deferred + 3 new) | +3 |
| Low (open) | 1 (deferred) | 2 (1 deferred + 1 new) | +1 |
| Highest open score | 85 (QF-026, deferred) | 85 (QF-026, deferred) | 0 |
| New issues created | -- | 5 (#90, #91, #92, #93, #94) | +5 |
| core.zig non-test lines | ~799 (at QF-001 resolution) | ~850 | +51 (regression) |
| processAction lines | ~228 (QF-003 resolution) | 231 | +3 (stable) |

**Key observations:**
- 5 new findings from Phase 11 quality-reviewer pass.
- 1 High-severity finding (QF-053): flushPasteBuffer `catch {}` silently loses pasted content and violates cursor invariant. This is the highest-priority new item.
- 1 Medium correctness finding (QF-052): handleSearch discards bytes 1..n from multi-byte reads. Silent data loss during search.
- 2 Medium readability findings (QF-050, QF-051): core.zig regressed to ~850 non-test lines; processAction at 231 lines with depth-6 nesting.
- 1 Low build finding (QF-054): redundant apt-get in all 7 CI jobs.
- core.zig has regressed from 799 lines (QF-001 resolution) to ~850 non-test lines due to helper function additions in Phases 5-10.
- All 5 new findings are quick wins (< 1 day effort each).
- No new Critical findings. The codebase's critical issues remain fully resolved.
- QF-053 (Score 60) is the most urgent: it can cause cursor > buffer.len invariant violation on OOM during paste.

### Phase 11 -> Phase 12 (Close-Out)

| Metric | Phase 11 (2026-03-24 quality-reviewer) | Phase 12 (2026-03-24 close-out) | Delta |
|--------|----------------------------------------|---------------------------------|-------|
| Total findings | 54 | 54 | 0 |
| Open findings | 9 (4 deferred + 5 new open) | 4 (all deferred) | -5 resolved |
| Resolved findings | 43 | 48 | +5 |
| Won't Do | 2 | 2 | 0 |
| Deferred | 4 | 4 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 3 (2 deferred + 1 new) | 2 (deferred) | -1 resolved |
| Medium (open) | 4 (1 deferred + 3 new) | 1 (deferred) | -3 resolved |
| Low (open) | 2 (1 deferred + 1 new) | 1 (deferred) | -1 resolved |
| Highest open score | 85 (QF-026, deferred) | 85 (QF-026, deferred) | 0 |
| Issues closed | -- | 5 (#90, #91, #92, #93, #94) | +5 |
| core.zig non-test lines | ~850 | 801 | -49 (improved) |
| processAction lines | 231 | 159 | -72 (improved) |

**Key observations:**
- All 5 findings from Phase 11 (QF-050 through QF-054) resolved and GitLab issues closed.
- QF-053 (flushPasteBuffer catch return) -- highest priority fix -- cursor invariant violation eliminated.
- QF-052 (handleSearch multi-byte) -- silent data loss in search mode eliminated.
- QF-050/QF-051 (core.zig size/processAction) -- core.zig back to 801 non-test lines; processAction at 159 lines.
- QF-054 (apt-get guard) -- CI job overhead reduced.
- All remaining open items are deferred with documented rationale.
- Zero open findings. 48 resolved, 4 deferred, 2 won't-do.

### Phase 12 -> Phase 14 (Phase 3 Deep Review)

| Metric | Phase 12 (2026-03-24 close-out) | Phase 14 (2026-03-24 deep review) | Delta |
|--------|--------------------------------|-----------------------------------|-------|
| Total findings | 54 | 57 | +3 new |
| Open findings | 4 (all deferred) | 7 (3 deferred + 1 open medium + 2 open low) | +3 new open |
| Resolved findings | 48 | 49 | 0 |
| Won't Do | 2 | 2 | 0 |
| Deferred | 4 | 3 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 2 (deferred) | 1 (deferred) | 0 |
| Medium (open) | 1 (deferred) | 2 (1 deferred + 1 new) | +1 |
| Low (open) | 1 (deferred) | 3 (1 deferred + 2 new) | +2 |
| Highest open score | 85 (QF-026, deferred) | 85 (QF-026, deferred) | 0 |
| New issues created | -- | 3 (#104, #105, #106) | +3 |

**Key observations:**
- 3 new findings from Phase 3 deep review of undo stack and key handling.
- QF-055 (Score 8, Low): Memory leak on rare OOM path in UndoStack.push -- missing `errdefer` after `allocator.dupe()`. Quick fix, extremely rare trigger.
- QF-056 (Score 36, Medium): No integration tests for undo functionality. The Delete key collision (GAP-0045) would have been caught by such tests. Medium effort due to test harness dependency.
- QF-057 (Score 24, Low): Synthetic key codes (0x02, 0x05, 0x06, 0x7f) are magic numbers across 3 files. Named constants would improve readability and reduce sync risk. Quick fix.
- No new Critical or High findings. The codebase's critical/high-severity issues remain stable.
- QF-056 is related to the deferred QF-026 (core loop test coverage) but is scoped specifically to undo, which can be tested without full mock stdin/stdout infrastructure.

### Phase 15 -> Phase 16 (Quality Reviewer Incremental)

| Metric | Phase 15 (2026-03-24 close-out) | Phase 16 (2026-03-24 quality-reviewer) | Delta |
|--------|--------------------------------|----------------------------------------|-------|
| Total findings | 57 | 63 | +6 new |
| Open findings | 0 (3 deferred, 2 won't-do, 52 resolved) | 6 open + 1 regressed (3 deferred, 2 won't-do, 52 resolved) | +6 new open, +1 regressed |
| Resolved findings | 52 | 52 | 0 |
| Won't Do | 2 | 2 | 0 |
| Deferred | 3 | 3 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 0 (1 deferred) | 1 new (1 deferred) | +1 |
| Medium (open) | 0 (1 deferred) | 2 (1 new + 1 regressed; 1 deferred) | +2 |
| Low (open) | 0 (1 deferred) | 4 new (1 deferred) | +4 |
| Highest open score | 85 (QF-026, deferred) | 85 (QF-026, deferred) | 0 |
| New issues created | -- | 2 (#110, #111) | +2 |
| Issues reopened | -- | 1 (#90) | +1 |
| core.zig non-test lines | 801 | ~878 | +77 (regression) |

**Key observations:**
- 6 new findings (QF-058 through QF-063) from Phase 16 quality-reviewer pass.
- 1 regression (QF-050): core.zig grew from 801 to ~878 non-test lines due to undo integration. Issue #90 reopened.
- QF-058 (Score 60, High): handleCompletion `catch {}` on insertSlice advances cursor on OOM. Same class as resolved QF-053. 1-line fix.
- QF-059 (Score 48, Medium): `.delete_word` (Alt+D) is the only delete operation that does not save to kill ring. Breaks yank workflow. 4-line fix.
- QF-060 through QF-063 are all Low severity quick wins (1-2 lines each).
- No new Critical findings. All 6 new findings are quick wins (< 1 day effort).
- The `catch {}` + unconditional state update pattern (QF-058, QF-061, QF-062) recurs in 3 locations. A systematic sweep was performed; these are the remaining instances.
- 1 rejected finding from quality-reviewer: `vi_append` (O) cursor logic was reviewed and found correct (cursor=0 is valid after insert at index 0; no advancement needed).

### Phase 20 -> Phase 21 (Validated Scan Intake)

| Metric | Phase 20 (2026-03-24 full audit closure) | Phase 21 (2026-03-24 validated scan) | Delta |
|--------|------------------------------------------|--------------------------------------|-------|
| Total findings | 66 | 81 | +15 new |
| Open findings | 0 (1 partial, 1 accepted, 4 won't-do, 60 resolved) | 15 open (1 partial, 1 accepted, 4 won't-do, 60 resolved) | +15 new open |
| Resolved findings | 60 | 60 | 0 |
| Won't Do | 4 | 4 | 0 |
| Partial | 1 | 1 | 0 |
| Accepted | 1 | 1 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 0 (1 partial) | 1 new (1 partial) | +1 |
| Medium (open) | 0 (1 accepted) | 0 (1 accepted) | 0 |
| Low (open) | 0 | 14 | +14 |
| Highest open score | 85 (QF-026, partial) | 85 (QF-026, partial) | 0 |
| New issues created | -- | 1 (#119) | +1 |
| platform.zig lines | 796 (after QF-042) | 904 | +108 (regression) |
| processAction lines | 159 (after QF-051) | 166 | +7 (stable) |
| processInput lines | 53 (after QF-002) | 77 | +24 (regression) |

**Key observations:**
- 15 new findings from Phase 21 validated scan (QF-067 through QF-083; QF-068 rejected as duplicate of PF-038).
- 1 High-severity finding (QF-067): search.zig has 73 lines and 0 test blocks. Same pattern as resolved QF-046/QF-047 (extracted modules shipped without tests). GitLab issue #119 created.
- 14 Low-severity findings: 10 readability (long functions, deep nesting, catch {} on unreachable paths), 1 correctness (multi-byte key handling in search), 1 consistency (Vi 'O' catch {} pattern), 2 monitoring items.
- platform.zig regressed from 796 to 904 lines (QF-083), reversing the QF-042 fix. This is the largest single regression.
- processInput regrew from 53 to 77 lines (QF-078) due to undo snapshot integration added in Phase 14.
- processAction regrew from 159 to 166 lines (QF-070) -- still under 180-line target.
- No new Critical or Medium findings. All new items except QF-067 are Low severity quick wins.
- Per project convention, no GitLab issues created for Low findings (tracked in this document only).

### Phase 21 -> Phase 23 (Quality Reviewer Incremental)

| Metric | Phase 21 (2026-03-24 validated scan) | Phase 23 (2026-03-25 quality-reviewer) | Delta |
|--------|--------------------------------------|----------------------------------------|-------|
| Total findings | 81 | 85 | +4 new |
| Open findings | 13 (1 partial, 1 accepted, 4 won't-do, 62 resolved) | 17 open (1 partial, 1 accepted, 4 won't-do, 62 resolved) | +4 new open |
| Resolved findings | 62 | 62 | 0 |
| Won't Do | 4 | 4 | 0 |
| Partial | 1 | 1 | 0 |
| Accepted | 1 | 1 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 1 (1 partial) | 1 (1 partial) | 0 |
| Medium (open) | 0 (1 accepted) | 0 (1 accepted) | 0 |
| Low (open) | 12 | 16 | +4 |
| Highest open score | 85 (QF-026, partial) | 85 (QF-026, partial) | 0 |
| New issues created | -- | 0 (Low findings tracked in docs only) | 0 |
| platform.zig lines | 904 | 908 | +4 (continuing regression) |
| processAction lines | 166 | 169 | +3 (stable, under 180) |

**Key observations:**
- 4 new findings from Phase 23 quality-reviewer pass (QF-084 through QF-087).
- All 4 findings are Low severity. No new Critical, High, or Medium findings.
- QF-084 (Score 12, Documentation): 6 public functions missing `///` doc comments across completion.zig, config.zig, core.zig. Quick fix.
- QF-085 (Score 20, Testing): config.zig has only 3 tests for 240 non-test lines. loadFromFile, saveToFile, getDefaultConfigPath completely untested. Same pattern as resolved QF-046/QF-047.
- QF-086 (Score 16, Duplication): getDefaultHistoryPath and getDefaultConfigPath share ~50 lines of structural duplication. Natural follow-up to resolved QF-033 (isPathSafe extraction).
- QF-087 (Score 12, Correctness, confidence::suspected): handleSearch does not reset state.history_index on exit. Would need search + Up/Down navigation test to confirm. Cross-references QF-067 (search.zig zero test coverage).
- platform.zig continues to regress (904 -> 908 lines), widening the gap from the 800-line guideline.
- processAction grew from 166 to 169 lines but remains under the 180-line threshold.
- Per project convention, no GitLab issues created for Low findings (tracked in this document only).

### Phase 23 Closure (Gap Closure Cycle)

| Metric | Phase 23 (2026-03-25 intake) | Phase 23 closure (2026-03-25) | Delta |
|--------|--------------------------------------|----------------------------------------|-------|
| Total findings | 85 | 85 | 0 |
| Open findings | 17 open (1 partial, 1 accepted, 4 won't-do, 62 resolved) | 13 open (1 partial, 1 accepted, 4 won't-do, 66 resolved) | -4 open |
| Resolved findings | 62 | 66 | +4 |
| Won't Do | 4 | 4 | 0 |
| Partial | 1 | 1 | 0 |
| Accepted | 1 | 1 | 0 |
| Critical (open) | 0 | 0 | 0 |
| High (open) | 1 (1 partial) | 1 (1 partial) | 0 |
| Medium (open) | 0 (1 accepted) | 0 (1 accepted) | 0 |
| Low (open) | 16 | 12 | -4 |
| Highest open score | 85 (QF-026, partial) | 85 (QF-026, partial) | 0 |
| Test count | 285 | 300 | +15 new tests |
| New issues created | -- | 0 (Low findings, no GitLab issues) | 0 |

**Key observations:**
- All 4 Phase 23 intake findings resolved in this closure cycle.
- QF-084 (Score 12, Documentation): `///` doc comments added to 6 public functions in completion.zig, config.zig, core.zig.
- QF-085 (Score 20, Testing): 6 new tests added to config.zig for loadFromFile, saveToFile, round-trip, getDefaultConfigPath. config.zig now has 9 test blocks.
- QF-086 (Score 16, Duplication): `resolveEnvOverridePath` extracted to `src/text_utils.zig`, deduplicating ~50 lines from history.zig and config.zig.
- QF-087 (Score 12, Correctness): handleSearch ESC/Ctrl+C now reset `state.history_index = null`; Enter preserves found position. 6 unit tests added for `replaceNewlinesForDisplay` helper.
- Test suite grew from 285 to 300 tests (15 new). 300/300 pass in both debug and release modes.
- No GitLab issues created or closed (all Low-severity, doc-only tracking per policy).

---

**Key observations (Phase 5 -> Phase 6):**
- 8 new findings from Phase 3 quality-reviewer, all Medium or Low severity.
- No new Critical or High findings -- the codebase's major issues remain stable.
- 3 Medium-severity findings received GitLab issues: render.zig tests (#80), input.zig tests (#81), CI cache (#84).
- 5 Low-severity findings deferred without issues -- all are quick wins but individually low-impact.
- The extracted modules (render.zig, input.zig) shipped without adequate tests during Phase 4 refactoring. QF-046 and QF-047 address this gap.
- CI inefficiency (QF-048) is the highest-scoring new finding at 40 -- a quick win with broad pipeline impact.
- QF-049 (examples/ not formatted) is a natural follow-up to the resolved QF-036/QF-037 formatting findings.
- QF-042 (platform.zig 812 lines) is borderline; all 12 excess lines are test blocks. May be acceptable as-is.

---

## Confidence Notes

All findings tagged `confidence::confirmed` were verified by direct code inspection during this re-audit. Evidence includes:
- Line counts verified via `wc -l` on current source files.
- Function boundaries verified by reading source.
- Dead code confirmed via grep for callers across the entire `src/` directory.
- Duplication confirmed by reading both copies side-by-side.
- Signal handler wiring confirmed: `installTerminalSignalHandlers` is now called in `enterRawMode()`; `saved_termios` is now assigned.
- render.zig test count verified: `grep -c "^test " src/render.zig` = 28 (was 0; 28 tests added covering tabWidth, calculateVisualLines, calculateCursorPosition).
- input.zig test count verified: `grep -c "^test " src/input.zig` = 46 (was 1; 45 tests added covering all branch families).
- CI install-zig references counted: 7 `*install-zig` anchors in `.gitlab-ci.yml`.
- Vi 'e' motion duplication verified: identical word-end traversal at `keymap_vi.zig:110-116` and `keymap_vi.zig:223-228`.
- Makefile/pre-commit fmt targets verified: `examples/` absent from both.

- QF-050 core.zig regression verified: `wc -l src/core.zig` = 1051; `grep -n "^test " src/core.zig` shows first test at L886; non-test boundary at ~L850.
- QF-051 processAction size verified: `awk '/^fn processAction/,/^}/' src/core.zig | wc -l` = 231; .complete at L721-766 (47 LOC); .reverse_tab at L583-608 (27 LOC).
- QF-052 handleSearch single-byte bug verified: L802 `var search_buf: [256]u8`, L805 `const n = try stdin.read(&search_buf)`, L808 `const c = search_buf[0]` -- only index 0 used.
- QF-053 flushPasteBuffer cursor bug verified: L470 `insertSlice(...) catch {}`, L471 `state.cursor += sanitized.len` -- cursor advances unconditionally.
- QF-054 apt-get redundancy verified: L49 `apt-get update && apt-get install -y curl xz-utils` outside cache guard; 7 `*install-zig` references counted.

- QF-055 UndoStack.push leak verified: `src/undo.zig:61` `const buf_copy = try self.allocator.dupe(u8, buffer)` followed by `try self.entries.append(...)` at L62 -- no `errdefer` between them. If append fails, buf_copy is leaked.
- QF-056 no undo integration tests verified: `grep "undo" tests/integration.zig` = 0 matches. Unit tests exist in `src/undo.zig` but no end-to-end tests exercising keymap -> core -> undo path.
- QF-057 magic key codes verified: `src/input.zig:29-32` uses `0x02`, `0x05`, `0x06`, `0x7f`; `src/keymap_emacs.zig:79-81` switches on same values; `src/keymap_vi.zig:388-390` likewise. No named constants defined.

- QF-058 handleCompletion cursor desync verified: `src/core.zig:834` `insertSlice(...) catch {}` followed by L835 `state.cursor += candidate.len` -- cursor advances unconditionally on insert failure.
- QF-059 delete_word kill ring omission verified: `src/core.zig:630-636` has no `kill_ring` operations; compare with `delete_word_backward` at L637-648 which saves to kill ring and sets `last_was_kill`.
- QF-060 try vs catch {} inconsistency verified: L651 `try state.kill_ring.appendSlice(...)` (delete_to_eol), L657 `try state.kill_ring.appendSlice(...)` (delete_to_bol), but L642 `state.kill_ring.appendSlice(...) catch {}` (delete_word_backward).
- QF-061 Vi `o` cursor desync verified: `src/keymap_vi.zig:124` `state.buffer.append(...) catch {}` followed by L125 `state.cursor += 1` -- cursor advances on append failure.
- QF-062 completion prefix loss verified: `src/core.zig:805` `state.allocator.dupe(u8, prefix) catch ""` -- on OOM, original_prefix set to empty string instead of retaining actual prefix.
- QF-063 unused import verified: `src/search.zig:13` `const history_mod = @import("history.zig")` -- grep for `history_mod` returns only the import line; zero usage.
- QF-050 regression verified: `wc -l src/core.zig` = 1044; `grep -n "^test " src/core.zig` shows first test at L879; non-test boundary at ~878 (was 801 at Phase 12 close).

- QF-067 search.zig test gap verified: `wc -l src/search.zig` = 73; `grep -c "^test " src/search.zig` = 0; 7 distinct code paths identified by reading L34,39,46,50,57.
- QF-069 unreachable catch {} verified: 9 `replaceRange(..., &.{})` calls with `catch {}` at core.zig:636,646,661,775,785,831 and keymap_vi.zig:243,253,264. Zig's `replaceRange` with empty replacement slice (shrinking) does not allocate.
- QF-070 processAction size verified: L597-762 = 166 lines (was 159 at QF-051 resolution).
- QF-071 generateFilePathCandidates verified: completion.zig L191-277 = 87 lines.
- QF-072 renderPrompt verified: core.zig L263-348 = 86 lines.
- QF-073 parseKeyEvent nesting verified: input.zig L40-105; 7 levels: `if (data[0] == 0x1b) { if (data.len > 1) { if (data[1] == '[') { if (data.len > 2) { if (data.len > 3 ...) } } } }`.
- QF-074 isBalanced verified: parse.zig L36-150 = 115 lines; 5 state variables tracked.
- QF-075 loadFromFile nesting verified: config.zig L121-138; 7 `else if` comparisons inside iterator + key/value parsing.
- QF-076 handleInsertMode verified: keymap_vi.zig L326-394 = 69 lines.
- QF-077 handlePendingOperator verified: keymap_vi.zig L221-324 = 104 lines.
- QF-078 processInput verified: core.zig L350-426 = 77 lines (was 53 at QF-002 resolution).
- QF-079 history.zig append verified: L126-194 = 69 lines; handles dedup, max entries, file persistence with mutex.
- QF-080 Vi 'O' catch {} verified: keymap_vi.zig L131: `state.buffer.insert(state.allocator, 0, '\n') catch {};` -- QF-061 changed 'o' to `catch return .vi_insert_mode` but 'O' was not updated.
- QF-082 search.zig multi-byte verified: L27 `var search_buf: [256]u8`; L33 processes via `for (search_buf[0..n]) |c|`; ESC sequences (e.g., arrow keys = 3+ bytes) are processed byte-by-byte; individual bytes may fall through to printable handler.
- QF-083 platform.zig regression verified: `wc -l src/platform.zig` = 908; was 796 after QF-042. Continuing regression from 904 (Phase 21).
- QF-070 processAction size updated: L597-765 = 169 lines (was 166 at Phase 21).

Phase 23 new findings:
- QF-084 missing doc comments verified (`confidence::confirmed`): completion.zig:32 (init), completion.zig:39 (deinit), completion.zig:116 (generate), config.zig:59 (Keymap.fromString), config.zig:77 (Format.fromString), core.zig:248 (ReplState.deinit) -- all public functions lacking `///` doc comments.
- QF-085 config.zig test gap verified (`confidence::confirmed`): `grep -c "^test " src/config.zig` = 3; 240 non-test lines; `loadFromFile`, `saveToFile`, `getDefaultConfigPath` have zero test coverage.
- QF-086 path helper duplication verified (`confidence::confirmed`): history.zig:276-326 and config.zig:195-239 share env var check + isPathSafe + platform dispatch pattern (~50 lines structural duplication).
- QF-087 search history_index stale (`confidence::suspected`): search.zig:34-36, 39-43 exit search without resetting `state.history_index`. Would need test exercising search exit followed by Up/Down history navigation to confirm stale position. Cross-references QF-067 (zero test coverage for search.zig).

One `confidence::suspected` finding: QF-087. Confirmation requires a test exercising search exit followed by Up/Down history navigation to verify stale history_index behavior.

## Scoring Methodology

**PriorityScore** = Impact(1-5) x Likelihood(1-5) x 4, capped at 100.

- **Impact**: 5=outages/data loss, 4=frequent bugs/dev drag, 3=moderate, 2=minor, 1=polish
- **Likelihood**: 5=ubiquitous, 4=often, 3=sometimes, 2=rare, 1=edge-case
