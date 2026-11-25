# Audit Cycle 4 Gap Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all remaining bug/gap findings from the 2026-06-12 full audit of devnw/zig/repl (security residuals, high quality bugs, test hardening, docs) so the next `/security:appsec-review` and `/codepros:audit` passes find nothing new.

**Architecture:** Surgical fixes to the existing Zig 0.16 readline library — no new modules. Security fixes harden the three display/ingest boundaries (history ingest filter, render loop, paste sanitizer) with UTF-8-aware C1 neutralization that only ever shrinks output (preserving the `appendAssumeCapacity` invariant). Quality fixes wire dormant config, fix undo coverage, and centralize duplicated logic. Tests move to `std.testing.tmpDir` isolation.

**Tech Stack:** Zig 0.16.0 (`zig build test --summary all` must stay green, 318+ tests), `glab` CLI for issue closure, pre-commit hooks active.

**Repo:** `/data/home/benji/src/gl/gitlab.com/devnw/zig/repl`, branch `main` @ `69b9d65` (v0.1.9). Working tree must be clean before starting. **Line numbers below were verified at `69b9d65` but earlier tasks shift later files — always re-locate by symbol name, not line number.**

**Verification command for every task:** `zig build test --summary all` (expect: all pass, 1 skipped otel smoke) and `zig fmt --check src/ tests/ examples/ build.zig` (expect: exit 0).

---

### Task 1: C1 control-byte neutralization in history ingest filter (GitLab issue to be filed as GAP-0074; APPSEC-02 residual)

The history ingest filter `appendHistoryFiltered` (src/text_utils.zig:230-238) drops C0/DEL but passes raw C1 bytes (0x80–0x9F) and UTF-8-encoded C1 codepoints (U+0080–U+009F, bytes `0xC2 0x80`–`0xC2 0x9F`) straight through. On C1-honoring terminals these are 8-bit CSI/OSC/DCS introducers → escape injection. Fix: UTF-8-aware walk that drops invalid bytes and C1 codepoints. Output ≤ input always, so `ensureTotalCapacity(items.len + entry.len)` + `appendAssumeCapacity` stays sound.

**Files:**
- Modify: `src/text_utils.zig` (function `appendHistoryFiltered`, ~line 230; tests at end of control-char section)

- [ ] **Step 1: Write the failing tests** (append after the existing `appendHistoryFiltered strips control characters` test in `src/text_utils.zig`):

