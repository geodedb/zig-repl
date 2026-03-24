# Performance Gap Analysis -- devnw/zig/repl

**Project:** gitlab.com/devnw/zig/repl
**Last updated:** 2026-03-24 (Phase 10 review -- PF-039, PF-040 added; PF-009, PF-025 rescored)
**Audit phase:** Phase 10 review -- 2 new Info findings (PF-039, PF-040); PF-009 score 30->20; PF-025 reclassified P3->Info
**Methodology:** Static code analysis with PerfScore framework

---

## Summary

### Severity Distribution

| Severity | Open | Resolved | Total | Description |
|----------|------|----------|-------|-------------|
| P0       | 0    | 1        | 1     | SLO breach / outage risk -- immediate action |
| P1       | 0    | 3        | 3     | Material user-facing impact -- within sprint |
| P2       | 1    | 5        | 6     | Moderate impact / cost -- next quarter |
| P3       | 6    | 7        | 13    | Minor optimization -- backlog |
| Info     | 14   | 2        | 16    | Hardening / best practice -- as capacity allows |
| **Total**| **21** | **18** | **39** | |

**Progress since Phase 10 review:** Added PF-039 (Info, undo orderedRemove(0) at capacity) and PF-040 (Info, no SIGWINCH handler). Rescored PF-009 from 30 to 20 (dual buffer scan ~40-160ns, <1% of keystroke latency). Reclassified PF-025 from P3 (Score 15) to Info (targets in-memory fixedBufferStream, not file descriptor; ~200-500ns total for 100-char line). 18 of 39 total findings resolved. 21 open (1 P2, 6 P3, 14 Info).

### Top 5 Open Risks by Expected Impact

1. **PF-004 (P2, Score 55):** File open/close + makePath on every history append. Persistent file handle eliminates repeated syscalls. Issue #66. Deferred -- lifecycle complexity.
2. **PF-011 (P3, Score 30):** Per-candidate alloc/free churn in completion. Use arena allocator for completion cycle.
3. **PF-021 (P3, Score 25):** getTerminalWidth() issues ioctl syscall on every renderPrompt call. Cache the value and update via SIGWINCH handler. PF-040 is a prerequisite enabler.
4. **PF-010 (P3, Score 25):** orderedRemove(0) on history append overflow. Use ring buffer or swap-remove with sort.
5. **PF-009 (P3, Score 20):** Redundant buffer scan (calculateVisualLines + calculateCursorPosition). Rescored from 30 to 20 -- dual scan adds ~40-160ns, <1% of keystroke latency. Still worthwhile as a single-pass merge in render.zig.

---

## Stack-Ranked Findings

### Open Findings

