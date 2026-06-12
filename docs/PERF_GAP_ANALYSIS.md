# Performance Gap Analysis -- devnw/zig/repl

**Project:** gitlab.com/devnw/zig/repl
**Last updated:** 2026-06-12 (Audit Cycle 3 -- Re-review: PF-043 resolved (lazy undo snapshot, commit d039c05); 10 new findings PF-043--PF-052 recorded, all LOW/INFO/P3 backlog)
**Audit phase:** Audit Cycle 3 (Re-review on branch `audit-cycle-3-gap-closure`) -- 1 resolved (lazy per-keystroke undo snapshot), 9 new tracked-open/deferred/won't-do items (all sub-µs / cold-path); GitLab issues #128--#132, #134, #135 reconciled (no duplicates created)
**Methodology:** Static code analysis with PerfScore framework

---

## Summary

### Severity Distribution

| Severity | Open | Resolved | Won't Do | Total | Description |
|----------|------|----------|----------|-------|-------------|
| P0       | 0    | 1        | 0        | 1     | SLO breach / outage risk -- immediate action |
| P1       | 0    | 3        | 0        | 3     | Material user-facing impact -- within sprint |
| P2       | 0    | 6        | 0        | 6     | Moderate impact / cost -- next quarter |
| P3       | 5    | 13       | 0        | 18    | Minor optimization -- backlog |
| Info     | 10   | 5        | 7        | 22    | Hardening / best practice -- as capacity allows |
| **Total**| **15** | **28** | **7** | **50** | |