```zig
test "appendHistoryFiltered strips raw C1 control bytes (8-bit CSI/OSC)" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // Raw (non-UTF-8) C1 bytes: 0x9B (CSI), 0x9D (OSC), 0x9C (ST), 0x90 (DCS).
    // e.g. "\x9d0;pwned\x9c" is an 8-bit OSC title-set sequence.
    try appendHistoryFiltered(&buffer, allocator, "a\x9d0;pwned\x9cb\x9b31mc\x90d");
    try std.testing.expectEqualStrings("a0;pwnedb31mcd", buffer.items);
}

test "appendHistoryFiltered strips UTF-8-encoded C1 codepoints" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // U+009B encoded as UTF-8 (0xC2 0x9B) decodes to C1 CSI on UTF-8 terminals.
    try appendHistoryFiltered(&buffer, allocator, "a\xc2\x9b31mb");
    try std.testing.expectEqualStrings("a31mb", buffer.items);
}

test "appendHistoryFiltered preserves valid multi-byte UTF-8" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // é (U+00E9, 0xC3 0xA9), 日 (U+65E5, 3 bytes), emoji (4 bytes) must survive.
    try appendHistoryFiltered(&buffer, allocator, "caf\xc3\xa9 \xe6\x97\xa5 \xf0\x9f\x98\x80");
    try std.testing.expectEqualStrings("caf\xc3\xa9 \xe6\x97\xa5 \xf0\x9f\x98\x80", buffer.items);
}

test "appendHistoryFiltered output never exceeds input length (invariant)" {
    const allocator = std.testing.allocator;
    // Property guard for the appendAssumeCapacity reservation (APPSEC-04):
    // the filter must only ever DROP bytes, never expand.
    const inputs = [_][]const u8{
        "plain", "\x9b\x9c\x9d", "\xc2\x9b", "\xff\xfe", "a\x1bb", "\xc3\xa9", "",
    };
    for (inputs) |input| {
        var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer buffer.deinit(allocator);
        try appendHistoryFiltered(&buffer, allocator, input);
        try std.testing.expect(buffer.items.len <= input.len);
    }
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `zig build test --summary all 2>&1 | tail -20`
Expected: FAIL — `appendHistoryFiltered strips raw C1 control bytes` and `strips UTF-8-encoded C1 codepoints` fail (current code passes C1 through). The "preserves valid UTF-8" and invariant tests pass already.

- [ ] **Step 3: Replace `appendHistoryFiltered` implementation**

```zig
/// Append a history entry to the buffer, filtering out unsafe control characters.
/// This prevents terminal injection from crafted history file entries (SF-009).
///
/// UTF-8-aware (GAP-0074 / APPSEC-02): in addition to C0 (except \t, \n) and
/// DEL, this drops:
///   - raw 8-bit C1 control bytes 0x80-0x9F that are not part of a valid
///     UTF-8 sequence (8-bit CSI/OSC/DCS/ST introducers on legacy terminals),
///   - UTF-8-encoded C1 codepoints U+0080-U+009F (0xC2 0x80..0xC2 0x9F),
///   - any other invalid UTF-8 byte.
/// Valid multi-byte UTF-8 sequences pass through unchanged.
///
/// INVARIANT: output length <= entry.len (the filter only drops bytes, never
/// expands). The appendAssumeCapacity calls below rely on this — do not add
/// an expanding transform without switching to bounds-checked append and a
/// larger reservation.
pub fn appendHistoryFiltered(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, entry: []const u8) !void {
    // Pre-allocate to avoid log2(n) reallocs during per-byte append
    try buffer.ensureTotalCapacity(allocator, buffer.items.len + entry.len);
    var i: usize = 0;
    while (i < entry.len) {
        const c = entry[i];
        if (c < 0x80) {
            if (!isUnsafeControlChar(c)) {
                buffer.appendAssumeCapacity(c);
            }
            i += 1;
            continue;
        }
        // Non-ASCII: decode one UTF-8 sequence. Invalid lead bytes (which
        // include raw C1 0x80-0x9F and stray continuation bytes) are dropped.
        const seq_len = std.unicode.utf8ByteSequenceLength(c) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > entry.len) {
            // Truncated sequence at end of input: drop the lead byte.
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(entry[i..][0..seq_len]) catch {
            // Invalid sequence: drop the lead byte and rescan from the next.
            i += 1;
            continue;
        };
        if (cp >= 0x80 and cp <= 0x9F) {
            // UTF-8-encoded C1 control codepoint: drop the whole sequence.
            i += seq_len;
            continue;
        }
        buffer.appendSliceAssumeCapacity(entry[i..][0..seq_len]);
        i += seq_len;
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test --summary all 2>&1 | tail -5`
Expected: PASS (all tests, 1 skipped). Also run `zig fmt --check src/text_utils.zig` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/text_utils.zig
git commit -m "fix(security): drop C1 control bytes in history ingest filter (GAP-0074)"
```

---

### Task 2: C1 neutralization in the render display loop (same GAP-0074; APPSEC-02 residual, display boundary)

`renderPrompt`'s content loop (src/core.zig:358-371) writes any byte `>= 0x20 and != 0x7F` raw — C1 bytes pasted into the buffer render verbatim. Add a shared display-span helper in `text_utils.zig` and use it in the loop. Substituting one `?` for a 1-byte invalid or 2+-byte C1 sequence never expands output, so the 8 KB render buffer math is unchanged.

**Files:**
- Modify: `src/text_utils.zig` (new pub fn + tests)
- Modify: `src/core.zig` (`renderPrompt` content loop, ~line 358)

- [ ] **Step 1: Write the failing test for the helper** (in `src/text_utils.zig`):

```zig
test "displaySpan classifies UTF-8 sequences and C1 bytes" {
    // Valid 2-byte UTF-8 (é): safe, len 2.
    {
        const span = displaySpan("\xc3\xa9x");
        try std.testing.expectEqual(@as(usize, 2), span.len);
        try std.testing.expect(span.safe);
    }
    // UTF-8-encoded C1 (U+009B): unsafe, len 2 (skip whole sequence).
    {
        const span = displaySpan("\xc2\x9bx");
        try std.testing.expectEqual(@as(usize, 2), span.len);
        try std.testing.expect(!span.safe);
    }
    // Raw C1 byte (0x9B, invalid UTF-8 lead): unsafe, len 1.
    {
        const span = displaySpan("\x9bx");
        try std.testing.expectEqual(@as(usize, 1), span.len);
        try std.testing.expect(!span.safe);
    }
    // Truncated sequence at end: unsafe, len 1.
    {
        const span = displaySpan("\xc3");
        try std.testing.expectEqual(@as(usize, 1), span.len);
        try std.testing.expect(!span.safe);
    }
}
```

- [ ] **Step 2: Run test to verify it fails** (`displaySpan` not defined)

Run: `zig build test --summary all 2>&1 | tail -10`
Expected: compile error — `displaySpan` not found.

- [ ] **Step 3: Implement `displaySpan` in `src/text_utils.zig`** (place next to `isUnsafeControlChar`):

```zig
/// Classification of the next byte sequence for terminal display.
pub const DisplaySpan = struct {
    /// Number of input bytes this span covers (always >= 1).
    len: usize,
    /// True if the bytes are a valid, non-control UTF-8 sequence safe to
    /// write to the terminal verbatim. False for invalid UTF-8 bytes and
    /// C1 control codepoints (U+0080-U+009F) — render a placeholder instead.
    safe: bool,
};

/// Classify the byte sequence starting at `bytes[0]` for display purposes.
/// Callers must only invoke this for lead bytes >= 0x80 (ASCII is handled
/// inline by the render loop). Never returns len == 0.
pub fn displaySpan(bytes: []const u8) DisplaySpan {
    const seq_len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch {
        return .{ .len = 1, .safe = false };
    };
    if (seq_len > bytes.len) return .{ .len = 1, .safe = false };
    const cp = std.unicode.utf8Decode(bytes[0..seq_len]) catch {
        return .{ .len = 1, .safe = false };
    };
    if (cp >= 0x80 and cp <= 0x9F) return .{ .len = seq_len, .safe = false };
    return .{ .len = seq_len, .safe = true };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 5: Rewrite the `renderPrompt` content loop in `src/core.zig`**

Find the loop (search for `Write buffer contents, sanitizing control characters`). Replace the `for (state.buffer.items) |c|` loop with an index-based walk (the surrounding `buffer_full` plumbing stays identical):

```zig
    // Write buffer contents, sanitizing control characters for display.
    // ASCII control chars and DEL render as '?'. Bytes >= 0x80 are decoded
    // as UTF-8: valid non-C1 sequences pass through; raw C1 bytes (0x9B CSI,
    // 0x9D OSC, ...), UTF-8-encoded C1 codepoints, and invalid bytes render
    // as '?' so attacker-controlled buffer content cannot emit 8-bit terminal
    // controls (GAP-0074). Substitution never expands output, so the render
    // buffer reservation is unaffected.
    // If the render buffer fills, stop immediately to avoid broken ANSI sequences.
    if (!buffer_full) {
        var idx: usize = 0;
        while (idx < state.buffer.items.len) {
            const c = state.buffer.items[idx];
            var advance: usize = 1;
            const write_result = if (c == '\n')
                w.writeAll("\r\n")
            else if (c == '\t' or (c >= 0x20 and c < 0x7F))
                w.writeAll(&[_]u8{c})
            else if (c < 0x20 or c == 0x7F)
                // C0 control characters and DEL - show visual indicator
                w.writeAll("?")
            else blk: {
                const span = text_utils.displaySpan(state.buffer.items[idx..]);
                advance = span.len;
                break :blk if (span.safe)
                    w.writeAll(state.buffer.items[idx..][0..span.len])
                else
                    w.writeAll("?");
            };

            write_result catch {
                buffer_full = true;
                break;
            };
            idx += advance;
        }
    }
```

Check the imports at the top of `core.zig`: `text_utils` is already imported (search `@import("text_utils.zig")`); use the existing import alias.

- [ ] **Step 6: Run full tests + fmt**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS. `zig fmt --check src/` → exit 0.
Note: existing render tests assert `?` substitution for C0 — they must still pass unchanged.

- [ ] **Step 7: Commit**

```bash
git add src/text_utils.zig src/core.zig
git commit -m "fix(security): neutralize C1 controls in render display path (GAP-0074)"
```

---

### Task 3: 8-bit / parameterized paste-marker stripping in `sanitizePasteContent` (GAP-0075; APPSEC-03 residual)

`sanitizePasteContent` (src/text_utils.zig:243-265) strips only the literal 6-byte `ESC[200~`/`ESC[201~`. The 8-bit CSI form `\x9b200~`/`\x9b201~` (5 bytes) and zero-padded params (`ESC[0200~`) survive. Extend the scan. Output is compacted in place (≤ input).

**Files:**
- Modify: `src/text_utils.zig` (`sanitizePasteContent` + tests)

- [ ] **Step 1: Write the failing tests** (next to existing `sanitizePasteContent` tests):

```zig
test "sanitizePasteContent strips 8-bit CSI paste markers" {
    const allocator = std.testing.allocator;
    const input = "safe\x9b201~rm -rf ~\x9b200~after";
    const buf = try allocator.dupe(u8, input);
    defer allocator.free(buf);
    const result = sanitizePasteContent(buf);
    try std.testing.expectEqualStrings("saferm -rf ~after", result);
}

test "sanitizePasteContent strips zero-padded paste markers" {
    const allocator = std.testing.allocator;
    const input = "a\x1b[0200~b\x1b[00201~c";
    const buf = try allocator.dupe(u8, input);
    defer allocator.free(buf);
    const result = sanitizePasteContent(buf);
    try std.testing.expectEqualStrings("abc", result);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test --summary all 2>&1 | tail -10` → the two new tests FAIL (markers pass through).

- [ ] **Step 3: Replace `sanitizePasteContent`**

```zig
/// If `data[pos..]` begins a bracketed-paste marker — 7-bit `ESC [` or 8-bit
/// CSI (0x9B) introducer, optional leading zeros, then `200~` or `201~` —
/// return the marker's byte length; otherwise null.
fn pasteMarkerLen(data: []const u8, pos: usize) ?usize {
    var i = pos;
    // Introducer: ESC [ (2 bytes) or 8-bit CSI 0x9B (1 byte).
    if (i + 1 < data.len and data[i] == 0x1b and data[i + 1] == '[') {
        i += 2;
    } else if (i < data.len and data[i] == 0x9b) {
        i += 1;
    } else {
        return null;
    }
    // Optional leading zeros before the parameter (e.g. ESC[0200~).
    while (i < data.len and data[i] == '0' and
        // Keep at least 3 digits available for "200"/"201".
        i + 3 < data.len and data[i + 1] == '2') : (i += 1)
    {}
    // Parameter must be exactly 200 or 201, terminated by '~'.
    if (i + 3 >= data.len) return null;
    if (data[i] != '2' or data[i + 1] != '0') return null;
    if (data[i + 2] != '0' and data[i + 2] != '1') return null;
    if (data[i + 3] != '~') return null;
    return (i + 4) - pos;
}

/// Sanitize paste content by stripping embedded bracketed-paste markers.
/// This prevents pastejacking attacks where malicious content embeds fake
/// bracketed paste start/end markers to break out of paste mode. Recognizes
/// both the canonical 7-bit `ESC[200~`/`ESC[201~` forms and the 8-bit CSI
/// (0x9B) and zero-padded parameter variants (GAP-0075 / APPSEC-03).
pub fn sanitizePasteContent(data: []u8) []u8 {
    var read_pos: usize = 0;
    var write_pos: usize = 0;

    while (read_pos < data.len) {
        if (pasteMarkerLen(data, read_pos)) |marker_len| {
            read_pos += marker_len;
            continue;
        }
        data[write_pos] = data[read_pos];
        write_pos += 1;
        read_pos += 1;
    }

    return data[0..write_pos];
}
```

- [ ] **Step 4: Run tests** — all existing `sanitizePasteContent` tests plus the two new ones must pass.

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/text_utils.zig
git commit -m "fix(security): strip 8-bit and zero-padded paste markers (GAP-0075)"
```

---

### Task 4: `enterRawMode` error-path cleanup (issue #147, ADV-002)

`enterRawMode` (src/platform.zig:189-246) commits `tcsetattr(raw)`, `saved_termios`, and signal handlers before `try compat.writeAll(stdout, "\x1b[?2004h")`. If that write fails, the error propagates before the caller's `defer restoreTerminalMode` exists — terminal stuck raw. Add `errdefer` cleanup.

**Files:**
- Modify: `src/platform.zig` (POSIX branch of `enterRawMode`, after the `tcsetattr` call)

- [ ] **Step 1: Apply the fix** (locate `try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);` in `enterRawMode`; the lines after it become):

```zig
    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);
    // ADV-002 (#147): if anything after this point fails, restore cooked mode
    // before propagating — the caller's `defer restoreTerminalMode` is not
    // registered until enterRawMode returns, so without this errdefer a
    // failed bracketed-paste enable would leave the terminal raw.
    errdefer std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};

    // Save original state for signal handler restoration and install handlers.
    saved_termios = original;
    installTerminalSignalHandlers();
    errdefer {
        removeTerminalSignalHandlers();
        saved_termios = null;
    }

    // Enable bracketed paste mode
    const stdout = getStdoutHandle();
    try compat.writeAll(stdout, "\x1b[?2004h");

    return original;
```

- [ ] **Step 2: Run tests + fmt**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS. `zig fmt --check src/platform.zig` → exit 0.
(No automated fault-injection seam exists for the stdout write; the errdefer is verified by review + compile. Note this in the commit body.)

- [ ] **Step 3: Commit**

```bash
git add src/platform.zig
git commit -m "fix(platform): restore terminal state when enterRawMode fails mid-setup (#147)"
```

- [ ] **Step 4: Close issue #147**

```bash
glab issue close 147 --repo devnw/zig/repl
glab issue note 147 --repo devnw/zig/repl -m "Fixed: errdefer in enterRawMode restores cooked termios and uninstalls signal handlers if the bracketed-paste enable write fails (src/platform.zig). Commit: $(git rev-parse --short HEAD)"
```

---

### Task 5: `parse.zig` depth counters i32 → i64 (GAP-0076; APPSEC-07)

`isBalanced` (src/parse.zig:36-39) and `needsContinuation` (search for other `: i32 = 0` depth vars in the file) use `i32` counters. ~2 GB of `(` overflows: trap in ReleaseSafe, wrap in ReleaseFast. A slice cannot hold more than `usize` bytes, and `i64` cannot overflow from a byte count on any supported target — switch the counter type. Zero behavior change.

**Files:**
- Modify: `src/parse.zig`

- [ ] **Step 1: Change all bracket/paren/brace depth counter declarations from `i32` to `i64`**

```zig
    var paren_depth: i64 = 0;
    var bracket_depth: i64 = 0;
    var brace_depth: i64 = 0;
```

Search the whole file for `: i32 = 0` — apply to every depth counter (there is a second set in `needsContinuation`/related fns around lines 125-138). Add a one-line comment above the first set:

```zig
    // i64: a slice can hold at most usize bytes, so a per-byte counter can
    // never overflow i64 — removes the theoretical i32 wrap/trap (APPSEC-07).
```

- [ ] **Step 2: Run tests (fuzz tests in parse.zig included)**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 3: Commit**

```bash
git add src/parse.zig
git commit -m "fix(parse): widen bracket depth counters to i64 (GAP-0076)"
```

---

### Task 6: Undo snapshots for bracketed paste and Vi direct-mutation operators (#146, QF-091)

Two undo bypasses: (a) `flushPasteBuffer` (src/core.zig, search `fn flushPasteBuffer`) inserts paste content with no snapshot; (b) vi `dd/dw/db/de/cc` mutate inside `handlePendingOperator` and return `.none`/`.vi_insert_mode`, so the keep-snapshot condition `is_destructive and changed` discards the snapshot `keyMayMutate` already took.

**Files:**
- Modify: `src/core.zig` (`flushPasteBuffer`, the snapshot keep-condition in `processInput`)
- Test: `src/core.zig` (new tests near the existing paste tests)

- [ ] **Step 1: Write the failing tests** (place near the existing `consumeBracketedPaste` tests in core.zig; mirror their setup pattern — look at `test "consumeBracketedPaste: normal paste within buffer size"` for the `createTestState` helper usage):

```zig
test "undo restores pre-paste buffer after flushPasteBuffer" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "pre");
    state.cursor = 3;

    var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
    var paste_len: usize = 0;
    const content = "pasted";
    @memcpy(paste_buf[0..content.len], content);
    paste_len = content.len;
    var last_action: KeyAction = .none;
    flushPasteBuffer(&state, &paste_buf, &paste_len, &last_action);
    try std.testing.expectEqualStrings("prepasted", state.buffer.items);

    // Undo must restore the pre-paste buffer.
    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("pre", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "vi dw is undoable" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    state.keymap = .vi;
    state.vi_mode = .normal;

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 0;

    // Feed "dw" through processInput's per-key path by simulating the two
    // key events directly: 'd' arms the pending operator, 'w' executes dw.
    var last_action: KeyAction = .none;
    try processInputBytes(&state, "dw", &last_action);
    try std.testing.expectEqualStrings("world", state.buffer.items);

    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("hello world", state.buffer.items);
}
```

**Note for implementer:** check whether a byte-feeding helper like `processInputBytes` already exists from the d039c05 "testable input loop" work (grep `processInputBytes\|feedInput\|injectInput` in core.zig and look at how the `perf NEW-1: pure cursor moves perform zero buffer dupes` test drives keys). Reuse the existing mechanism; if the existing tests drive keys via `keymap_vi.handleKey(&state, ...)` + `processAction`, mirror that instead:

```zig
    // Alternative driving if no byte-feeder exists — replicate the
    // processInput snapshot flow manually:
    // 'd' press
    _ = keymap_vi.handleKey(&state, .{ .key = 'd' });
    // 'w' press with snapshot, exactly as processInput does:
    const pre = try allocator.dupe(u8, state.buffer.items);
    const pre_cursor = state.cursor;
    const action = keymap_vi.handleKey(&state, .{ .key = 'w' });
    try processAction(&state, action);
    if (!std.mem.eql(u8, pre, state.buffer.items)) {
        try state.undo_stack.pushOwned(pre, pre_cursor);
    } else {
        allocator.free(pre);
    }
```

If the manual-replication form is needed, the test then primarily pins the *new keep-condition semantics* — still write it, and additionally verify via the real `processInput` path if the d039c05 testable-loop seam allows.

- [ ] **Step 2: Run tests to verify the undo assertions fail**

Run: `zig build test --summary all 2>&1 | tail -10`
Expected: FAIL — after `.undo`, buffer is unchanged (no snapshot was kept).

- [ ] **Step 3: Fix the keep-condition in `processInput`** (search for `Keep the snapshot only if the action was destructive`):

Replace:

```zig
            const changed = is_destructive and !std.mem.eql(u8, buf_snap, state.buffer.items);
```

with:

```zig
            // Keep the snapshot whenever the buffer ACTUALLY changed — not
            // only for delete/insert-class actions. Vi operators (dd/dw/db/
            // de/cc) mutate the buffer inside handleKey and return .none, so
            // an action-class check misses them (QF-091 / #146). Comparing
            // the pre-state against the final buffer is authoritative for
            // every mutation path.
            const changed = !std.mem.eql(u8, buf_snap, state.buffer.items);
```

Then delete the now-unused `is_destructive` block (the `const is_destructive = switch (action) { ... };` a few lines above) — `zig build` will error on unused constants if left.

- [ ] **Step 4: Fix `flushPasteBuffer`** (whole function):

```zig
fn flushPasteBuffer(
    state: *ReplState,
    paste_buf: *[PASTE_BUF_SIZE]u8,
    paste_len: *usize,
    last_action: *KeyAction,
) void {
    const data = paste_buf[0..paste_len.*];
    const sanitized = sanitizePasteContent(data);
    if (sanitized.len > 0) {
        // QF-091 (#146): snapshot the pre-paste buffer so paste is undoable.
        // For pastes larger than PASTE_BUF_SIZE each flushed chunk becomes
        // one undo step. Snapshot alloc failure degrades to non-undoable
        // paste (matching the keystroke path's catch-null policy).
        const pre_buffer: ?[]u8 = state.allocator.dupe(u8, state.buffer.items) catch null;
        const pre_cursor = state.cursor;
        state.buffer.insertSlice(state.allocator, state.cursor, sanitized) catch {
            if (pre_buffer) |p| state.allocator.free(p);
            return;
        };
        if (pre_buffer) |p| {
            state.undo_stack.pushOwned(p, pre_cursor) catch {
                state.allocator.free(p);
            };
        }
        state.cursor += sanitized.len;
        state.content_changed = true;
        last_action.* = .insert;
    }
    paste_len.* = 0;
}
```

(Compare against the current body first — keep any post-d039c05 details like the `sanitized.len` cursor advance identical apart from the snapshot insertion.)

- [ ] **Step 5: Run full tests**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS, including all existing undo and paste tests (watch for tests that asserted vi `dd` was NOT undoable — if any exist, update them to the new, correct semantics and say so in the commit).

- [ ] **Step 6: Commit and close #146**

```bash
git add src/core.zig
git commit -m "fix(core): make paste and vi operator mutations undoable (#146, QF-091)"
glab issue close 146 --repo devnw/zig/repl
glab issue note 146 --repo devnw/zig/repl -m "Fixed: snapshot keep-condition now keyed on actual buffer change (covers vi dd/dw/db/de/cc), and flushPasteBuffer pushes an undo snapshot per flushed chunk. Tests added. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 7: Wire `Config.max_history` through `Repl.Options` to `HistoryStore` (#149, QF-093)

`Config.max_history` is parsed/persisted but nothing maps it to `HistoryStore.max_entries` (hardcoded default 5000). Add `max_history` to `Repl.Options` and assign it in `run()`.

**Files:**
- Modify: `src/core.zig` (`Options` struct ~line 170; `run()` after `HistoryStore.init` ~line 227)
- Modify: `src/config.zig` (module doc comment mapping example, ~lines 12-30)
- Modify: `README.md` (Options table)

- [ ] **Step 1: Add the Options field** (after `history_path` in `pub const Options`):

```zig
        /// Maximum number of history entries kept in memory and persisted.
        /// Maps from `Config.max_history` for consumers using the config file.
        max_history: usize = 5000,
```

- [ ] **Step 2: Wire it in `run()`** (immediately after `var hist = try history_mod.HistoryStore.init(opts.allocator, hist_path, opts.history_enabled);`):

```zig
        hist.max_entries = opts.max_history;
```

- [ ] **Step 3: Add a regression test** (near other core.zig option tests; verify the field plumbs):

```zig
test "Options.max_history maps to HistoryStore.max_entries" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    const opts = Repl.Options{ .allocator = allocator, .max_history = 42 };
    hist.max_entries = opts.max_history;
    try std.testing.expectEqual(@as(usize, 42), hist.max_entries);

    // Capacity is enforced on append.
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var buf: [8]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "cmd{d}", .{i});
        try hist.append(line);
    }
    try std.testing.expectEqual(@as(usize, 42), hist.entries.items.len);
}
```

- [ ] **Step 4: Update docs** — in `src/config.zig`'s module doc comment, extend the Config→Options mapping example to include `.max_history = config.max_history,`. In `README.md`'s Options/configuration table add a row: `| max_history | usize | 5000 | Maximum history entries kept and persisted |` (match the table's existing format exactly).

- [ ] **Step 5: Run tests + fmt**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 6: Commit and close #149**

```bash
git add src/core.zig src/config.zig README.md
git commit -m "fix(core): wire max_history through Repl.Options to HistoryStore (#149, QF-093)"
glab issue close 149 --repo devnw/zig/repl
glab issue note 149 --repo devnw/zig/repl -m "Fixed: Options.max_history added (default 5000), assigned to HistoryStore.max_entries in run(); Config mapping documented in config.zig and README. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 8: `handleSearch` tolerates transient I/O errors (#153, QF-097)

`handleSearch` (src/search.zig:22+) propagates `compat.read` and append errors via `try`, killing the whole REPL on a hiccup mid-search, while the main loop tolerates BrokenPipe. Change: any I/O or alloc failure inside the search loop cancels the search gracefully (returns, leaving the accepted-so-far buffer state).

**Files:**
- Modify: `src/search.zig`

- [ ] **Step 1: Change the error handling inside the search loop**

In the `outer: while (true)` loop body:

```zig
        // QF-097 (#153): a transient read failure cancels the search instead
        // of tearing down the whole REPL (renderPrompt already tolerates
        // BrokenPipe; the search loop should degrade the same way).
        const n = compat.read(stdin, &search_buf) catch break :outer;
```

Find every other `try` inside the loop (`state.search_buffer.append(...)`, the final `compat.writeAll(stdout, display_line)`) and convert the same way:

```zig
            state.search_buffer.append(state.allocator, c) catch break :outer;
```

```zig
        compat.writeAll(stdout, display_line) catch break :outer;
```

Keep `try` only on operations *outside* the loop whose failure genuinely must propagate (check whether any exist; the function-level error set may shrink — if `handleSearch` no longer returns errors, change its signature to non-error and fix the call site in `core.zig` (`processAction`'s `.search` arm), removing the `try` there).

- [ ] **Step 2: Add a regression test pinning the no-error contract** (if the signature became non-error, in `src/search.zig`):

```zig
test "handleSearch signature does not propagate I/O errors" {
    // Compile-time pin: if handleSearch regains an error set, this breaks.
    const F = @TypeOf(handleSearch);
    const info = @typeInfo(F).@"fn";
    try std.testing.expect(@typeInfo(info.return_type.?) != .error_union);
}
```

(If keeping an error signature for OOM-only reasons, skip this test and instead document the retained error set in a doc comment.)

- [ ] **Step 3: Run tests + fmt**

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 4: Commit and close #153**

```bash
git add src/search.zig src/core.zig
git commit -m "fix(search): cancel search on transient I/O errors instead of killing the REPL (#153, QF-097)"
glab issue close 153 --repo devnw/zig/repl
glab issue note 153 --repo devnw/zig/repl -m "Fixed: read/append/write failures inside the Ctrl-R loop now cancel the search gracefully. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 9: Assert and document the `cursor <= buffer.len` invariant (#151, QF-095)

`ReplState` is public ("advanced use cases") and slicing code relies on `cursor <= buffer.items.len` with no guard.

**Files:**
- Modify: `src/core.zig` (`ReplState.cursor` field doc; top of `processAction`)

- [ ] **Step 1: Document the field** — find `cursor:` in the `ReplState` struct and give it a doc comment:

```zig
    /// Byte offset of the cursor within `buffer`.
    /// INVARIANT: `cursor <= buffer.items.len` at every public API boundary.
    /// All editing paths in this module maintain it; external callers that
    /// mutate `buffer` or `cursor` directly (ReplState is exposed for
    /// advanced use) must re-establish it or processAction will assert.
    cursor: usize = 0,
```

- [ ] **Step 2: Assert at the dispatch boundary** — first line of `fn processAction(state: *ReplState, action: KeyAction) !void {`:

```zig
    // QF-095 (#151): slicing below (delete_to_eol/bol, word ops) relies on
    // this invariant; fail fast in safe builds if an external caller broke it.
    std.debug.assert(state.cursor <= state.buffer.items.len);
```

- [ ] **Step 3: Run tests + fmt** → PASS.

- [ ] **Step 4: Commit and close #151**

```bash
git add src/core.zig
git commit -m "fix(core): assert and document cursor<=len invariant on processAction (#151, QF-095)"
glab issue close 151 --repo devnw/zig/repl
glab issue note 151 --repo devnw/zig/repl -m "Fixed: invariant documented on ReplState.cursor and asserted at processAction entry. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 10: Remove dead render-tracking state (#150, QF-094)

`last_buffer_len` and `last_visual_lines` are written across core.zig but never read (`content_changed` IS read — it gates the completion-context reset in `processAction`; keep it). Delete the two dead fields and every write site. The skip-redraw optimization they hinted at stays tracked as a perf enhancement — note that disposition when closing.

**Files:**
- Modify: `src/core.zig`

- [ ] **Step 1: Verify readers** (must be zero reads for the two fields, >0 for content_changed):

```bash
grep -n "last_buffer_len\|last_visual_lines\|content_changed" src/core.zig src/*.zig
```

Expected: `last_buffer_len`/`last_visual_lines` appear only as `state.X = ...` assignments and the field declarations; `content_changed` has at least one `if (...)` read (completion reset). If a genuine read of the two fields exists, STOP and re-scope — do not delete.

- [ ] **Step 2: Delete the two field declarations from `ReplState` and every assignment site** (the grep from Step 1 lists them all). Leave `content_changed` and `last_cursor_row` untouched (both are read).

- [ ] **Step 3: Run tests + fmt** → PASS (a test referencing the deleted fields would fail compile — update/remove any such assertions, keeping the `content_changed` test).

- [ ] **Step 4: Commit and close #150**

```bash
git add src/core.zig
git commit -m "refactor(core): remove dead render-tracking fields (#150, QF-094)"
glab issue close 150 --repo devnw/zig/repl
glab issue note 150 --repo devnw/zig/repl -m "Resolved by deleting the write-only fields last_buffer_len/last_visual_lines (8 sync sites removed). content_changed retained — it gates completion reset. The skip-redraw-on-cursor-move optimization remains tracked as a perf enhancement. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 11: Extract shared `killRange` helper (#154, QF-098)

The 3-step kill pattern (clear ring → appendSlice range → replaceRange-delete) is duplicated across `core.zig` `processAction` (delete_word, delete_word_backward, delete_to_eol, delete_to_bol) and `keymap_vi.zig` `handlePendingOperator` (dd, dw, db, de).

**Files:**
- Modify: `src/core.zig` (new pub fn + 4 call sites)
- Modify: `src/keymap_vi.zig` (4 call sites)

- [ ] **Step 1: Add the helper to `src/core.zig`** (near `processAction`):

```zig
/// Kill (cut) `buffer[start..end)`: replace the kill ring's contents with the
/// range, delete it from the buffer, and mark `last_was_kill`.
/// No-op when `start >= end`. `state` is `anytype` so keymap modules can pass
/// their duck-typed test states (same contract as handleKey).
///
/// Kill-ring alloc failures are non-critical: the delete still proceeds,
/// yank-back just won't have data. Shrinking replaceRange with an empty
/// replacement cannot allocate.
pub fn killRange(state: anytype, start: usize, end: usize) void {
    if (start >= end) return;
    state.kill_ring.clearRetainingCapacity();
    state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..end]) catch {};
    state.buffer.replaceRange(state.allocator, start, end - start, &.{}) catch unreachable;
    state.last_was_kill = true;
}
```

- [ ] **Step 2: Replace the four `processAction` sites in core.zig** — preserve exact cursor semantics:

```zig
        .delete_word => {
            const end = findWordEnd(state.buffer.items, state.cursor);
            killRange(state, state.cursor, end);
        },
        .delete_word_backward => {
            const start = findWordStart(state.buffer.items, state.cursor);
            killRange(state, start, state.cursor);
            state.cursor = @min(state.cursor, start);
            state.last_was_kill = true; // parity: set even when range was empty
        },
        .delete_to_eol => {
            killRange(state, state.cursor, state.buffer.items.len);
            state.last_was_kill = true; // parity: set even at EOL
        },
        .delete_to_bol => {
            killRange(state, 0, state.cursor);
            state.cursor = 0;
            state.last_was_kill = true; // parity: set even at BOL
        },
```

**Behavior-parity caution:** the current code sets `last_was_kill = true` (and clears the ring) even for empty ranges in delete_to_eol/delete_to_bol/delete_word_backward; `killRange` early-returns on empty. The explicit `state.last_was_kill = true` lines above preserve the flag parity. Run the kill-ring tests and compare — if any test pins "ring cleared on empty delete", adapt by calling `state.kill_ring.clearRetainingCapacity()` in those arms too.

- [ ] **Step 3: Replace the four `keymap_vi.zig` sites** (`handlePendingOperator` arms for `'d'`):

```zig
            'd' => {
                // dd: delete line
                core.killRange(state, 0, state.buffer.items.len);
                state.cursor = 0;
                state.last_was_kill = true;
                state.pending_operator = null;
                return .none;
            },
            'w' => {
                // dw: delete word
                core.killRange(state, state.cursor, findWordEnd(state.buffer.items, state.cursor));
                state.pending_operator = null;
                return .none;
            },
            'b' => {
                // db: delete word backward
                const start = findWordStart(state.buffer.items, state.cursor);
                core.killRange(state, start, state.cursor);
                state.cursor = start;
                state.pending_operator = null;
                return .none;
            },
            'e' => {
                // de: delete to end of word
                core.killRange(state, state.cursor, findEndOfWord(state.buffer.items, state.cursor));
                state.pending_operator = null;
                return .none;
            },
```

(`keymap_vi.zig` already does `const core = @import("core.zig")` — verify the import alias and use it.)

- [ ] **Step 4: Run full tests** — the existing dd/dw/db/de and kill-ring tests in keymap_vi.zig and core.zig are the regression net.

Run: `zig build test --summary all 2>&1 | tail -5` → PASS.

- [ ] **Step 5: Commit and close #154**

```bash
git add src/core.zig src/keymap_vi.zig
git commit -m "refactor: extract shared killRange helper for the 8 kill sites (#154, QF-098)"
glab issue close 154 --repo devnw/zig/repl
glab issue note 154 --repo devnw/zig/repl -m "Fixed: killRange(state, start, end) in core.zig replaces the duplicated 3-step pattern at 8 sites (4 core, 4 vi). Commit: $(git rev-parse --short HEAD)"
```

---

### Task 12: Centralize paste-marker literals (#164, QF-108)

`"\x1b[200~"`/`"\x1b[201~"` are inlined in `core.zig` (search `200~`) and locally in `text_utils.zig`. Promote to module-level pub consts in `text_utils.zig`; reference everywhere.

**Files:**
- Modify: `src/text_utils.zig`, `src/core.zig`

- [ ] **Step 1: Add to `src/text_utils.zig`** (above `sanitizePasteContent`):

```zig
/// Canonical 7-bit bracketed-paste markers (ESC [ 200~ / ESC [ 201~).
pub const paste_start_marker = "\x1b[200~";
pub const paste_end_marker = "\x1b[201~";
```

- [ ] **Step 2: Replace every production literal**: in `core.zig` (the `isPasteMarkerPrefix` consts and the two `std.mem.eql(u8, buf[i.*..][0..6], "\x1b[200~")`-style checks — use `text_utils.paste_start_marker`/`paste_end_marker` and `.len` instead of hardcoded 6 where it reads better). Test-block literals may stay. In `text_utils.zig`, sanitize/prefix helpers reference the new consts.

- [ ] **Step 3: Run tests + fmt** → PASS.

- [ ] **Step 4: Commit and close #164**

```bash
git add src/text_utils.zig src/core.zig
git commit -m "refactor: centralize bracketed-paste marker literals (#164, QF-108)"
glab issue close 164 --repo devnw/zig/repl
glab issue note 164 --repo devnw/zig/repl -m "Fixed: paste_start_marker/paste_end_marker pub consts in text_utils.zig; production literals replaced. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 13: Test isolation — `std.testing.tmpDir` instead of hardcoded `/tmp` paths (#152, QF-096)

History/config tests use fixed paths like `/tmp/test_repl_history.tmp` — racy across parallel runs, non-portable. Convert every site (grep `"/tmp/` in `src/history.zig` ~9 sites and `src/config.zig` ~4 sites).

**Files:**
- Modify: `src/history.zig`, `src/config.zig` (tests only)

- [ ] **Step 1: Establish the conversion pattern** — for each test using a hardcoded path:

```zig
test "history file permissions are 0o600" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &dir_buf);
    const path = try std.fs.path.join(allocator, &.{ dir_path, "hist.txt" });
    defer allocator.free(path);
    // ... rest of test unchanged, using `path` ...
}
```

`std.testing.tmpDir` may interact with the 0.16 `std.Io` APIs the code under test uses — the stores open paths via `std.Io.Dir.cwd()` with an absolute path, which works with the joined absolute `path`. If `tmp.dir.realpath` is unavailable in 0.16, fall back to `try tmp.dir.realpathAlloc(allocator, ".")` (and free it). Verify with one test before converting the rest.

- [ ] **Step 2: Convert all sites** (every `"/tmp/...` literal in tests in both files; delete any now-unneeded `std.fs.cwd().deleteFile` cleanup lines — `tmp.cleanup()` handles it).

- [ ] **Step 3: Run the suite twice concurrently to prove isolation**

```bash
zig build test --summary all & zig build test --summary all ; wait
```

Expected: both PASS (previously could race on shared /tmp files).

- [ ] **Step 4: Commit and close #152**

```bash
git add src/history.zig src/config.zig
git commit -m "test: isolate history/config tests with std.testing.tmpDir (#152, QF-096)"
glab issue close 152 --repo devnw/zig/repl
glab issue note 152 --repo devnw/zig/repl -m "Fixed: all hardcoded /tmp test paths converted to std.testing.tmpDir with cleanup. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 14: Boundary tests for HistoryStore and history_index transitions (#156, QF-100)

**Files:**
- Modify: `src/history.zig` (new tests), `src/core.zig` (new tests)

- [ ] **Step 1: Add HistoryStore boundary tests** (src/history.zig, near existing tests; check exact signatures of `get`/`search`/`searchBackward` first and adapt argument/return shapes):

```zig
test "get returns null for out-of-range index" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("one");
    try std.testing.expect(hist.get(0) != null);
    try std.testing.expect(hist.get(1) == null);
    try std.testing.expect(hist.get(9999) == null);
}

test "searchBackward with empty pattern matches the most recent entry" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("alpha");
    try hist.append("beta");
    // indexOf(_, "") matches at position 0 of any entry — pin the semantics.
    const result = hist.searchBackward("", null);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("beta", result.?.entry);
}

test "searchBackward start_index boundaries" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("match one");
    try hist.append("other");
    try hist.append("match two");
    // Starting before index 0's entry: only entry 0 is scanned.
    const r0 = hist.searchBackward("match", 0);
    try std.testing.expect(r0 != null);
    try std.testing.expectEqualStrings("match one", r0.?.entry);
    // Empty store
    var empty = try HistoryStore.init(allocator, null, true);
    defer empty.deinit();
    try std.testing.expect(empty.searchBackward("x", null) == null);
}
```

(**Adapt to the real API**: read `searchBackward`'s signature — it may take `start_index: ?usize` or a plain `usize`; the result may be a struct with `.entry`/`.index`. Mirror how `search.zig:82-86` calls it.)

- [ ] **Step 2: Add history_index transition asserts** (src/core.zig, near the existing history navigation tests — find `test "processAction: history` blocks and extend with explicit index assertions):

```zig
test "history_index transitions at boundaries" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("first");
    try hist.append("second");
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    // Walk back to the oldest entry; index must clamp, not underflow.
    try processAction(&state, .history_prev); // -> "second" (index 1)
    try std.testing.expectEqual(@as(?usize, 1), state.history_index);
    try processAction(&state, .history_prev); // -> "first" (index 0)
    try std.testing.expectEqual(@as(?usize, 0), state.history_index);
    try processAction(&state, .history_prev); // stay on "first"
    try std.testing.expectEqual(@as(?usize, 0), state.history_index);

    // Walk forward past the newest entry; index must become null (live line).
    try processAction(&state, .history_next);
    try std.testing.expectEqual(@as(?usize, 1), state.history_index);
    try processAction(&state, .history_next);
    try std.testing.expectEqual(@as(?usize, null), state.history_index);
}
```

- [ ] **Step 3: Run tests** → all PASS (if an assertion exposes a real off-by-one, fix the bug in the same task and note it in the commit).

- [ ] **Step 4: Commit and close #156**

```bash
git add src/history.zig src/core.zig
git commit -m "test: add HistoryStore boundary and history_index transition tests (#156, QF-100)"
glab issue close 156 --repo devnw/zig/repl
glab issue note 156 --repo devnw/zig/repl -m "Fixed: boundary tests added for get OOB, empty-pattern search, start_index edges, and history_index clamp/null transitions. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 15: Callback contract docs + missing re-exports (#158, QF-102) and path-doc fix (#159, QF-103)

**Files:**
- Modify: `src/repl.zig` (re-exports), `src/core.zig` (Options doc comments), `src/history.zig` (`getDefaultHistoryPath` doc)

- [ ] **Step 1: Re-export the callback types in `src/repl.zig`** — find where `CompleteFn` is re-exported (`pub const CompleteFn = core.CompleteFn;` style) and add siblings:

```zig
pub const RunFn = core.RunFn;
pub const IsCompleteFn = core.IsCompleteFn;
pub const WelcomeFn = core.WelcomeFn;
```

- [ ] **Step 2: Document error contracts on `Options`** in `src/core.zig` — replace the three field doc comments:

```zig
        /// Command handler function.
        /// ERROR CONTRACT: errors returned by run_fn are printed to stderr
        /// and the REPL CONTINUES running (a failing command must not tear
        /// down the session).
        run_fn: ?RunFn = null,
        /// Statement completion checker (for multi-line input).
        /// Cannot fail: the callback returns bool, with no error channel.
        is_complete_fn: ?IsCompleteFn = null,
```

and on `welcome_fn`:

```zig
        /// Welcome message printer.
        /// ERROR CONTRACT: errors returned by welcome_fn ABORT Repl.run()
        /// before the terminal enters raw mode.
        welcome_fn: ?WelcomeFn = null,
```

- [ ] **Step 3: Fix `getDefaultHistoryPath` doc** in `src/history.zig` (~line 288) — rewrite the fallback list to match the code:

```zig
/// Resolve the default history file path for `app_name`.
/// Resolution order:
///   1. `$<APP>_HISTORY` env override (validated by isPathSafe).
///   2. `~/.<app>_history` whenever `HOME` is set — this is the effective
///      path on virtually all systems.
///   3. Platform-specific app-data fallbacks (XDG_DATA_HOME, macOS
///      Application Support, Windows APPDATA) — reached ONLY when `HOME`
///      is unset.
```

(Adapt wording to the actual branch order in the function body — re-read it first.)

- [ ] **Step 4: Run tests + fmt** → PASS.

- [ ] **Step 5: Commit and close #158, #159**

```bash
git add src/repl.zig src/core.zig src/history.zig
git commit -m "docs(api): document callback error contracts, re-export callback types, fix history path doc (#158 #159)"
glab issue close 158 --repo devnw/zig/repl
glab issue note 158 --repo devnw/zig/repl -m "Fixed: RunFn/IsCompleteFn/WelcomeFn re-exported from repl.zig; error contracts documented on Options. Commit: $(git rev-parse --short HEAD)"
glab issue close 159 --repo devnw/zig/repl
glab issue note 159 --repo devnw/zig/repl -m "Fixed: getDefaultHistoryPath doc now matches actual resolution order (platform fallbacks only when HOME unset). Commit: $(git rev-parse --short HEAD)"
```

---

### Task 16: SIGTSTP suspend/resume terminal handling + accurate signal docs (#155, QF-099)

The docs claim "cleanup on signals"; SIGTERM/SIGHUP/SIGWINCH are handled but Ctrl-Z (SIGTSTP) leaves the terminal raw while suspended and broken on resume. Implement suspend/resume handling: on SIGTSTP restore cooked mode and re-raise with default disposition; on SIGCONT re-apply raw mode. `tcsetattr`, `sigaction`, `raise`, and `kill` are async-signal-safe per POSIX.

**Files:**
- Modify: `src/platform.zig` (signal section, `installTerminalSignalHandlers`/`removeTerminalSignalHandlers`)
- Modify: `README.md` + `src/repl.zig` module docstring (signal behavior wording)

- [ ] **Step 1: Read the existing signal section** (`src/platform.zig:40-115`) to match its style exactly (handler fn signature, `std.posix.sigaction` usage, the `saved_termios` global, SA_RESETHAND usage for TERM/HUP).

- [ ] **Step 2: Add the handlers** (POSIX-only, same guards as existing handlers):

```zig
/// SIGTSTP (Ctrl-Z): restore cooked mode so the user's shell is usable while
/// the process is suspended, then re-deliver SIGTSTP with the default
/// disposition so the suspension actually happens.
/// Async-signal-safety: tcsetattr, sigaction, and raise are all ASYNC-SAFE
/// per POSIX.1.
fn handleSigtstp(sig: c_int) callconv(.c) void {
    if (saved_termios) |original| {
        const stdin_handle = getStdinHandle().handle;
        std.posix.tcsetattr(stdin_handle, .FLUSH, original) catch {};
    }
    // Re-raise with default disposition to actually suspend.
    var dfl_action = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TSTP, &dfl_action, null);
    std.posix.raise(@intCast(sig)) catch {};
}