| Rank | PF-ID | Severity | PerfScore | Finding | Component | Evidence | Issue | Fix Summary | Status |
|------|-------|----------|-----------|---------|-----------|----------|-------|-------------|--------|
| 1 | PF-004 | P2 | 55 | File open/close per history append (no persistent handle) | history.zig | `createFile` on every `append()` call; 2-3 syscalls per line added | [#66](https://gitlab.com/devnw/zig/repl/-/issues/66) | Keep persistent file handle; open at init | Deferred |
| ~~2~~ | PF-017 | P2 | 40 | Paste buffer 4096 silent truncation | core.zig | `if (paste_collect_len < paste_collect_buf.len)` silently drops chars | -- | Flush-and-continue: when paste buffer is full, flush to edit buffer and reset | Resolved |
| 3 | PF-011 | P3 | 30 | Per-candidate alloc/free churn in completion | completion.zig | `allocator.dupe()` per candidate in addCandidate; 1 alloc per candidate | [#70](https://gitlab.com/devnw/zig/repl/-/issues/70) | Use arena allocator for completion cycle | Deferred |
| ~~4~~ | PF-019 | P3 | 30 | Render buffer 8192 silent truncation | core.zig | `var render_buf: [8192]u8 = undefined` with `catch {}` overflow | -- | buffer_full flag stops writes on overflow; cursor positioning skipped to avoid broken ANSI | Resolved |
| 5 | PF-021 | P3 | 25 | getTerminalWidth() ioctl syscall on every renderPrompt | platform.zig:229, core.zig:252 | `platform.getTerminalWidth()` calls `ioctl(STDOUT_FILENO, TIOCGWINSZ)` per render; 1 syscall per keystroke | -- | Cache terminal width at init; install SIGWINCH handler to invalidate cache | Deferred |
| 6 | PF-010 | P3 | 25 | orderedRemove(0) on history append overflow | history.zig | `orderedRemove(0)` when entries exceed max; O(n) per append at capacity | [#69](https://gitlab.com/devnw/zig/repl/-/issues/69) | Use ring buffer or swap-remove with sort | Deferred |
| 7 | PF-022 | P3 | 20 | Global dedup orderedRemove(i) in while loop O(k*n) | history.zig:136-145 | `orderedRemove(i)` inside `while (i < self.entries.items.len)` loop when `deduplicate_global` is true; O(k*n) where k=duplicates, n=entries | -- | Use a hash set for O(1) lookup, or swap-remove + re-sort to avoid O(n) shift per removal | Deferred |
| 8 | PF-009 | P3 | 20 | Redundant buffer scan (calculateVisualLines + calculateCursorPosition) | render.zig | Both functions iterate entire buffer independently; 2x full buffer scan per render. Rescored 30->20: adds ~40-160ns for typical lines, <1% of keystroke latency | [#68](https://gitlab.com/devnw/zig/repl/-/issues/68) | Merge into single pass returning both values; now in render.zig for future work | Deferred |
| 9 | PF-026 | P3 | 15 | History search re-scans all entries per keystroke | core.zig:782, history.zig:224-234 | `searchBackward()` iterates all entries with `std.mem.indexOf` per entry; called on every keystroke in search mode | -- | Cache last match index and resume from there; or build incremental index | Deferred |
| 10 | PF-025 | Info | -- | Byte-by-byte writeAll to fixedBufferStream in render loop | core.zig:273-288 | `w.writeAll(&[_]u8{c})` in per-character loop; targets in-memory fixedBufferStream, not file descriptor. Per-byte overhead ~2-5ns function-call cost; ~200-500ns total for 100-char line. Reclassified P3->Info: not an I/O problem | -- | Batch write contiguous printable runs; only break for control character substitutions | Deferred |
| ~~11~~ | PF-028 | P3 | 25 | History load() dupes all lines then frees excess beyond max_entries | history.zig:88-109 | `allocator.dupe(u8, line)` for every line, then frees excess entries when count > max_entries; 10k-line file = 10k allocs + 5k frees | -- | Two-pass approach: count lines first, skip `total - max_entries` before allocating | Resolved |
| ~~12~~ | PF-027 | P3 | 20 | History ArrayList no preallocation during load() | history.zig:43,88-94 | `initCapacity(allocator, 0)` at line 43; `append` in loop at lines 89-94 causes ~13 reallocs for 5000 entries (geometric growth) | -- | Added `ensureTotalCapacity(min(file_size / 40, max_entries))` before load loop | Resolved |
| ~~13~~ | PF-035 | P3 | 20 | apt-get install runs in every CI job (~2-3.5min aggregate overhead) | .gitlab-ci.yml:49 | `apt-get update && apt-get install -y curl xz-utils` in `.install-zig` anchor; runs in every job using the anchor | -- | Moved apt-get inside cache guard with `command -v` check; runs only when needed | Resolved |
| 14 | PF-014 | Info | -- | Entire history file read into memory | history.zig | `allocator.alloc(u8, file_size)` for full file; bounded by 64MB check | -- | Read from end of file; or stream-parse lines | Deferred |
| 15 | PF-013 | Info | -- | No benchmark suite | -- | No benchmark infrastructure exists | -- | Add `zig build bench` target with key scenarios | Deferred |
| 16 | PF-023 | Info | -- | handleSearch() direct stdout writes (2 syscalls/keystroke) | core.zig:747,795 | `stdout.writeAll` called twice per keystroke in search mode: once for initial prompt (line 747) and once for search result display (line 795); unbuffered direct writes | -- | Buffer search output into a stack buffer and flush once per keystroke | Deferred |
| 17 | PF-029 | Info | -- | appendToMultiLine no pre-allocate for continuation buffer | core.zig:478-486 | `appendSlice` without prior `ensureTotalCapacity`; each continuation triggers potential reallocs in multi_line_buffer | -- | Pre-allocate with `ensureTotalCapacity(input.len + 1)` before append | Deferred |
| 18 | PF-030 | Info | -- | search_buffer starts at capacity 0 | core.zig:181 | `initCapacity(opts.allocator, 0)` for search_buffer; every search keystroke triggers realloc growth | -- | Pre-allocate 64-128 bytes at init (typical search queries are short) | Deferred |
| 19 | PF-031 | Info | -- | ReplState buffers (buffer, kill_ring, multi_line_buffer) start at capacity 0 | core.zig:172-184 | All four ArrayList fields initialized with `initCapacity(allocator, 0)`; first use triggers realloc | -- | Pre-allocate reasonable defaults: buffer=256, kill_ring=128, multi_line_buffer=256, search_buffer=64 | Deferred |
| 20 | PF-032 | Info | -- | Two writeAll syscalls in history append | history.zig:179-180 | `file.writeAll(line)` then `file.writeAll("\n")` -- two separate syscalls per history append | -- | Concatenate line + newline into single buffer before write, or use writev/iovec | Deferred |
| 21 | PF-033 | Info | -- | shouldUseColor() calls 2 getenv + 1 isatty per TerminalWriter init | platform.zig:269-283,357 | `getenv("NO_COLOR")`, `getenv("TERM")`, `isStdoutTty()` called in `shouldUseColor()` which is called in every `TerminalWriter.init()` | -- | Cache result in module-level `var` on first call; environment does not change during process lifetime | Deferred |
| 22 | PF-034 | Info | -- | Config.loadFromFile no pre-size-check for readToEndAlloc | config.zig:109 | `file.readToEndAlloc(allocator, 1024 * 1024)` reads without checking file size first; may over-allocate for small config files | -- | Call `file.getEndPos()` first and allocate exact size, or use smaller initial max (e.g. 64KB for config) | Deferred |
| 23 | PF-036 | Info | -- | Build job missing --summary all flag for test output | .gitlab-ci.yml:92 | `zig build` without `--summary all`; no build summary in CI logs for diagnosing slow compilation | -- | Add `--summary all` to build command for visibility into compilation steps | Deferred |
| 24 | PF-038 | Info | -- | Undo pre-snapshot alloc+free on non-destructive keypresses | core.zig:371,393-394 | `allocator.dupe()` runs on every keypress; freed immediately at line 394 for non-destructive actions (~15-40% of keypresses). Cost ~100-300ns per wasted cycle; terminal I/O syscalls are 100-1000x more expensive | -- | Conditional dupe (only allocate after action is classified as destructive). Not worth the complexity -- adds a second keymap dispatch or deferred snapshot pattern for sub-microsecond gain | Deferred |
| 25 | PF-039 | Info | -- | UndoStack orderedRemove(0) at capacity | undo.zig:57,75 | `orderedRemove(0)` shifts up to 99 entries (~2.4KB) when stack is full; ~100-200ns per destructive keypress. L1-cache-resident data, 50-100x cheaper than any syscall | -- | Replace with ring buffer (write index wraps around). Low priority -- data fits in L1 cache and cost is negligible vs. terminal I/O | Deferred |
| 26 | PF-040 | Info | -- | No SIGWINCH handler (enabler for PF-021) | platform.zig:242-258 | Signal infrastructure exists for SIGTERM/SIGHUP but SIGWINCH is not registered. Prerequisite for PF-021 (terminal width caching via SIGWINCH invalidation). No standalone performance impact | -- | Register SIGWINCH handler alongside existing SIGTERM/SIGHUP handlers; set a flag that getTerminalWidth() checks to refresh cached value. Implement when PF-021 is addressed | Deferred |
| ~~27~~ | PF-024 | Info | -- | CI re-downloads Zig on every job (no caching) | .gitlab-ci.yml:36-73 | `curl -fsSL` downloads Zig tarball in every CI job; no `cache:` directive | -- | Global `cache:` block added with `key: zig-${ZIG_VERSION}` and `paths: [zig-${ZIG_VERSION}/]` | Resolved |

### Resolved Findings

| PF-ID | Severity | PerfScore | Finding | Component | Resolution | Resolved In |
|-------|----------|-----------|---------|-----------|------------|-------------|
| PF-001 | P0 | 92 | Byte-by-byte stdout writes (~100 syscalls/render) | core.zig:340-343 | fixedBufferStream with 8192-byte render_buf, single writeAll per render | Phase 4 |
| PF-002 | P1 | 78 | O(n*k) insert during bracketed paste | core.zig:454-478 | Batch paste into paste_collect_buf[4096], single insertSlice | Phase 4 |
| PF-003 | P1 | 75 | O(n^2) orderedRemove(0) during history load | history.zig:90-103 | Bulk trim with copyForwards after loading all entries | Phase 4 |
| PF-015 | P1 | 65 | Vi dw/db/de orderedRemove loops -- O(n*w) vs O(n) | keymap_vi.zig:91-122 | Replaced orderedRemove loops with single `replaceRange` calls at `src/keymap_vi.zig:91,103,121` | Phase 5 |
| PF-007 | P2 | 60 | Unbounded directory iteration in completion | completion.zig:18,240 | MAX_FILE_CANDIDATES=256 cap on iteration | Phase 4 |
| PF-005 | P2 | 50 | TerminalWriter newline conversion multi-write | platform.zig:362-391 | 8192-byte stack buffer (WRITE_BUF_SIZE), single writeAll | Phase 4 |
| PF-016 | P2 | 50 | delete_to_bol unnecessary heap allocation | core.zig:834-843 | Replaced heap alloc with `replaceRange(0, cursor, &.{})`. Zero allocations for Ctrl-U. | Phase 5 |
| PF-006 | P2 | 45 | 3 writeAll calls per ANSI color sequence | platform.zig:450-465 | 16-byte stack buffer, single writeAll per sequence | Phase 4 |
| PF-018 | P3 | 35 | appendHistoryFiltered per-byte append without capacity reservation | core.zig:408-414 | Now calls `ensureTotalCapacity` + `appendAssumeCapacity` instead of per-byte `append`. Eliminates realloc churn. | Phase 5 |
| PF-008 | P3 | 35 | orderedRemove in loop for word deletion | core.zig:812-823 | replaceRange for O(n) word deletion | Phase 4 |
| PF-020 | P3 | 15 | reverse_tab orderedRemove x4 | core.zig:790-794 | Replaced up-to-4 orderedRemove calls with single `replaceRange` call. Consistent with replaceRange pattern. | Phase 5 |
| PF-012 | Info | -- | No build/test CI stage | .gitlab-ci.yml | CI now has build + 4 test stages + fuzz stage in .gitlab-ci.yml | Phase 6 |
| PF-017 | P2 | 40 | Paste buffer 4096 silent truncation | core.zig | Flush-and-continue: when paste buffer fills, flush to edit buffer via sanitizePasteContent + insertSlice, reset, continue collecting. Handles arbitrarily large pastes without dynamic allocation. | Phase 9 |
| PF-019 | P3 | 30 | Render buffer 8192 silent truncation | core.zig | Replaced `catch {}` with `buffer_full` flag. Writes stop on overflow; cursor positioning skipped to prevent broken ANSI sequences. Valid partial content still written. | Phase 9 |
| PF-024 | Info | -- | CI re-downloads Zig on every job (no caching) | .gitlab-ci.yml | Global `cache:` block added with `key: zig-${ZIG_VERSION}` and `paths: [zig-${ZIG_VERSION}/]` | Phase 8 |

---

## Findings by Area

### Application (`area::app`)

| PF-ID | Severity | Score | File | Summary | Status |
|-------|----------|-------|------|---------|--------|
| PF-001 | P0 | 92 | core.zig | Byte-by-byte stdout writes in render loop | Resolved |
| PF-002 | P1 | 78 | core.zig | O(n*k) insert during bracketed paste | Resolved |
| PF-003 | P1 | 75 | history.zig | O(n^2) orderedRemove(0) during history load | Resolved |
| PF-015 | P1 | 65 | keymap_vi.zig | Vi dw/db/de orderedRemove loops | Resolved |
| PF-007 | P2 | 60 | completion.zig | Unbounded directory iteration | Resolved |
| PF-004 | P2 | 55 | history.zig | File open/close per history append | Deferred |
| PF-005 | P2 | 50 | platform.zig | Multi-write newline conversion | Resolved |
| PF-016 | P2 | 50 | core.zig | delete_to_bol heap allocation | Resolved |
| PF-006 | P2 | 45 | platform.zig | Multi-write ANSI sequences | Resolved |
| PF-017 | P2 | 40 | core.zig | Paste buffer 4096 silent truncation | Resolved |
| PF-008 | P3 | 35 | core.zig | orderedRemove in word deletion loop | Resolved |
| PF-018 | P3 | 35 | core.zig | appendHistoryFiltered per-byte append | Resolved |
| PF-009 | P3 | 20 | render.zig | Redundant dual buffer scan (rescored 30->20) | Deferred |
| PF-011 | P3 | 30 | completion.zig | Per-candidate allocation churn | Deferred |
| PF-019 | P3 | 30 | core.zig | Render buffer 8192 silent truncation | Resolved |
| PF-021 | P3 | 25 | platform.zig, core.zig | getTerminalWidth() ioctl per renderPrompt | Deferred |
| PF-010 | P3 | 25 | history.zig | orderedRemove(0) on append overflow | Deferred |
| PF-022 | P3 | 20 | history.zig | Global dedup orderedRemove in while loop O(k*n) | Deferred |
| PF-025 | Info | -- | core.zig | Byte-by-byte writeAll to fixedBufferStream (reclassified P3->Info) | Deferred |
| PF-026 | P3 | 15 | core.zig, history.zig | History search re-scans all entries per keystroke | Deferred |
| PF-020 | P3 | 15 | core.zig | reverse_tab orderedRemove x4 | Resolved |
| PF-028 | P3 | 25 | history.zig | History load() dupes all lines then frees excess | Resolved |
| PF-027 | P3 | 20 | history.zig | History ArrayList no preallocation during load() | Resolved |
| PF-014 | Info | -- | history.zig | Full history file read into memory | Deferred |
| PF-023 | Info | -- | core.zig | handleSearch() direct stdout writes (2 syscalls/keystroke) | Deferred |
| PF-029 | Info | -- | core.zig | appendToMultiLine no pre-allocate | Deferred |
| PF-030 | Info | -- | core.zig | search_buffer starts at capacity 0 | Deferred |
| PF-031 | Info | -- | core.zig | ReplState buffers start at capacity 0 | Deferred |
| PF-032 | Info | -- | history.zig | Two writeAll syscalls in history append | Deferred |
| PF-033 | Info | -- | platform.zig | shouldUseColor() 2 getenv + 1 isatty per TerminalWriter | Deferred |
| PF-034 | Info | -- | config.zig | Config.loadFromFile no pre-size-check | Deferred |
| PF-038 | Info | -- | core.zig | Undo pre-snapshot alloc+free on non-destructive keypresses | Deferred |
| PF-039 | Info | -- | undo.zig | UndoStack orderedRemove(0) at capacity | Deferred |
| PF-040 | Info | -- | platform.zig | No SIGWINCH handler (enabler for PF-021) | Deferred |

### Infrastructure (`area::infra`)

| PF-ID | Severity | Score | File | Summary | Status |
|-------|----------|-------|------|---------|--------|
| PF-035 | P3 | 20 | .gitlab-ci.yml | apt-get install runs in every CI job | Resolved |
| PF-012 | Info | -- | .gitlab-ci.yml | No build/test CI stage | Resolved |
| PF-013 | Info | -- | build.zig | No benchmark suite | Deferred |
| PF-024 | Info | -- | .gitlab-ci.yml | CI re-downloads Zig on every job (no caching) | Resolved |
| PF-036 | Info | -- | .gitlab-ci.yml | Build job missing --summary all flag | Deferred |

---

## Roadmap

### Quick Wins (< 1 day)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-009 | 20 | Merge calculateVisualLines + calculateCursorPosition into single pass (now in render.zig). Rescored 30->20 | 1-2 hours | Deferred |
| PF-021 | 25 | Cache terminal width in a module-level var; install SIGWINCH handler to invalidate | 2-3 hours | Deferred |
| PF-027 | 20 | Added `ensureTotalCapacity(min(file_size / 40, max_entries))` before history load loop | 30 min | Resolved |
| PF-029 | -- | Pre-allocate multi_line_buffer with `ensureTotalCapacity(input.len + 1)` before append | 15 min | Deferred |
| PF-025 | -- | Batch contiguous printable character runs into single writeAll calls in render loop (reclassified P3->Info) | 1-2 hours | Deferred |
| PF-026 | 15 | Cache last match index in searchBackward; resume search from cached position | 2-3 hours | Deferred |
| PF-030 | -- | Pre-allocate search_buffer with 64-128 bytes at init | 15 min | Deferred |
| PF-031 | -- | Pre-allocate ReplState buffers with reasonable defaults (buffer=256, kill_ring=128, etc.) | 30 min | Deferred |
| PF-032 | -- | Concatenate history line + newline into single write | 30 min | Deferred |
| PF-033 | -- | Cache shouldUseColor() result in module-level var | 15 min | Deferred |
| PF-034 | -- | Call getEndPos() before readToEndAlloc in Config.loadFromFile | 15 min | Deferred |
| PF-039 | -- | UndoStack: ring buffer instead of orderedRemove(0). L1-cache-resident, negligible cost | 1-2 hours | Deferred |
| PF-040 | -- | Register SIGWINCH handler alongside SIGTERM/SIGHUP. Enabler for PF-021 width caching | 1-2 hours | Deferred |
| PF-036 | -- | Add `--summary all` to build command in .gitlab-ci.yml | 5 min | Deferred |

### Medium Effort (1-5 days)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-004 | 55 | Persistent file handle for history; open at init, append-only writes | 1 day | Deferred -- lifecycle complexity |
| PF-028 | 25 | Two-pass approach: count lines, skip `total - max_entries` before allocating | 2-4 hours | Resolved |
| PF-035 | 20 | Moved apt-get inside cache guard with `command -v` check | 2-4 hours | Resolved |
| PF-017 | 40 | Flush-and-continue: paste buffer flushes to edit buffer when full | 1-2 days | Resolved |
| PF-019 | 30 | buffer_full flag stops writes on overflow; cursor positioning skipped | 1 day | Resolved |
| PF-022 | 20 | Replace linear scan dedup with hash set for O(1) lookup, or swap-remove + re-sort | 1 day | Deferred |
| PF-024 | -- | Add GitLab CI `cache:` directive for Zig installation directory | 1-2 hours | Resolved |
| PF-014 | -- | Stream history file or read from end | 2-3 days | Deferred |

### Strategic (> 5 days)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-011 | 30 | Arena allocator for completion lifecycle | 2-3 days | Deferred |
| PF-010 | 25 | Ring buffer for history or swap-remove with sort | 3-5 days | Deferred |
| PF-013 | -- | Benchmark suite (render, paste, history, completion) | 3-5 days | Deferred |
| PF-023 | -- | Buffer all search mode output into stack buffer; single flush per keystroke | 1 day | Deferred |

---

## Tracked Issues

| PF-ID | Severity | Issue URL | Status |
|-------|----------|-----------|--------|
| PF-001 | P0 | [#42](https://gitlab.com/devnw/zig/repl/-/issues/42) | Resolved |
| PF-002 | P1 | [#44](https://gitlab.com/devnw/zig/repl/-/issues/44) | Resolved |
| PF-003 | P1 | [#47](https://gitlab.com/devnw/zig/repl/-/issues/47) | Resolved |
| PF-015 | P1 | [#67](https://gitlab.com/devnw/zig/repl/-/issues/67) | Resolved |
| PF-004 | P2 | [#66](https://gitlab.com/devnw/zig/repl/-/issues/66) | Deferred |
| PF-010 | P3 | [#69](https://gitlab.com/devnw/zig/repl/-/issues/69) | Deferred |
| PF-011 | P3 | [#70](https://gitlab.com/devnw/zig/repl/-/issues/70) | Deferred |
| PF-012 | Info | [#1](https://gitlab.com/devnw/zig/repl/-/issues/1), [#71](https://gitlab.com/devnw/zig/repl/-/issues/71) | Resolved |

*Note: PF-021 through PF-040 are all P3/Info severity (backlog). No GitLab issues created per policy -- issues are only tracked for P0-P2 findings.*

---

## Changelog

| Date | Change |
|------|--------|
| 2026-03-24 (Phase 10 review) | Phase 10 review: 2 new Info findings added, 2 severity adjustments. **New findings:** PF-039 (Info) -- UndoStack orderedRemove(0) at capacity shifts ~99 entries (~2.4KB), ~100-200ns per destructive keypress, L1-cache-resident and 50-100x cheaper than any syscall. PF-040 (Info) -- No SIGWINCH handler; signal infrastructure exists for SIGTERM/SIGHUP but SIGWINCH not registered; prerequisite enabler for PF-021 terminal width caching; no standalone perf impact. **Severity adjustments:** PF-009 rescored 30->20 (P3): dual buffer scan adds ~40-160ns for typical lines, <1% of keystroke latency; score 30 overstated impact but fix remains worthwhile. PF-025 reclassified P3 (Score 15)->Info: "byte-by-byte writeAll" targets in-memory fixedBufferStream, not file descriptor; per-byte overhead ~2-5ns function-call cost, ~200-500ns total for 100-char line; not an I/O problem. No GitLab issues created (all Info/P3 level). Updated severity distribution (39 total, 21 open, 18 resolved). |
| 2026-03-24 (Phase 9 audit) | Phase 9 audit: added PF-038 (Info) -- undo pre-snapshot alloc+free on non-destructive keypresses. Originally flagged as P2 by Phase 2 scanner, downgraded to Info by Phase 3 deep reviewer. Absolute cost ~100-300ns per non-destructive keypress; terminal I/O syscalls are 100-1000x more expensive. Persistent shadow buffer fix adds complexity for near-zero gain. No GitLab issue created (Info-level). Updated severity distribution (37 total, 19 open, 18 resolved). Corrected pre-existing count errors: P2 resolved 6->5 (total 7->6), P3 open/resolved 6/8->7/7. |
| 2026-03-24 (Phase 10) | Phase 10 performance review: added 10 new findings (PF-027 through PF-036). 3 P3 findings: PF-027 (history ArrayList no preallocation, Score 20), PF-028 (history load dupes all lines then frees excess, Score 25), PF-035 (apt-get install in every CI job, Score 20). 7 Info findings: PF-029 (appendToMultiLine no pre-allocate), PF-030 (search_buffer capacity 0), PF-031 (ReplState buffers capacity 0), PF-032 (two writeAll syscalls in history append), PF-033 (shouldUseColor 2 getenv + 1 isatty), PF-034 (Config.loadFromFile no pre-size-check), PF-036 (build job missing --summary all). No GitLab issues created -- all findings are P3/Info backlog. Updated severity distribution (37 total, 20 open, 17 resolved), top 5 risks, roadmap. |
| 2026-03-24 (Phase 6) | Phase 6 re-audit: resolved PF-012 (CI now has build + 4 test stages + fuzz). Added 6 new findings: PF-021 (ioctl per render), PF-022 (global dedup O(k*n)), PF-023 (search mode direct stdout writes), PF-024 (CI Zig re-download), PF-025 (byte-by-byte fixedBufferStream writes), PF-026 (history search full re-scan per keystroke). Updated severity distribution, roadmap split into Quick Wins / Medium / Strategic tiers. No new GitLab issues -- all new findings are P3/Info backlog. |
| 2026-03-24 (post-closure) | Phase 5 gap closure: resolved PF-015 (replaceRange for vi word ops), PF-016 (replaceRange for delete_to_bol), PF-018 (ensureTotalCapacity for history filter), PF-020 (replaceRange for reverse_tab). Updated PF-009 component from core.zig to render.zig. Updated severity distribution, roadmap, and status for all remaining items. |
| 2026-03-24 | Phase 4 re-audit: marked 7 findings resolved (PF-001, PF-002, PF-003, PF-005, PF-006, PF-007, PF-008). Added 6 new findings (PF-015 through PF-020). Updated severity distribution, roadmap, and recommended fix order. |
| 2026-03-23 | Phase 3 initial scoring and issue tracking: 14 findings identified and scored. Issues created for P0-P1 items. |