**Progress this cycle (Audit Cycle 3 -- Re-review, 2026-06-12):** 1 item resolved -- **PF-043** (lazy per-keystroke undo snapshot, commit d039c05): the pre-edit buffer dupe is now taken lazily via a `keyMayMutate` predictor, so pure cursor moves / history-nav perform ZERO buffer dupes and no-op edits (backspace-at-BOL, delete-at-EOL) skip dead undo entries; verified by a counting-allocator test. This effectively closes the optimization that PF-038 previously declined (PF-038 stays Won't Do as originally scoped; PF-043 records the realized fix). 9 new findings recorded as tracked backlog -- 4 P3 open (PF-044 defaultIo fat-struct, PF-046 file.length() extra syscall, PF-047 history-append newline alloc, PF-048 UndoStack O(n) eviction), 4 Info open/deferred (PF-045 single-threaded Mutex spinlock, PF-049 3x stderr writeAll, PF-050 TerminalWriter 6+ syscalls, PF-051 searchBackward per-keystroke re-scan), 1 Info Won't Do (PF-052 UndoStack uncapped retained bytes). **All new items are sub-µs / cold-path; none are P0/P1.** GitLab issues #128--#132, #134, #135 reconciled (PF-IDs cross-referenced in comments; no duplicate issues created). Overall performance posture remains Strong/Production-Ready: keystroke-to-render latency ~5-20µs, 500-2000x below human perception.

**Cumulative (since Phase 15):** Phase 15 resolved 8 (single-pass render, arena allocator, SIGWINCH+cached width, O(n) dedup, search resume, writev, CI summary) and marked 6 Won't Do (sub-µs optimizations not worth complexity). 28 of 50 total findings resolved, 7 won't do, 15 open (5 P3, 10 Info).

### Top Open Risks by Expected Impact

1. **PF-048 (P3, Score 25):** UndoStack orderedRemove(0) O(n) memmove on eviction; fires every ~100 destructive keystrokes at steady state. Ring buffer or swap eviction. [#132](https://gitlab.com/devnw/zig/repl/-/issues/132)
2. **PF-010 (P3, Score 25):** orderedRemove(0) on history append overflow. Use ring buffer or swap-remove with sort. [#69](https://gitlab.com/devnw/zig/repl/-/issues/69)
3. **PF-046 (P3, Score 20):** file.length() extra syscall before every history append on the persistent handle. Track length in-process. [#130](https://gitlab.com/devnw/zig/repl/-/issues/130)
4. **PF-047 (P3, Score 16):** heap alloc+free per history append solely to concatenate the trailing newline. Use writev iovec. [#131](https://gitlab.com/devnw/zig/repl/-/issues/131)
5. **PF-044 (P3, Score 16, suspected):** defaultIo() constructs a fat Io struct (~30 fn-ptr fields) per call, ~28 sites incl. render path; optimizer may fold. Confirm with disassembly. [#128](https://gitlab.com/devnw/zig/repl/-/issues/128)

All five are minor-optimization backlog (P3). None affect the interactive keystroke-to-render hot path materially; the per-keystroke undo allocation that did sit on the hot path was resolved this cycle (PF-043).

---

## Stack-Ranked Findings

### Open Findings

| Rank | PF-ID | Severity | PerfScore | Finding | Component | Evidence | Issue | Fix Summary | Status |
|------|-------|----------|-----------|---------|-----------|----------|-------|-------------|--------|
| ~~1~~ | PF-004 | P2 | 48 | File open/close per history append (no persistent handle) | history.zig | `createFile` on every `append()` call; 6 syscalls per line added (open+write+write+chmod+close+fsync; chmod added by SF-024 security fix). Runs once per Enter key, not per keystroke. Rescored 55->48: Impact 4 x Likelihood 3 x 4 | [#66](https://gitlab.com/devnw/zig/repl/-/issues/66) | Added `append_handle: ?std.fs.File` field; lazily opened on first append, reused for all subsequent appends; closed in deinit() and reset in clear(). syscalls reduced from 6 to 2 per append. 3 tests added | Resolved |
| ~~2~~ | PF-017 | P2 | 40 | Paste buffer 4096 silent truncation | core.zig | `if (paste_collect_len < paste_collect_buf.len)` silently drops chars | -- | Flush-and-continue: when paste buffer is full, flush to edit buffer and reset | Resolved |
| ~~3~~ | PF-019 | P3 | 30 | Render buffer 8192 silent truncation | core.zig | `var render_buf: [8192]u8 = undefined` with `catch {}` overflow | -- | buffer_full flag stops writes on overflow; cursor positioning skipped to avoid broken ANSI | Resolved |
| ~~4~~ | PF-021 | P3 | 25 | getTerminalWidth() ioctl syscall on every renderPrompt | platform.zig | `platform.getTerminalWidth()` calls `ioctl(STDOUT_FILENO, TIOCGWINSZ)` per render; 1 syscall per keystroke | -- | Added SIGWINCH handler (PF-040) + cached terminal width; `terminal_resized` flag invalidates cache on resize; getTerminalWidth() returns cached value when valid | Resolved |
| 5 | PF-048 | P3 | 24 | UndoStack orderedRemove(0) O(n) memmove on eviction | undo.zig | `orderedRemove(0)` when the undo stack is full (cap 100); O(n) memmove shifting up to 99 entries, fires every ~100 destructive keystrokes at steady state. Impact 3 x Likelihood 2 x 4 = 24 | [#132](https://gitlab.com/devnw/zig/repl/-/issues/132) | Ring buffer (head/tail indices) or swap-out eviction to avoid the O(n) shift | Open |
| 6 | PF-010 | P3 | 25 | orderedRemove(0) on history append overflow | history.zig | `orderedRemove(0)` when entries exceed max; O(n) per append at capacity | [#69](https://gitlab.com/devnw/zig/repl/-/issues/69) | Use ring buffer or swap-remove with sort | Deferred |
| 7 | PF-046 | P3 | 20 | file.length() extra syscall before every history append | history.zig | `file.length()` called before every `writePositionalAll` on the persistent append handle; 1 extra syscall per history append (per Enter, not per keystroke). Impact 3 x Likelihood ~2 (once per submitted line) x 4 ... class 20 | [#130](https://gitlab.com/devnw/zig/repl/-/issues/130) | Track the write offset in-process; avoid the per-append length syscall | Open |
| 8 | PF-047 | P3 | 16 | Heap alloc+free per history append for newline concat | history.zig | `allocator.alloc` + `defer free` per `append()` solely to concatenate the trailing `\n`; 1 alloc/free pair per submitted line. Impact 2 x Likelihood 2 x 4 = 16 | [#131](https://gitlab.com/devnw/zig/repl/-/issues/131) | Use `writev`/iovec `[line, "\n"]` (mirrors PF-032) -- zero extra allocation | Open |
| 9 | PF-044 | P3 | 16 | defaultIo() constructs fat Io struct (~30 fn-ptr fields) per call | core.zig (and ~28 sites) | `defaultIo()` builds the full `std.Io` vtable struct on every call; ~28 production call sites including the per-keystroke render path. Suspected -- the optimizer may fold the constant construction. Impact 4 x Likelihood ... discounted by suspected-fold: Impact 2 x Likelihood 2 x 4 = 16 | [#128](https://gitlab.com/devnw/zig/repl/-/issues/128) | Hoist a single cached `Io` instance; OR confirm via disassembly the construction is folded and close as no-op | Open |
| 10 | PF-051 | Info | -- | searchBackward re-scans history per search keystroke | search.zig:83, history.zig:264 | `searchBackward` re-scans history entries on each search keystroke; O(N·patternlen) worst case. Note PF-026 already added resume-from-history_index for the incremental match cursor; this finding is the residual full-pattern re-compare cost within a single keystroke's scan. Cold path (only in reverse-search mode) | -- | Memoize last match span; or short-circuit when the query is an extension of the prior query | Deferred |
| ~~6~~ | PF-011 | P3 | 24 | Per-candidate alloc/free churn in completion | completion.zig | `allocator.dupe()` per candidate in addCandidate; 1 alloc per candidate, up to 256 alloc/free at ~25-50us total; runs once per Tab press | [#70](https://gitlab.com/devnw/zig/repl/-/issues/70) | Added `arena: std.heap.ArenaAllocator` to CompletionContext; `addCandidate` uses arena allocator; `reset()` uses `arena.reset(.retain_capacity)` — O(1) instead of N frees | Resolved |
| ~~7~~ | PF-022 | P3 | 20 | Global dedup orderedRemove(i) in while loop O(k*n) | history.zig | `orderedRemove(i)` inside `while` loop when `deduplicate_global` is true; O(k*n) where k=duplicates, n=entries | -- | Replaced with O(n) single-pass compacting: forward scan with write_idx, free duplicates in-place, shrinkRetainingCapacity at end | Resolved |
| ~~8~~ | PF-009 | P3 | 20 | Redundant buffer scan (calculateVisualLines + calculateCursorPosition) | render.zig | Both functions iterate entire buffer independently; 2x full buffer scan per render | [#68](https://gitlab.com/devnw/zig/repl/-/issues/68) | Added `calculateRenderInfo()` single-pass function; core.zig renderPrompt now calls it once instead of two separate functions | Resolved |
| ~~9~~ | PF-026 | P3 | 15 | History search re-scans all entries per keystroke | search.zig:82, history.zig | `searchBackward()` called with `null` start_index, causing full re-scan from end on every keystroke | -- | Changed `null` to `state.history_index` at search.zig:82; search resumes from last match position | Resolved |
| ~~10~~ | PF-025 | Info | -- | Byte-by-byte writeAll to fixedBufferStream in render loop | core.zig | `w.writeAll(&[_]u8{c})` in per-character loop; targets in-memory fixedBufferStream. Per-byte overhead ~2-5ns; ~200-500ns total for 100-char line. Not an I/O problem | -- | Won't Do -- in-memory fixedBufferStream writes are sub-microsecond; batching adds complexity for negligible gain | Won't Do |
| ~~11~~ | PF-028 | P3 | 25 | History load() dupes all lines then frees excess beyond max_entries | history.zig:88-109 | `allocator.dupe(u8, line)` for every line, then frees excess entries when count > max_entries; 10k-line file = 10k allocs + 5k frees | -- | Two-pass approach: count lines first, skip `total - max_entries` before allocating | Resolved |
| ~~12~~ | PF-027 | P3 | 20 | History ArrayList no preallocation during load() | history.zig:43,88-94 | `initCapacity(allocator, 0)` at line 43; `append` in loop at lines 89-94 causes ~13 reallocs for 5000 entries (geometric growth) | -- | Added `ensureTotalCapacity(min(file_size / 40, max_entries))` before load loop | Resolved |
| ~~13~~ | PF-035 | P3 | 20 | apt-get install runs in every CI job (~2-3.5min aggregate overhead) | .gitlab-ci.yml:49 | `apt-get update && apt-get install -y curl xz-utils` in `.install-zig` anchor; runs in every job using the anchor | -- | Moved apt-get inside cache guard with `command -v` check; runs only when needed | Resolved |
| 14 | PF-014 | Info | -- | Entire history file read into memory | history.zig | `allocator.alloc(u8, file_size)` for full file; bounded by 64MB check | -- | Read from end of file; or stream-parse lines | Deferred |
| 15 | PF-013 | Info | -- | No benchmark suite | -- | No benchmark infrastructure exists | -- | Add `zig build bench` target with key scenarios | Deferred |
| 16 | PF-023 | Info | -- | handleSearch() direct stdout writes (1 syscall/keystroke + 1 on search entry) | core.zig:747,795 | `stdout.writeAll` at line 747 runs once on search entry (not per keystroke); line 795 writes search result display once per keystroke. Actual per-keystroke cost is 1 unbuffered write, not 2 | -- | Buffer search output into a stack buffer and flush once per keystroke | Deferred |
| 17 | PF-029 | Info | -- | appendToMultiLine no pre-allocate for continuation buffer | core.zig:478-486 | `appendSlice` without prior `ensureTotalCapacity`; each continuation triggers potential reallocs in multi_line_buffer | -- | Pre-allocate with `ensureTotalCapacity(input.len + 1)` before append | Deferred |
| 18 | PF-030 | Info | -- | search_buffer starts at capacity 0 | core.zig:181 | `initCapacity(opts.allocator, 0)` for search_buffer; every search keystroke triggers realloc growth | -- | Pre-allocate 64-128 bytes at init (typical search queries are short) | Deferred |
| ~~19~~ | PF-031 | Info | -- | ReplState buffers start at capacity 0 | core.zig | All ArrayList fields initialized with `initCapacity(allocator, 0)`; first use triggers realloc | -- | Won't Do -- pre-allocating would change `initCapacity(allocator, 0) catch unreachable` to fallible paths for sub-µs first-use realloc gain | Won't Do |
| ~~20~~ | PF-032 | Info | -- | Two writeAll syscalls in history append | history.zig | `file.writeAll(line)` then `file.writeAll("\n")` -- two separate syscalls per history append | -- | Combined into single `writev` syscall using iovec array: `[line, "\n"]` | Resolved |
| ~~21~~ | PF-033 | Info | -- | shouldUseColor() 2 getenv + 1 isatty per TerminalWriter init | platform.zig | `getenv("NO_COLOR")`, `getenv("TERM")`, `isStdoutTty()` called in `shouldUseColor()` | -- | Won't Do -- shouldUseColor is called during TerminalWriter.init() (once at startup), not per-keystroke; caching adds complexity for zero runtime benefit | Won't Do |
| ~~22~~ | PF-034 | Info | -- | Config.loadFromFile no pre-size-check for readToEndAlloc | config.zig | `file.readToEndAlloc(allocator, 1024 * 1024)` reads without checking file size first | -- | Won't Do -- stdlib `readToEndAlloc` already handles internal buffering and allocation; pre-checking adds a syscall for negligible memory savings on small config files | Won't Do |
| ~~23~~ | PF-036 | Info | -- | Build job missing --summary all flag | .gitlab-ci.yml | `zig build` without `--summary all`; no build summary in CI logs | -- | Added `--summary all` to build command at .gitlab-ci.yml:93 | Resolved |
| ~~24~~ | PF-038 | Info | -- | Undo pre-snapshot alloc+free on non-destructive keypresses | core.zig | `allocator.dupe()` runs on every keypress; freed immediately for non-destructive actions. Cost ~100-300ns per wasted cycle | -- | Won't Do -- snapshot must precede handleKey which modifies buffer directly; conditional dupe would require two keymap dispatches or deferred snapshot for sub-µs gain | Won't Do |
| ~~25~~ | PF-039 | Info | -- | UndoStack orderedRemove(0) at capacity | undo.zig | `orderedRemove(0)` shifts up to 99 entries (~2.4KB) when stack is full; ~100-200ns. L1-cache-resident. **Re-filed Cycle 3 as PF-048 (P3, [#132](https://gitlab.com/devnw/zig/repl/-/issues/132))** with a confirmed every-~100-keystroke steady-state cadence; PF-039 stays Won't Do at Info, PF-048 tracks the structural fix at P3 | -- | Won't Do -- orderedRemove is correct for LIFO undo semantics (oldest entry evicted); L1-cache-resident data is 50-100x cheaper than any syscall. See PF-048 for the tracked structural fix | Won't Do |
| ~~26~~ | PF-040 | Info | -- | No SIGWINCH handler (enabler for PF-021) | platform.zig | Signal infrastructure existed for SIGTERM/SIGHUP but SIGWINCH was not registered | -- | Registered SIGWINCH handler in installTerminalSignalHandlers; sets `terminal_resized` flag; removed in removeTerminalSignalHandlers | Resolved |
| 27 | PF-042 | Info | -- | generateFilePathCandidates sorts <=256 candidates | completion.zig | `std.mem.sort` on up to 256 candidates; O(n log n) where n<=256; ~1-5µs; runs once per Tab press | -- | No action warranted. Sort provides consistent user-facing ordering | Deferred |
| 28 | PF-045 | Info | -- | compat.Mutex spinlock in single-threaded REPL | compat.zig | `compat.Mutex` lock/unlock performs atomic CAS + memory fence; the REPL is single-threaded so this is zero-correctness-benefit work on every locked section | [#129](https://gitlab.com/devnw/zig/repl/-/issues/129) | Provide a no-op Mutex shim for the single-threaded build, or remove the lock where provably single-threaded | Open |
| 29 | PF-049 | Info | -- | 3 sequential writeAll syscalls per stderr error/warning message | core.zig | error/warning emit path issues 3 sequential `compat.writeAll` syscalls per message; cold path (error reporting), not per-keystroke | [#134](https://gitlab.com/devnw/zig/repl/-/issues/134) | Batch the message into one stack-buffered `writeAll` | Open |
| 30 | PF-050 | Info | -- | TerminalWriter.writeError/Warning/Success 6+ syscalls per colored message | platform.zig | colored status messages issue 6+ `compat.writeAll` syscalls (color-on + text + reset, per segment); cold path (status/error output), not per-keystroke | [#135](https://gitlab.com/devnw/zig/repl/-/issues/135) | Batch color+text+reset into a single stack-buffered `writeAll` per message | Open |
| ~~31~~ | PF-052 | Info | -- | UndoStack retained bytes uncapped (100 × line_len) | undo.zig | The undo stack caps entry count (100) but not retained bytes; worst case ~100 × line_len held. For a pathological multi-MB single line this is 100x that line in memory | -- | Won't Do -- bounding bytes adds eviction-policy complexity; interactive line lengths make worst-case retained memory negligible, and the entry-count cap already bounds growth | Won't Do |
| ~~32~~ | PF-024 | Info | -- | CI re-downloads Zig on every job (no caching) | .gitlab-ci.yml:36-73 | `curl -fsSL` downloads Zig tarball in every CI job; no `cache:` directive | -- | Global `cache:` block added with `key: zig-${ZIG_VERSION}` and `paths: [zig-${ZIG_VERSION}/]` | Resolved |

### Resolved Findings

| PF-ID | Severity | PerfScore | Finding | Component | Resolution | Resolved In |
|-------|----------|-----------|---------|-----------|------------|-------------|
| PF-043 | P3 | 30 | Per-keystroke unconditional undo snapshot dupe | core.zig:378 | Undo snapshot made lazy: a conservative `keyMayMutate` predictor takes the pre-edit buffer dupe only for keys that can mutate the buffer. Pure cursor moves / history-nav now perform ZERO buffer dupes; no-op edits (backspace-at-BOL, delete-at-EOL) skip dead undo entries by comparing snapshot vs post-action buffer. Exhaustive guard test proves the predictor never under-predicts a mutating key; zero-dupe property verified by counting-allocator test. Realizes the optimization PF-038 had declined as too costly. | Audit Cycle 3 (commit d039c05) |
| PF-004 | P2 | 48 | File open/close per history append (6 syscalls/append) | history.zig | Added persistent `append_handle: ?std.fs.File`; lazily opened on first append, reused for subsequent appends; closed in deinit() and reset in clear(). Syscalls reduced from 6 to 2 per append. 3 tests added. | Phase 14 (Gap Closure) |
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
| PF-009 | P3 | 20 | Redundant buffer scan (calculateVisualLines + calculateCursorPosition) | render.zig, core.zig | Added `calculateRenderInfo()` single-pass function returning `RenderInfo{visual_lines, cursor_pos}`; core.zig renderPrompt uses single call instead of two separate functions | Phase 15 (Gap Closure) |
| PF-011 | P3 | 24 | Per-candidate alloc/free churn in completion | completion.zig, core.zig | Added `arena: std.heap.ArenaAllocator` to CompletionContext; `addCandidate` uses arena; `reset()` uses `arena.reset(.retain_capacity)` — O(1) instead of N frees | Phase 15 (Gap Closure) |
| PF-021 | P3 | 25 | getTerminalWidth() ioctl syscall on every renderPrompt | platform.zig | Cached terminal width with SIGWINCH invalidation; `terminal_resized` flag set by signal handler; getTerminalWidth() returns cached value when valid | Phase 15 (Gap Closure) |
| PF-022 | P3 | 20 | Global dedup orderedRemove(i) in while loop O(k*n) | history.zig | Replaced with O(n) single-pass compacting: forward scan with write_idx, free duplicates in-place, shrinkRetainingCapacity | Phase 15 (Gap Closure) |
| PF-026 | P3 | 15 | History search re-scans all entries per keystroke | search.zig | Changed `null` to `state.history_index` in searchBackward call; search resumes from last match position | Phase 15 (Gap Closure) |
| PF-032 | Info | -- | Two writeAll syscalls in history append | history.zig | Combined into single `writev` syscall using iovec array | Phase 15 (Gap Closure) |
| PF-036 | Info | -- | Build job missing --summary all flag | .gitlab-ci.yml | Added `--summary all` to build command | Phase 15 (Gap Closure) |
| PF-040 | Info | -- | No SIGWINCH handler (enabler for PF-021) | platform.zig | Registered SIGWINCH handler in installTerminalSignalHandlers; sets `terminal_resized` flag; removed in removeTerminalSignalHandlers | Phase 15 (Gap Closure) |

### Won't Do

| PF-ID | Severity | Finding | Reason |
|-------|----------|---------|--------|
| PF-025 | Info | Byte-by-byte writeAll to fixedBufferStream in render loop | Won't Do -- in-memory fixedBufferStream writes are sub-microsecond (~200-500ns for 100-char line); batching adds complexity for negligible gain |
| PF-031 | Info | ReplState buffers start at capacity 0 | Won't Do -- pre-allocating would change `initCapacity(allocator, 0) catch unreachable` to fallible paths; sub-µs first-use realloc cost |
| PF-033 | Info | shouldUseColor() 2 getenv + 1 isatty per TerminalWriter init | Won't Do -- called once at TerminalWriter.init() (startup), not per-keystroke; caching adds complexity for zero runtime benefit |
| PF-034 | Info | Config.loadFromFile no pre-size-check for readToEndAlloc | Won't Do -- stdlib `readToEndAlloc` already handles internal buffering; pre-checking adds a syscall for negligible memory savings on small configs |
| PF-038 | Info | Undo pre-snapshot alloc+free on non-destructive keypresses | Won't Do -- snapshot must precede handleKey which modifies buffer directly; conditional dupe requires two keymap dispatches for sub-µs gain |
| PF-039 | Info | UndoStack orderedRemove(0) at capacity | Won't Do -- orderedRemove is correct for LIFO undo semantics (oldest entry evicted); L1-cache-resident data (~2.4KB) is 50-100x cheaper than any syscall. Structural fix tracked separately as PF-048 (P3, [#132](https://gitlab.com/devnw/zig/repl/-/issues/132)) |
| PF-052 | Info | UndoStack retained bytes uncapped (100 × line_len) | Won't Do -- bounding retained bytes adds eviction-policy complexity; the entry-count cap (100) already bounds growth, and interactive line lengths make worst-case retained memory negligible |

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
| PF-004 | P2 | 48 | history.zig | File open/close per history append (rescored 55->48) | Resolved |
| PF-005 | P2 | 50 | platform.zig | Multi-write newline conversion | Resolved |
| PF-016 | P2 | 50 | core.zig | delete_to_bol heap allocation | Resolved |
| PF-006 | P2 | 45 | platform.zig | Multi-write ANSI sequences | Resolved |
| PF-017 | P2 | 40 | core.zig | Paste buffer 4096 silent truncation | Resolved |
| PF-008 | P3 | 35 | core.zig | orderedRemove in word deletion loop | Resolved |
| PF-018 | P3 | 35 | core.zig | appendHistoryFiltered per-byte append | Resolved |
| PF-009 | P3 | 20 | render.zig | Redundant dual buffer scan (rescored 30->20) | Resolved |
| PF-011 | P3 | 24 | completion.zig | Per-candidate allocation churn (rescored 30->24) | Resolved |
| PF-019 | P3 | 30 | core.zig | Render buffer 8192 silent truncation | Resolved |
| PF-021 | P3 | 25 | platform.zig, core.zig | getTerminalWidth() ioctl per renderPrompt | Resolved |
| PF-010 | P3 | 25 | history.zig | orderedRemove(0) on append overflow | Deferred |
| PF-022 | P3 | 20 | history.zig | Global dedup orderedRemove in while loop O(k*n) | Resolved |
| PF-025 | Info | -- | core.zig | Byte-by-byte writeAll to fixedBufferStream (reclassified P3->Info) | Won't Do |
| PF-026 | P3 | 15 | search.zig, history.zig | History search re-scans from history_index | Resolved |
| PF-020 | P3 | 15 | core.zig | reverse_tab orderedRemove x4 | Resolved |
| PF-028 | P3 | 25 | history.zig | History load() dupes all lines then frees excess | Resolved |
| PF-027 | P3 | 20 | history.zig | History ArrayList no preallocation during load() | Resolved |
| PF-014 | Info | -- | history.zig | Full history file read into memory | Deferred |
| PF-023 | Info | -- | core.zig | handleSearch() direct stdout writes (1 syscall/keystroke + 1 on entry) | Deferred |
| PF-029 | Info | -- | core.zig | appendToMultiLine no pre-allocate | Deferred |
| PF-030 | Info | -- | core.zig | search_buffer starts at capacity 0 | Deferred |
| PF-031 | Info | -- | core.zig | ReplState buffers start at capacity 0 | Won't Do |
| PF-032 | Info | -- | history.zig | Two writeAll syscalls in history append | Resolved |
| PF-033 | Info | -- | platform.zig | shouldUseColor() 2 getenv + 1 isatty per TerminalWriter | Won't Do |
| PF-034 | Info | -- | config.zig | Config.loadFromFile no pre-size-check | Won't Do |
| PF-038 | Info | -- | core.zig | Undo pre-snapshot alloc+free on non-destructive keypresses | Won't Do |
| PF-039 | Info | -- | undo.zig | UndoStack orderedRemove(0) at capacity | Won't Do |
| PF-040 | Info | -- | platform.zig | SIGWINCH handler (enabler for PF-021) | Resolved |
| PF-042 | Info | -- | completion.zig | generateFilePathCandidates sorts <=256 candidates (negligible) | Deferred |
| PF-043 | P3 | 30 | core.zig | Per-keystroke unconditional undo snapshot dupe (now lazy via keyMayMutate) | Resolved |
| PF-044 | P3 | 16 | core.zig | defaultIo() fat Io struct per call (~28 sites incl. render path; suspected fold) | Open |
| PF-045 | Info | -- | compat.zig | compat.Mutex spinlock (atomic CAS + fence) in single-threaded REPL | Open |
| PF-046 | P3 | 20 | history.zig | file.length() extra syscall before every history append | Open |
| PF-047 | P3 | 16 | history.zig | Heap alloc+free per history append for newline concat | Open |
| PF-048 | P3 | 24 | undo.zig | UndoStack orderedRemove(0) O(n) memmove on eviction (~every 100 keystrokes) | Open |
| PF-049 | Info | -- | core.zig | 3 sequential writeAll syscalls per stderr error/warning message | Open |
| PF-050 | Info | -- | platform.zig | TerminalWriter.writeError/Warning/Success 6+ syscalls per colored message | Open |
| PF-051 | Info | -- | search.zig, history.zig | searchBackward re-scans history per search keystroke (O(N·patternlen)) | Deferred |
| PF-052 | Info | -- | undo.zig | UndoStack retained bytes uncapped (100 × line_len) | Won't Do |

### Infrastructure (`area::infra`)

| PF-ID | Severity | Score | File | Summary | Status |
|-------|----------|-------|------|---------|--------|
| PF-035 | P3 | 20 | .gitlab-ci.yml | apt-get install runs in every CI job | Resolved |
| PF-012 | Info | -- | .gitlab-ci.yml | No build/test CI stage | Resolved |
| PF-013 | Info | -- | build.zig | No benchmark suite | Deferred |
| PF-024 | Info | -- | .gitlab-ci.yml | CI re-downloads Zig on every job (no caching) | Resolved |
| PF-036 | Info | -- | .gitlab-ci.yml | Build job missing --summary all flag | Resolved |

---

## Roadmap

### Quick Wins (< 1 day)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-009 | 20 | Merged into `calculateRenderInfo()` single-pass in render.zig; core.zig uses single call | 1-2 hours | Resolved |
| PF-021 | 25 | Cached terminal width with SIGWINCH invalidation in platform.zig | 2-3 hours | Resolved |
| PF-027 | 20 | Added `ensureTotalCapacity(min(file_size / 40, max_entries))` before history load loop | 30 min | Resolved |
| PF-029 | -- | Pre-allocate multi_line_buffer with `ensureTotalCapacity(input.len + 1)` before append | 15 min | Deferred |
| PF-025 | -- | Batch contiguous printable character runs into single writeAll calls in render loop (reclassified P3->Info) | 1-2 hours | Deferred |
| PF-026 | 15 | Changed `null` to `state.history_index` in searchBackward call at search.zig:82 | 30 min | Resolved |
| PF-042 | -- | No action warranted. O(n log n) sort on <=256 items at completion.zig:270-276 is ~1-5us per Tab press | -- | Deferred |
| PF-030 | -- | Pre-allocate search_buffer with 64-128 bytes at init | 15 min | Deferred |
| PF-031 | -- | Pre-allocate ReplState buffers with reasonable defaults (buffer=256, kill_ring=128, etc.) | 30 min | Deferred |
| PF-032 | -- | Combined into single `writev` syscall using iovec array | 30 min | Resolved |
| PF-033 | -- | shouldUseColor() is init-only, not per-keystroke | -- | Won't Do |
| PF-034 | -- | stdlib readToEndAlloc already optimizes internally | -- | Won't Do |
| PF-039 | -- | orderedRemove correct for LIFO undo; L1-cache data | -- | Won't Do |
| PF-040 | -- | Registered SIGWINCH handler alongside SIGTERM/SIGHUP | 1-2 hours | Resolved |
| PF-036 | -- | Added `--summary all` to build command in .gitlab-ci.yml | 5 min | Resolved |
| PF-043 | 30 | Lazy undo snapshot via `keyMayMutate` predictor; zero dupes on cursor moves / history nav; no-op edits skip dead entries | 1 day | Resolved |
| PF-046 | 20 | Track write offset in-process; drop the per-append `file.length()` syscall | 1 hour | Open |
| PF-047 | 16 | Replace newline-concat alloc with `writev` iovec `[line, "\n"]` (mirrors PF-032) | 30 min | Open |
| PF-049 | -- | Batch 3 stderr writeAll calls into one stack-buffered write | 30 min | Open |
| PF-050 | -- | Batch color+text+reset into one writeAll per colored message | 1 hour | Open |
| PF-045 | -- | No-op Mutex shim for single-threaded build (or remove provably-single-threaded locks) | 1-2 hours | Open |
| PF-044 | 16 | Cache a single `Io` instance, OR confirm via disassembly the construction is folded and close | 1-2 hours | Open |
| PF-051 | -- | Memoize last search match span / short-circuit on query extension | 2-4 hours | Deferred |
| PF-052 | -- | Cap UndoStack retained bytes -- declined (entry-count cap suffices) | -- | Won't Do |

### Medium Effort (1-5 days)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-004 | 48 | Persistent file handle for history; lazily opened on first append, reused for subsequent appends. Syscalls reduced from 6 to 2 per append. 3 tests added. | 1 day | Resolved |
| PF-028 | 25 | Two-pass approach: count lines, skip `total - max_entries` before allocating | 2-4 hours | Resolved |
| PF-035 | 20 | Moved apt-get inside cache guard with `command -v` check | 2-4 hours | Resolved |
| PF-017 | 40 | Flush-and-continue: paste buffer flushes to edit buffer when full | 1-2 days | Resolved |
| PF-019 | 30 | buffer_full flag stops writes on overflow; cursor positioning skipped | 1 day | Resolved |
| PF-022 | 20 | Replaced with O(n) single-pass compacting dedup | 1 hour | Resolved |
| PF-024 | -- | Add GitLab CI `cache:` directive for Zig installation directory | 1-2 hours | Resolved |
| PF-014 | -- | Stream history file or read from end | 2-3 days | Deferred |

### Strategic (> 5 days)

| PF-ID | Score | Fix | Effort | Status |
|-------|-------|-----|--------|--------|
| PF-011 | 24 | Arena allocator for completion lifecycle. ArenaAllocator field in CompletionContext; reset(.retain_capacity) in reset() | 2 hours | Resolved |
| PF-010 | 25 | Ring buffer for history or swap-remove with sort | 3-5 days | Deferred |
| PF-048 | 24 | Ring buffer (head/tail indices) or swap-out eviction for UndoStack to drop the O(n) memmove | 3-5 days | Open |
| PF-013 | -- | Benchmark suite (render, paste, history, completion) | 3-5 days | Deferred |
| PF-023 | -- | Buffer search mode output into stack buffer; single flush per keystroke. Corrected: 1 write/keystroke + 1 on search entry (not 2/keystroke) | 1 day | Deferred |

---

## Tracked Issues

| PF-ID | Severity | Issue URL | Status |
|-------|----------|-----------|--------|
| PF-001 | P0 | [#42](https://gitlab.com/devnw/zig/repl/-/issues/42) | Resolved |
| PF-002 | P1 | [#44](https://gitlab.com/devnw/zig/repl/-/issues/44) | Resolved |
| PF-003 | P1 | [#47](https://gitlab.com/devnw/zig/repl/-/issues/47) | Resolved |
| PF-015 | P1 | [#67](https://gitlab.com/devnw/zig/repl/-/issues/67) | Resolved |
| PF-004 | P2 | [#66](https://gitlab.com/devnw/zig/repl/-/issues/66) | Resolved |
| PF-010 | P3 | [#69](https://gitlab.com/devnw/zig/repl/-/issues/69) | Deferred |
| PF-011 | P3 | [#70](https://gitlab.com/devnw/zig/repl/-/issues/70) | Resolved |
| PF-009 | P3 | [#68](https://gitlab.com/devnw/zig/repl/-/issues/68) | Resolved |
| PF-012 | Info | [#1](https://gitlab.com/devnw/zig/repl/-/issues/1), [#71](https://gitlab.com/devnw/zig/repl/-/issues/71) | Resolved |
| PF-013 | Info | [#77](https://gitlab.com/devnw/zig/repl/-/issues/77) | Deferred |
| PF-014 | Info | [#78](https://gitlab.com/devnw/zig/repl/-/issues/78) | Deferred |
| PF-044 | P3 | [#128](https://gitlab.com/devnw/zig/repl/-/issues/128) | Open |
| PF-045 | Info | [#129](https://gitlab.com/devnw/zig/repl/-/issues/129) | Open |
| PF-046 | P3 | [#130](https://gitlab.com/devnw/zig/repl/-/issues/130) | Open |
| PF-047 | P3 | [#131](https://gitlab.com/devnw/zig/repl/-/issues/131) | Open |
| PF-048 | P3 | [#132](https://gitlab.com/devnw/zig/repl/-/issues/132) | Open |
| PF-049 | Info | [#134](https://gitlab.com/devnw/zig/repl/-/issues/134) | Open |
| PF-050 | Info | [#135](https://gitlab.com/devnw/zig/repl/-/issues/135) | Open |

*Note: most P3/Info backlog findings carry no GitLab issue (tracked in this doc only). Audit Cycle 3 reconciled the seven perf issues #128--#132, #134, #135 that were filed independently -- each now carries its PF-ID in an issue comment. PF-043 (resolved this cycle) was a deep-review finding fixed inline (commit d039c05) and has no standalone issue. PF-051 and PF-052 are doc-tracked only.*

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-12 (Audit Cycle 3 -- Re-review) | Re-review on branch `audit-cycle-3-gap-closure`. **1 resolved:** PF-043 (P3, new ID) -- per-keystroke unconditional undo snapshot dupe (core.zig:378) made lazy via a conservative `keyMayMutate` predictor; pure cursor moves / history-nav now perform ZERO buffer dupes, and no-op edits (backspace-at-BOL, delete-at-EOL) skip dead undo entries; verified by counting-allocator + exhaustive predictor-guard tests (commit d039c05). PF-043 realizes the optimization PF-038 had declined; PF-038 stays Won't Do as originally scoped. **9 new findings recorded (all LOW/INFO/P3 backlog, none P0/P1):** PF-044 (P3, suspected -- defaultIo() fat Io struct per call, ~28 sites incl. render path; optimizer may fold; #128), PF-045 (Info -- compat.Mutex spinlock in single-threaded REPL; #129), PF-046 (P3 -- file.length() extra syscall per history append; #130), PF-047 (P3 -- heap alloc/free per history append for newline concat; #131), PF-048 (P3 -- UndoStack orderedRemove(0) O(n) eviction every ~100 keystrokes; #132; structural twin of the Won't-Do PF-039), PF-049 (Info -- 3x stderr writeAll per error message; #134), PF-050 (Info -- TerminalWriter 6+ syscalls per colored message; #135), PF-051 (Info, Deferred -- searchBackward per-keystroke re-scan O(N·patternlen)), PF-052 (Info, Won't Do -- UndoStack uncapped retained bytes). GitLab issues #128--#132, #134, #135 reconciled (PF-ID cross-references added as comments; **no duplicate issues created**). Severity distribution updated: 50 total, 15 open (5 P3, 10 Info), 28 resolved, 7 won't do. Overall posture remains Strong/Production-Ready; the only per-keystroke hot-path allocation (undo snapshot) was eliminated this cycle. |
| 2026-03-25 (Phase 14 -- Gap Closure) | **PF-004 resolved.** Added persistent `append_handle: ?std.fs.File` field to history.zig; lazily opened on first append, reused for subsequent appends; closed in deinit() and reset in clear(). Syscalls reduced from 6 to 2 per history append (write+write). 3 tests added. GitLab issue #66 closed. Severity distribution updated: 40 total, 21 open (0 P2, 6 P3, 15 Info), 19 resolved. All other findings unchanged. |
| 2026-03-25 (Phase 13 -- Audit Cycle 2, Phase 4) | Audit Cycle 2 perf-reviewer confirmation pass. All 22 open findings confirmed accurately classified. **Score adjustments:** PF-004 rescored 55->48 (6 syscalls run once per Enter key, not per keystroke; Impact 4 x Likelihood 3 x 4 = 48). PF-011 rescored 30->24 (256 alloc/free at ~25-50us total, once per Tab press; Impact 3 x Likelihood 2 x 4 = 24). **Description correction:** PF-023 corrected -- line 747 `stdout.writeAll` runs once on search entry, not per keystroke; actual per-keystroke cost is 1 write (line 795), not 2. **No new findings, no regressions, no GitLab issue changes.** Severity distribution unchanged: 40 total, 22 open (1 P2, 6 P3, 15 Info), 18 resolved. Overall posture confirmed Strong/Production-Ready. |
| 2026-03-25 (Phase 12 review) | Phase 12 review: 0 new findings, 0 score adjustments, 0 regressions. All 22 open findings re-verified and confirmed still present and accurately described. **PF-004 evidence updated:** SF-024 security fix added +1 chmod syscall per history append (now 6 syscalls/append: open+write+write+chmod+close+fsync, up from 5). This further strengthens the case for a persistent file handle. **Overall posture:** Strong/Production-Ready for interactive REPL use. Keystroke-to-render latency ~5-20us (500-2000x below human perception threshold). **No GitLab issue changes** -- no issues created, updated, or closed. Severity distribution unchanged: 40 total, 22 open (1 P2, 6 P3, 15 Info), 18 resolved. |
| 2026-03-24 (Phase 11 review) | Phase 11 review: 1 finding merged, 1 new Info finding added, 0 regressions. **PF-041 merged into PF-026:** handleSearch at search.zig:57 passes `null` to `searchBackward()`, causing full history re-scan from end on every keystroke. This is the specific root cause of PF-026. Fix: pass `state.history_index` as `start_index` to resume from last match position. PF-026 evidence updated (core.zig:782 -> search.zig:57, history.zig:236-239). **PF-042 (NEW, Info):** `generateFilePathCandidates` at completion.zig:270-276 sorts all candidates after directory iteration. O(n log n) on <=256 items (MAX_FILE_CANDIDATES), single-digit microseconds, runs once per Tab press. No action warranted. **Verification:** All 18 resolved findings verified with no regressions. Updated severity distribution (40 total, 22 open, 18 resolved; Info open 14->15). No GitLab issues created (both Info-level or existing). |
| 2026-03-24 (Phase 10 review) | Phase 10 review: 2 new Info findings added, 2 severity adjustments. **New findings:** PF-039 (Info) -- UndoStack orderedRemove(0) at capacity shifts ~99 entries (~2.4KB), ~100-200ns per destructive keypress, L1-cache-resident and 50-100x cheaper than any syscall. PF-040 (Info) -- No SIGWINCH handler; signal infrastructure exists for SIGTERM/SIGHUP but SIGWINCH not registered; prerequisite enabler for PF-021 terminal width caching; no standalone perf impact. **Severity adjustments:** PF-009 rescored 30->20 (P3): dual buffer scan adds ~40-160ns for typical lines, <1% of keystroke latency; score 30 overstated impact but fix remains worthwhile. PF-025 reclassified P3 (Score 15)->Info: "byte-by-byte writeAll" targets in-memory fixedBufferStream, not file descriptor; per-byte overhead ~2-5ns function-call cost, ~200-500ns total for 100-char line; not an I/O problem. No GitLab issues created (all Info/P3 level). Updated severity distribution (39 total, 21 open, 18 resolved). |
| 2026-03-24 (Phase 9 audit) | Phase 9 audit: added PF-038 (Info) -- undo pre-snapshot alloc+free on non-destructive keypresses. Originally flagged as P2 by Phase 2 scanner, downgraded to Info by Phase 3 deep reviewer. Absolute cost ~100-300ns per non-destructive keypress; terminal I/O syscalls are 100-1000x more expensive. Persistent shadow buffer fix adds complexity for near-zero gain. No GitLab issue created (Info-level). Updated severity distribution (37 total, 19 open, 18 resolved). Corrected pre-existing count errors: P2 resolved 6->5 (total 7->6), P3 open/resolved 6/8->7/7. |
| 2026-03-24 (Phase 10) | Phase 10 performance review: added 10 new findings (PF-027 through PF-036). 3 P3 findings: PF-027 (history ArrayList no preallocation, Score 20), PF-028 (history load dupes all lines then frees excess, Score 25), PF-035 (apt-get install in every CI job, Score 20). 7 Info findings: PF-029 (appendToMultiLine no pre-allocate), PF-030 (search_buffer capacity 0), PF-031 (ReplState buffers capacity 0), PF-032 (two writeAll syscalls in history append), PF-033 (shouldUseColor 2 getenv + 1 isatty), PF-034 (Config.loadFromFile no pre-size-check), PF-036 (build job missing --summary all). No GitLab issues created -- all findings are P3/Info backlog. Updated severity distribution (37 total, 20 open, 17 resolved), top 5 risks, roadmap. |
| 2026-03-24 (Phase 6) | Phase 6 re-audit: resolved PF-012 (CI now has build + 4 test stages + fuzz). Added 6 new findings: PF-021 (ioctl per render), PF-022 (global dedup O(k*n)), PF-023 (search mode direct stdout writes), PF-024 (CI Zig re-download), PF-025 (byte-by-byte fixedBufferStream writes), PF-026 (history search full re-scan per keystroke). Updated severity distribution, roadmap split into Quick Wins / Medium / Strategic tiers. No new GitLab issues -- all new findings are P3/Info backlog. |
| 2026-03-24 (post-closure) | Phase 5 gap closure: resolved PF-015 (replaceRange for vi word ops), PF-016 (replaceRange for delete_to_bol), PF-018 (ensureTotalCapacity for history filter), PF-020 (replaceRange for reverse_tab). Updated PF-009 component from core.zig to render.zig. Updated severity distribution, roadmap, and status for all remaining items. |
| 2026-03-24 | Phase 4 re-audit: marked 7 findings resolved (PF-001, PF-002, PF-003, PF-005, PF-006, PF-007, PF-008). Added 6 new findings (PF-015 through PF-020). Updated severity distribution, roadmap, and recommended fix order. |
| 2026-03-23 | Phase 3 initial scoring and issue tracking: 14 findings identified and scored. Issues created for P0-P1 items. |