/// SIGCONT (resume after Ctrl-Z): re-enter raw mode and re-arm the SIGTSTP
/// handler. The screen is not redrawn from the handler (not async-safe);
/// the next keystroke triggers a normal render.
fn handleSigcont(_: c_int) callconv(.c) void {
    if (saved_termios != null) {
        // Reconstruct raw settings from the saved original, mirroring
        // enterRawMode's flag set.
        if (saved_termios) |original| {
            var raw = original;
            raw.iflag.ICRNL = false;
            raw.iflag.IXON = false;
            raw.oflag.OPOST = false;
            raw.lflag.ECHO = false;
            raw.lflag.ICANON = false;
            raw.lflag.ISIG = false;
            raw.lflag.IEXTEN = false;
            raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
            raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
            const stdin_handle = getStdinHandle().handle;
            std.posix.tcsetattr(stdin_handle, .FLUSH, raw) catch {};
        }
        installTstpHandler();
    }
}

fn installTstpHandler() void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = handleSigtstp },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TSTP, &action, null);
}
```

**Implementer must adapt** to the file's exact existing idioms: how `Sigaction` is constructed for the TERM/HUP handlers (copy that struct literal style and the `callconv` annotation precisely — Zig 0.16 may use `.{ .handler = ... }` differently), whether `std.posix.raise` exists or `std.posix.kill(std.posix.getpid(), ...)` is the available API, and the `sigemptyset` spelling used elsewhere in the file. Avoid duplicating the raw-flag block if `enterRawMode`'s flag setup can be extracted into a shared `fn makeRawTermios(original: std.posix.termios) std.posix.termios` — prefer that extraction (DRY):

```zig
fn makeRawTermios(original: std.posix.termios) std.posix.termios {
    var raw = original;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
    return raw;
}
```

and use it from both `enterRawMode` and `handleSigcont`.

- [ ] **Step 3: Wire install/remove** — in `installTerminalSignalHandlers()` add `installTstpHandler()` and a SIGCONT sigaction; in `removeTerminalSignalHandlers()` reset TSTP and CONT to `SIG.DFL` alongside the existing resets.

- [ ] **Step 4: Run tests; manual smoke if a TTY is available**

`zig build test --summary all` → PASS. Manual (optional, requires interactive TTY): run `zig build run`, Ctrl-Z → shell prompt echoes normally; `fg` → typing works, line redraws on next key.

- [ ] **Step 5: Fix the docs** — `README.md` feature bullet and `src/repl.zig` module docstring: state precisely "Terminal state restored on normal exit, SIGTERM/SIGHUP, and Ctrl-Z suspend/resume (SIGTSTP/SIGCONT); SIGKILL cannot be handled."

- [ ] **Step 6: Commit and close #155**

```bash
git add src/platform.zig README.md src/repl.zig
git commit -m "feat(platform): restore terminal on SIGTSTP suspend and re-raw on SIGCONT (#155, QF-099)"
glab issue close 155 --repo devnw/zig/repl
glab issue note 155 --repo devnw/zig/repl -m "Fixed: SIGTSTP handler restores cooked mode and re-raises; SIGCONT re-enters raw mode; docs updated to state exact signal coverage. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 17: Low-hygiene batch — doc comments, magic numbers, swallowed-error comments, dead-API docs (#169, #168, #163, #161)

**Files:**
- Modify: `src/input.zig`, `src/repl.zig`, `src/compat.zig`, `src/config.zig`, `src/observability_init.zig`, `src/core.zig`, `src/render.zig`, `src/parse.zig`, `src/completion.zig`

- [ ] **Step 1 (#169): `///` docs** — in `src/input.zig`, convert the `//` comments on `SyntheticKey`'s `delete`/`page_up`/`page_down` constants to `///` doc comments (e.g. `/// ESC[3~: forward delete (synthetic, collision-free code).`). In `src/repl.zig`, add `///` docs to `version_major`/`version_minor`/`version_patch` (`/// Major component of `version`, parsed at comptime.`).

- [ ] **Step 2 (#168): magic numbers** — `src/compat.zig` (search `>= 255`): introduce `const max_env_name_len = 255;` and use it for both the check and the `[256]u8` buffer (`[max_env_name_len + 1]u8`). `src/config.zig` test (search `999`): `const test_max_history = 999; // differs from the 5000 default to prove round-trip`.

- [ ] **Step 3 (#163): swallowed-error intent comments** — `src/observability_init.zig` (the three `forceFlush(...) catch {}` lines): add one comment above the block: `// Best-effort flush on shutdown: exporter failures are unreportable here (deinit path, telemetry already optional by design).` `src/core.zig` (search `compat.writeAll(stdout, "\r\n") catch {};`): add `// Best-effort: stdout may already be broken (pipe closed) during exit.`

- [ ] **Step 4 (#161): dead pub API disposition** — add doc comments declaring intent on: `src/render.zig` `calculateVisualLines`, `calculateCursorPosition`, `tabWidth` (`/// Public utility for consumers building custom render layers; unused internally.`); `src/parse.zig` `trimTrailing`, `hasBackslashContinuation` (same wording); `src/completion.zig` `keywordProvider` (`/// Convenience provider for static keyword lists — consumer-facing API.`). Leave `observability.zig` span fns as-is (template symmetry already documented in-file).

- [ ] **Step 5: Run tests + fmt** → PASS.

- [ ] **Step 6: Commit and close #169, #168, #163, #161**

```bash
git add src/input.zig src/repl.zig src/compat.zig src/config.zig src/observability_init.zig src/core.zig src/render.zig src/parse.zig src/completion.zig
git commit -m "docs(code): doc comments, named constants, swallowed-error intent notes (#169 #168 #163 #161)"
for n in 169 168 163 161; do
  glab issue close $n --repo devnw/zig/repl
  glab issue note $n --repo devnw/zig/repl -m "Fixed in commit $(git rev-parse --short HEAD) (low-hygiene batch: docs/constants/intent comments)."
done
```

---

### Task 18: Project docs — CONTRIBUTING Zig version (#143) and CHANGELOG backfill (#144)

**Files:**
- Modify: `docs/CONTRIBUTING.md:9`, `CHANGELOG.md`

- [ ] **Step 1 (#143):** change `docs/CONTRIBUTING.md` line 9 from `0.15.0 or later` to `0.16.0 or later` (verify nothing else in the file says 0.15: `grep -n "0\.1[45]" docs/CONTRIBUTING.md`).

- [ ] **Step 2 (#144):** backfill `CHANGELOG.md` with sections for v0.1.2 through v0.1.9. Generate the raw material:

```bash
for t in v0.1.2 v0.1.3 v0.1.4 v0.1.5 v0.1.6 v0.1.7 v0.1.8 v0.1.9; do
  echo "== $t  $(git log -1 --format=%ad --date=short $t)";
  git log --oneline $(git describe --tags --abbrev=0 $t^)..$t | head -20;
done
```

Write one `## [0.1.N] - YYYY-MM-DD` section per tag in Keep-a-Changelog style (Added/Fixed/Changed subsections, summarizing the commits — e.g. v0.1.5 "Fixed: hardcoded observability seam disabled to dodge Zig 0.16 build_options dedup", v0.1.9 "Fixed: config/history file permissions hardened (NEW-001/002), bracketed-paste state persists across reads (ADV-001), otel seam restored, CI base image digest-pinned"). Update the link references at the bottom: `[Unreleased]: ...compare/v0.1.9...HEAD` plus one compare link per new section, matching the existing `[0.1.1]` link format.

- [ ] **Step 3: markdownlint check** — `pre-commit run markdownlint --files CHANGELOG.md docs/CONTRIBUTING.md` → Passed.

- [ ] **Step 4: Commit and close #143, #144**

```bash
git add docs/CONTRIBUTING.md CHANGELOG.md
git commit -m "docs: fix CONTRIBUTING Zig version, backfill CHANGELOG v0.1.2-v0.1.9 (#143 #144)"
glab issue close 143 --repo devnw/zig/repl
glab issue note 143 --repo devnw/zig/repl -m "Fixed: docs/CONTRIBUTING.md now requires Zig 0.16.0. Commit: $(git rev-parse --short HEAD)"
glab issue close 144 --repo devnw/zig/repl
glab issue note 144 --repo devnw/zig/repl -m "Fixed: CHANGELOG backfilled for v0.1.2..v0.1.9 with compare links. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 19: Close issues already fixed upstream + stale-verified issues

These were verified already-resolved at `9b0085d`; close with evidence. Also verify-and-close #157 and #165.

- [ ] **Step 1: Verify #157 (duplicated leading-space filter)** — `grep -n "== ' '" src/core.zig src/history.zig`. Expected: the privacy filter exists ONLY at `history.zig:141` (the `core.zig` hits are paste-indent/completion logic, not the history privacy check). If a second history-privacy site exists, leave #157 open and STOP this step.

- [ ] **Step 2: Verify #165 (version derivation)** — confirm `src/repl.zig` derives `version` from `build_options` (search `build_options.version`). Expected: yes (landed in cf50500).

- [ ] **Step 3: Close with evidence:**

```bash
glab issue close 145 --repo devnw/zig/repl
glab issue note 145 --repo devnw/zig/repl -m "Resolved upstream: build.zig.zon version is 0.1.9 matching tag v0.1.9, and repl.zig now derives version constants from the manifest via build options (cf50500). Verified at 9b0085d."
glab issue close 133 --repo devnw/zig/repl
glab issue note 133 --repo devnw/zig/repl -m "Resolved upstream: DEBIAN_IMAGE pinned to debian:bookworm-slim@sha256:96e378d7... (.gitlab-ci.yml:34, cf50500). Verified at 9b0085d."
glab issue close 148 --repo devnw/zig/repl
glab issue note 148 --repo devnw/zig/repl -m "Resolved upstream: d039c05 added carry-over handling (carryOverSplit, PASTE_CARRY_MAX) for markers torn across read() boundaries plus a paste-read safety bound. Verified at 9b0085d."
glab issue close 157 --repo devnw/zig/repl
glab issue note 157 --repo devnw/zig/repl -m "Stale: the leading-space privacy filter now exists only in HistoryStore.append (history.zig:141); the duplicated core.zig site was removed in the d039c05 refactor. Verified at 9b0085d."
glab issue close 165 --repo devnw/zig/repl
glab issue note 165 --repo devnw/zig/repl -m "Resolved upstream: repl.zig version constants are derived from build.zig.zon via build options (cf50500) — divergence is no longer possible. Verified at 9b0085d."
```

---

### Task 20: Lint hygiene sweep (#166, QF-110)

- [ ] **Step 1: Run the full hook suite and let auto-fixers fix:**

```bash
pre-commit run --all-files || true
git status --short
```

- [ ] **Step 2:** If `ruff-format` still complains about `scripts/detect_diamond_deps.py`, run `ruff format scripts/detect_diamond_deps.py`. Fix any remaining markdownlint complaints by hand (language tags on fences, list numbering — re-run `pre-commit run markdownlint --all-files` until Passed). NOTE: upstream cycle-3 may have already fixed most of these — if `pre-commit run --all-files` passes clean on the first run, just close the issue with that evidence.

- [ ] **Step 3: Run `zig build test` one more time** (hooks touch only docs/scripts, but verify) → PASS.

- [ ] **Step 4: Commit (if changes) and close #166:**

```bash
git add -A
git commit -m "chore: lint hygiene sweep — pre-commit autofixes (#166, QF-110)" || echo "nothing to fix"
glab issue close 166 --repo devnw/zig/repl
glab issue note 166 --repo devnw/zig/repl -m "Fixed: pre-commit run --all-files passes clean. Commit: $(git rev-parse --short HEAD)"
```

---

### Task 21: File tracking issues for the two security fixes done in Tasks 1–3 + 5, update gap docs, push

- [ ] **Step 1: Create the (retroactive) tracking issues** so the tracker mirrors reality — one per fixed gap, created closed-with-evidence:

```bash
glab issue create --repo devnw/zig/repl \
  --title "GAP-0074: C1 control bytes (0x80-0x9F) bypassed display and history filters" \
  --label security --label gap --label "priority::medium" \
  --description "8-bit C1 controls (0x9B CSI, 0x9D OSC, 0x9C ST, 0x90 DCS) passed isUnsafeControlChar, the renderPrompt loop, and the search display verbatim -> terminal escape injection on C1-honoring terminals (APPSEC-02, docs/APPSEC_REVIEW_2026-06-12.md §8). FIXED: UTF-8-aware filtering in appendHistoryFiltered + displaySpan-based render sanitization. See commits in this branch."
# capture the printed issue number, then:
glab issue close <NUM> --repo devnw/zig/repl

glab issue create --repo devnw/zig/repl \
  --title "GAP-0075: sanitizePasteContent missed 8-bit and zero-padded paste markers" \
  --label security --label gap --label "priority::medium" \
  --description "Only canonical 6-byte ESC[200~/201~ forms were stripped; \\x9b201~ and ESC[0200~ variants bypassed (APPSEC-03). FIXED: pasteMarkerLen recognizes 7-bit/8-bit introducers + zero-padded params."
glab issue close <NUM> --repo devnw/zig/repl

glab issue create --repo devnw/zig/repl \
  --title "GAP-0076: parse.zig i32 depth counters could wrap on pathological input" \
  --label gap --label "priority::low" \
  --description "Theoretical (~2GB single-slice input) i32 wrap in ReleaseFast / trap in ReleaseSafe (APPSEC-07). FIXED: counters widened to i64."
glab issue close <NUM> --repo devnw/zig/repl
```

- [ ] **Step 2: Update `docs/GAP_ANALYSIS.md`** — bump header to "Next Gap-ID: GAP-0077"; note GAP-0074/0075/0076 as resolved this cycle (Audit Cycle 4) with commit refs; correct the Cycle-3 note that claimed GAP-0066/0067 resolved (they were not — fixed now in Task 18). Move resolved entries to `docs/GAP_ANALYSIS_RESOLVED.md` following its existing format.

- [ ] **Step 3: Update `docs/SECURITY_GAP_ANALYSIS.md`** — add a Cycle-4 changelog entry: GAP-0074/0075 fixed (C1 + paste markers), ADV-002/#147 fixed (enterRawMode errdefer), APPSEC-04 invariant hardened with property test, APPSEC-07/GAP-0076 fixed (i64). Keep its established table format.

- [ ] **Step 4: Update `docs/APPSEC_REVIEW_2026-06-12.md` §8 residual table** — mark every residual row fixed with commit SHAs.

- [ ] **Step 5: Final full validation**

```bash
zig build test --summary all          # PASS, 1 skipped
zig build test -Doptimize=ReleaseSafe --summary all 2>&1 | tail -3   # PASS
zig fmt --check src/ tests/ examples/ build.zig                      # exit 0
pre-commit run --all-files            # all Passed/Skipped
```

- [ ] **Step 6: Commit docs + push everything**

```bash
git add docs/
git commit -m "docs: record Audit Cycle 4 gap closures (GAP-0074..0076, QF-091..113 batch)"
git push origin main
```

---

## Deferred / explicitly out of scope (tracked, not closed by this plan)

- #162 (QF-106 long functions), #167 (QF-111 deep nesting), #160 (QF-104 keymap duck-typing), #141/#139/#138/#137 (long-function refactors) — tracked refactors, Low, no behavior impact.
- #128–#135, #69, #77, #78 (perf enhancements) — tracked/deferred in PERF_GAP_ANALYSIS.md.
- #52 (core-loop coverage) — partially improved by d039c05's testable loop + this plan's tests; full PTY harness remains tracked.
- #31 (release signing), GAP-0052/GAP-0073 — blocked/deferred gaps.
- Feature requests #6–#26 — features, not audit gaps.
