// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Core REPL implementation
//!
//! The main REPL loop with:
//! - Raw terminal mode
//! - Input processing and key event parsing
//! - Multi-line input support
//! - Prompt rendering

const std = @import("std");
const compat = @import("compat.zig");
const platform = @import("platform.zig");
const history_mod = @import("history.zig");
const completion = @import("completion.zig");
const parse = @import("parse.zig");
const keymap_emacs = @import("keymap_emacs.zig");
const keymap_vi = @import("keymap_vi.zig");
const text_utils = @import("text_utils.zig");
const render = @import("render.zig");
const input_mod = @import("input.zig");
const undo_mod = @import("undo.zig");
const observability = @import("observability");

const findWordStart = text_utils.findWordStart;
const findWordEnd = text_utils.findWordEnd;
const isUnsafeControlChar = text_utils.isUnsafeControlChar;
const appendHistoryFiltered = text_utils.appendHistoryFiltered;
const sanitizePasteContent = text_utils.sanitizePasteContent;

/// Size of the fixed buffer used for batching terminal render output.
const RENDER_BUF_SIZE = 8192;

/// Size of the fixed buffer used for accumulating bracketed-paste content.
const PASTE_BUF_SIZE = 4096;

/// Longest bracketed-paste marker is 6 bytes (`\x1b[200~` / `\x1b[201~`); a
/// marker torn across a read boundary leaves at most 5 trailing bytes to carry
/// into the next read.
const PASTE_CARRY_MAX = 5;

/// Safety bound: if `in_bracketed_paste` stays true across more reads than this
/// without ever seeing a complete end marker, force-exit paste mode so a
/// malformed/torn `\x1b[201~` cannot wedge the REPL indefinitely (ADV-001).
/// A real paste streams its end marker within a handful of reads; 4096 reads of
/// up-to-256 bytes is ~1 MiB of unterminated paste, far beyond any legitimate
/// interactive paste, so reaching it means the terminal never sent (or we lost)
/// the end marker.
const PASTE_MAX_READS_WITHOUT_END = 4096;

/// Hard cap on total bytes accumulated in a single paste before we force-exit
/// paste mode (ADV-001). Independent of PASTE_BUF_SIZE flush cycles: this counts
/// cumulative paste bytes across flushes. 16 MiB is generous for an interactive
/// paste yet bounded so a stuck end marker cannot grow memory without limit.
const PASTE_MAX_TOTAL_BYTES = 16 * 1024 * 1024;

/// Persistent bracketed-paste accumulation state.
///
/// Hoisted out of the per-`read(2)` loop in `processInput` so paste content and
/// torn markers survive across read boundaries (ADV-001 / issue #142). Without
/// this, a paste larger than the OS read buffer, or an end marker split across
/// two reads, either lost data or wedged the REPL in paste mode forever.
const PasteState = struct {
    /// Accumulated paste content not yet flushed into the edit buffer.
    buf: [PASTE_BUF_SIZE]u8 = undefined,
    /// Number of valid bytes in `buf`.
    len: usize = 0,
    /// Bytes held back because they form a proper prefix of a paste marker that
    /// was torn across a read boundary; prepended to the next read's data.
    carry: [PASTE_CARRY_MAX]u8 = undefined,
    /// Number of valid bytes in `carry`.
    carry_len: usize = 0,
    /// Number of consecutive reads spent in paste mode without seeing an end
    /// marker. Reset to 0 whenever a complete end marker is consumed.
    reads_in_paste: usize = 0,
    /// Cumulative paste-content bytes seen for the current paste, counted across
    /// flush cycles (so it reflects TOTAL size, not just unflushed `len`). Reset
    /// to 0 when a paste closes (end marker consumed or force-exit), so it is 0
    /// at the start of the next paste.
    total_bytes: usize = 0,

    /// Force-exit paste mode: flush whatever was collected and clear paste
    /// flags so the prompt recovers. Used by the safety bounds.
    fn forceExit(self: *PasteState, state: *ReplState, last_action: *KeyAction) void {
        if (self.len > 0) {
            flushPasteBuffer(state, &self.buf, &self.len, last_action);
        }
        state.in_bracketed_paste = false;
        state.paste_strip_leading = false;
        self.reads_in_paste = 0;
        self.total_bytes = 0;
        self.carry_len = 0;
    }
};

/// Keymap selection.
/// Unified with Config.Keymap from config.zig; includes fromString() for parsing.
pub const Keymap = @import("config.zig").Config.Keymap;

/// Output format.
/// Unified with Config.Format from config.zig; includes fromString() for parsing.
pub const Format = @import("config.zig").Config.Format;

/// Key event from terminal input (defined in input.zig)
pub const KeyEvent = input_mod.KeyEvent;

/// Named constants for synthetic key codes (Insert, Delete, Page Up, Page Down).
/// Defined in input.zig; re-exported for consumers of the public API.
pub const SyntheticKey = input_mod.SyntheticKey;

/// Action to perform in response to a key
pub const KeyAction = enum {
    none,
    insert,
    insert_tab,
    reverse_tab,
    backspace,
    delete_char,
    delete_char_forward,
    delete_word,
    delete_word_backward,
    delete_to_eol,
    delete_to_bol,
    move_left,
    move_right,
    move_word_left,
    move_word_right,
    move_bol,
    move_eol,
    history_prev,
    history_next,
    history_first,
    history_last,
    search,
    complete,
    run,
    cancel,
    quit,
    yank,
    undo,
    clear_screen,
    vi_normal_mode,
    vi_insert_mode,
};

/// Command handler function type.
/// Called when user presses Enter with input.
/// The first parameter is a pointer to user_context (passed via Options).
/// The second parameter is the allocator.
/// The third parameter is the input text.
/// The fourth parameter is the history store for saving entries.
/// Returns true to continue REPL, false to exit.
pub const RunFn = *const fn (user_context: ?*anyopaque, allocator: std.mem.Allocator, input: []const u8, history: *history_mod.HistoryStore) anyerror!bool;

/// Statement completion checker function type.
/// Returns true if the input is a complete statement.
pub const IsCompleteFn = *const fn (input: []const u8) bool;

/// Tab completion function type.
/// Given a prefix, adds completion candidates to the context.
pub const CompleteFn = *const fn (prefix: []const u8, ctx: *completion.CompletionContext) void;

/// Welcome message printer function type.
pub const WelcomeFn = *const fn (stdout: std.Io.File, use_color: bool) anyerror!void;

/// Main REPL interface
pub const Repl = struct {
    /// REPL configuration options
    pub const Options = struct {
        /// Memory allocator
        allocator: std.mem.Allocator,
        /// Normal prompt string (e.g., ">>> ")
        prompt: []const u8 = "> ",
        /// Continuation prompt for multi-line input
        continuation_prompt: []const u8 = "... ",
        /// Keybinding mode
        keymap: Keymap = .emacs,
        /// Enable command history
        history_enabled: bool = true,
        /// Application name (used for history file path)
        app_name: []const u8 = "repl",
        /// Custom history file path (optional)
        history_path: ?[]const u8 = null,
        /// Command handler function
        run_fn: ?RunFn = null,
        /// Statement completion checker (for multi-line input)
        is_complete_fn: ?IsCompleteFn = null,
        /// Tab completion function
        complete_fn: ?CompleteFn = null,
        /// Welcome message printer
        welcome_fn: ?WelcomeFn = null,
        /// Show verbose output
        verbose: bool = false,
        /// User context data (passed to callbacks)
        user_context: ?*anyopaque = null,
    };

    /// Run the REPL with the given options.
    pub fn run(opts: Options) !void {
        // Check for TTY
        if (!platform.isStdinTty()) {
            const stderr = platform.getStderrHandle();
            try compat.writeAll(stderr, "Error: interactive shell requires a TTY\n");
            return error.NotATty;
        }

        // Print welcome message BEFORE entering raw mode
        if (opts.welcome_fn) |welcome| {
            const stdout = platform.getStdoutHandle();
            try welcome(stdout, platform.shouldUseColor());
        }

        // Setup terminal (raw mode)
        const original_termios = try platform.enterRawMode();
        defer platform.restoreTerminalMode(original_termios) catch {};

        // Initialize history
        const hist_path = if (opts.history_path) |p|
            try opts.allocator.dupe(u8, p)
        else if (opts.history_enabled)
            try history_mod.getDefaultHistoryPath(opts.allocator, opts.app_name)
        else
            null;
        defer if (hist_path) |path| opts.allocator.free(path);

        var hist = try history_mod.HistoryStore.init(opts.allocator, hist_path, opts.history_enabled);
        defer hist.deinit();

        if (opts.history_enabled) {
            try hist.load();
        }

        // Initialize state
        var state = ReplState{
            .allocator = opts.allocator,
            .buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
            .cursor = 0,
            .history = &hist,
            .history_index = null,
            .keymap = opts.keymap,
            .vi_mode = .insert,
            .quit_requested = false,
            .kill_ring = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
            .last_was_kill = false,
            .undo_stack = undo_mod.UndoStack.init(opts.allocator, undo_mod.UndoStack.default_max_entries),
            .search_buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
            .searching = false,
            .completion_ctx = completion.CompletionContext.init(opts.allocator),
            .multi_line_buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
            .is_continuation = false,
            .prompt = opts.prompt,
            .continuation_prompt = opts.continuation_prompt,
            .run_fn = opts.run_fn,
            .is_complete_fn = opts.is_complete_fn orelse parse.isComplete,
            .complete_fn = opts.complete_fn,
            .user_context = opts.user_context,
            .verbose = opts.verbose,
        };
        defer state.deinit();

        // Main loop
        while (!state.quit_requested) {
            try renderPrompt(&state);
            try processInput(&state);
        }

        // Final newline
        const stdout = platform.getStdoutHandle();
        compat.writeAll(stdout, "\r\n") catch {};
    }
};

/// REPL state during a session
pub const ReplState = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    cursor: usize,
    history: *history_mod.HistoryStore,
    history_index: ?usize,
    keymap: Keymap,
    vi_mode: keymap_vi.ViMode,
    quit_requested: bool,
    kill_ring: std.ArrayList(u8),
    last_was_kill: bool,
    undo_stack: undo_mod.UndoStack,
    search_buffer: std.ArrayList(u8),
    searching: bool,
    completion_ctx: completion.CompletionContext,
    pending_operator: ?u8 = null,
    multi_line_buffer: std.ArrayList(u8),
    is_continuation: bool,
    in_bracketed_paste: bool = false,
    paste_strip_leading: bool = false,
    content_changed: bool = true,
    last_buffer_len: usize = 0,
    last_visual_lines: usize = 0,
    last_cursor_row: usize = 0,

    // Configuration
    prompt: []const u8,
    continuation_prompt: []const u8,
    run_fn: ?RunFn,
    is_complete_fn: *const fn (input: []const u8) bool,
    complete_fn: ?CompleteFn,
    user_context: ?*anyopaque,
    verbose: bool,

    /// Release all resources owned by the REPL state (buffers, undo stack, history store).
    pub fn deinit(self: *ReplState) void {
        self.buffer.deinit(self.allocator);
        self.kill_ring.deinit(self.allocator);
        self.undo_stack.deinit();
        self.search_buffer.deinit(self.allocator);
        self.multi_line_buffer.deinit(self.allocator);
        self.completion_ctx.deinit();
    }

    /// Get the current prompt string
    pub fn getPrompt(self: *const ReplState) []const u8 {
        return if (self.is_continuation) self.continuation_prompt else self.prompt;
    }
};

fn renderPrompt(state: *ReplState) !void {
    const stdout = platform.getStdoutHandle();
    const term_width = platform.getTerminalWidth();

    const prompt = state.getPrompt();

    // Accumulate all render output into a fixed buffer, then issue a single write.
    // If the buffer fills, we stop writing and output the valid partial content.
    var render_buf: [RENDER_BUF_SIZE]u8 = undefined;
    var fbs = compat.FixedBufferStream.init(&render_buf);
    const w = fbs.writer();

    var buffer_full = false;

    // Move cursor up from current row to start
    if (state.last_cursor_row > 0) {
        w.print("\x1b[{d}A", .{state.last_cursor_row}) catch {
            buffer_full = true;
        };
    }

    // Clear from cursor to end of screen
    if (!buffer_full) w.writeAll("\r\x1b[J") catch {
        buffer_full = true;
    };

    // Write prompt
    if (!buffer_full) w.writeAll(prompt) catch {
        buffer_full = true;
    };

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
                // Control characters and DEL - show visual indicator
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

    // Single-pass calculation of visual lines and cursor position (PF-009).
    const render_info = render.calculateRenderInfo(prompt.len, state.buffer.items, state.cursor, term_width);
    const current_visual_lines = render_info.visual_lines;

    // Position cursor -- only if the buffer has not overflowed, since writing
    // partial ANSI escape sequences would corrupt the terminal.
    if (!buffer_full) {
        const cursor_pos = render_info.cursor_pos;

        if (cursor_pos.rows_from_end > 0) {
            w.print("\x1b[{d}A", .{cursor_pos.rows_from_end}) catch {
                buffer_full = true;
            };
        }

        if (!buffer_full) {
            w.print("\r\x1b[{d}C", .{cursor_pos.col}) catch {
                buffer_full = true;
            };
        }

        // Single write for entire render output
        try compat.writeAll(stdout, fbs.getWritten());

        // Update tracking state
        state.last_cursor_row = current_visual_lines - cursor_pos.rows_from_end;
    } else {
        // Buffer overflowed -- write the valid partial content we have.
        // Cursor positioning is skipped to avoid broken ANSI sequences.
        try compat.writeAll(stdout, fbs.getWritten());

        // Without cursor positioning, assume cursor is at the end
        state.last_cursor_row = 0;
    }

    state.content_changed = false;
    state.last_buffer_len = state.buffer.items.len;
    state.last_visual_lines = current_visual_lines;
}

fn processInput(state: *ReplState) !void {
    const stdin = platform.getStdinHandle();
    // Read buffer plus room to prepend any carried-over torn-marker bytes from
    // the previous read.
    var buf: [PASTE_CARRY_MAX + 256]u8 = undefined;

    // PasteState is hoisted ABOVE the read loop so paste accumulation and torn
    // markers persist across `read(2)` boundaries (ADV-001 / issue #142).
    var paste_state = PasteState{};

    outer: while (true) {
        // Read fresh data after any carried-over bytes, so the carry (a torn
        // marker prefix from the previous read) can be re-examined contiguously.
        const carry_len = paste_state.carry_len;
        const n = try compat.read(stdin, buf[carry_len .. carry_len + 256]);
        // No new data: leave any carry intact for the next non-empty read
        // rather than reprocessing it in a tight loop.
        if (n == 0) continue;

        // Now that we have fresh bytes, prepend the carry contiguously.
        if (carry_len > 0) {
            @memcpy(buf[0..carry_len], paste_state.carry[0..carry_len]);
            paste_state.carry_len = 0;
        }
        const total = carry_len + n;

        var last_action: KeyAction = .none;
        processReadBuffer(state, &paste_state, buf[0..total], &last_action) catch break;

        if (!state.in_bracketed_paste and !platform.stdinHasMoreData()) {
            renderPrompt(state) catch |err| {
                if (err == error.BrokenPipe) {
                    state.quit_requested = true;
                    break :outer;
                }
            };
        }

        if (last_action == .run) {
            try handleCommandSubmission(state);
            break :outer;
        }
        if (last_action == .cancel) {
            try handleCancellation(state);
            break :outer;
        }
        if (last_action == .quit and state.buffer.items.len == 0) {
            state.quit_requested = true;
            break :outer;
        }
    }
}

/// Process one read's worth of input bytes against the persistent REPL and
/// paste state. Extracted from `processInput` so it is unit-testable without a
/// TTY (GAP-0072 / #52): tests feed scripted byte slices and assert on
/// `state.buffer`/`state.cursor`/`last_action`.
///
/// `data` is one logical read (carried-over torn-marker bytes already
/// prepended). On return, any trailing proper-prefix of a paste marker has been
/// moved into `paste_state.carry` to be re-examined with the next read.
///
/// Paste-mode safety bounds (ADV-001): if paste mode persists across too many
/// reads with no end marker, or total paste bytes exceed a hard cap, we
/// force-exit paste mode so a torn/malformed end marker cannot wedge the REPL.
fn processReadBuffer(
    state: *ReplState,
    paste_state: *PasteState,
    data: []const u8,
    last_action: *KeyAction,
) !void {
    // Per-read paste-mode safety accounting (ADV-001).
    const was_in_paste = state.in_bracketed_paste;
    if (was_in_paste) {
        paste_state.reads_in_paste += 1;
        if (paste_state.reads_in_paste > PASTE_MAX_READS_WITHOUT_END) {
            paste_state.forceExit(state, last_action);
        }
    }

    // Hold back a trailing proper-prefix of a paste marker so it is not
    // misinterpreted as paste content / a torn escape (ADV-001). The carried
    // bytes are re-examined prepended to the next read.
    const usable = carryOverSplit(data, paste_state, state.in_bracketed_paste);

    var i: usize = 0;
    while (i < usable) {
        const before = i;
        const was_pasting = state.in_bracketed_paste;
        if (consumeBracketedPaste(data[0..usable], &i, state, &paste_state.buf, &paste_state.len, last_action)) {
            if (state.in_bracketed_paste) {
                // Count cumulative paste-content bytes consumed this step
                // (i advanced by 1 per content byte; marker handling toggles
                // the flag). This survives flush cycles where paste_state.len
                // resets, so the hard cap reflects TOTAL paste size (ADV-001).
                if (was_pasting) paste_state.total_bytes += (i - before);
                if (paste_state.total_bytes > PASTE_MAX_TOTAL_BYTES) {
                    paste_state.forceExit(state, last_action);
                }
            } else {
                // End marker consumed (or never entered paste): paste closed.
                paste_state.reads_in_paste = 0;
                paste_state.total_bytes = 0;
            }
            continue;
        }

        const remaining = data[i..usable];
        const key_event = parseKeyEvent(remaining) catch break;
        i += getKeyEventLength(remaining);

        // Snapshot the pre-edit buffer LAZILY: only keys that *can* mutate the
        // buffer take a snapshot (perf NEW-1). Pure cursor moves / history nav
        // no longer dupe+memcpy+free the whole line on every keystroke.
        //
        // The snapshot is taken BEFORE the keymap handler because some keymaps
        // (emacs/vi) mutate the buffer in-place inside handleKey for inserts.
        // Whether to KEEP the snapshot is decided AFTER processAction, since
        // delete-class actions mutate inside processAction -- comparing the
        // pre-state against the final buffer is the only point that correctly
        // detects a real change for both insert- and delete-class actions.
        const may_mutate = keyMayMutate(state, key_event);
        const pre_buffer: ?[]u8 = if (may_mutate)
            (state.allocator.dupe(u8, state.buffer.items) catch null)
        else
            null;
        const pre_cursor = state.cursor;

        const action = switch (state.keymap) {
            .emacs => keymap_emacs.handleKey(state, key_event),
            .vi => keymap_vi.handleKey(state, key_event),
        };

        // Determine if this action modifies buffer content.
        const is_destructive = switch (action) {
            .insert, .insert_tab, .reverse_tab, .backspace, .delete_char, .delete_char_forward, .delete_word, .delete_word_backward, .delete_to_eol, .delete_to_bol, .yank => true,
            else => false,
        };

        processAction(state, action) catch {
            if (pre_buffer) |buf_snap| state.allocator.free(buf_snap);
            break;
        };
        last_action.* = action;

        if (pre_buffer) |buf_snap| {
            // Keep the snapshot only if the action was destructive AND the
            // buffer actually changed (perf NEW-2: skip dead undo entries for
            // no-op edits such as backspace-at-BOL or delete-at-EOL).
            const changed = is_destructive and !std.mem.eql(u8, buf_snap, state.buffer.items);
            if (changed) {
                // pushOwned takes ownership; no extra free needed.
                state.undo_stack.pushOwned(buf_snap, pre_cursor) catch {
                    // On error, we still own the buffer.
                    state.allocator.free(buf_snap);
                };
            } else {
                state.allocator.free(buf_snap);
            }
        }
    }
}

/// Returns the number of leading bytes of `data` that are safe to process now.
/// If `data` ends with a proper (incomplete) prefix of a bracketed-paste marker
/// (`\x1b[200~` / `\x1b[201~`), those trailing bytes are copied into
/// `paste_state.carry` and excluded so the torn marker can be re-assembled with
/// the next read (ADV-001).
///
/// `in_paste` selects the conservative handling of a lone trailing `\x1b`:
/// outside paste mode a bare ESC is processed immediately (preserving the
/// terminal's existing ESC-key latency, important for vi mode-switching); in
/// paste mode it is held back because it may begin a torn end marker.
fn carryOverSplit(data: []const u8, paste_state: *PasteState, in_paste: bool) usize {
    // Examine up to the last PASTE_CARRY_MAX bytes for an ESC-led proper prefix
    // of a marker. The earliest such ESC position gives the longest carry.
    const start = if (data.len > PASTE_CARRY_MAX) data.len - PASTE_CARRY_MAX else 0;
    var p = start;
    while (p < data.len) : (p += 1) {
        if (data[p] != 0x1b) continue;
        const tail = data[p..];
        // A complete marker (6 bytes) is NOT carried -- it is consumed normally.
        if (tail.len >= 6) {
            // Could still be an ESC that is not a marker; let normal parsing
            // handle it. Only carry strict proper-prefixes (len 1..5).
            continue;
        }
        // A lone trailing ESC outside paste mode is left for immediate handling
        // (bare-ESC key); only carry it when a torn end marker is possible.
        if (tail.len == 1 and !in_paste) break;
        if (isMarkerPrefix(tail)) {
            @memcpy(paste_state.carry[0..tail.len], tail);
            paste_state.carry_len = tail.len;
            return p;
        }
        // ESC found but not a marker prefix: leave it for normal parsing.
        break;
    }
    return data.len;
}

/// True if `s` (length 1..5) is a proper prefix of `\x1b[200~` or `\x1b[201~`.
fn isMarkerPrefix(s: []const u8) bool {
    if (s.len == 0 or s.len >= 6) return false;
    const start_marker = "\x1b[200~";
    const end_marker = "\x1b[201~";
    return std.mem.eql(u8, s, start_marker[0..s.len]) or
        std.mem.eql(u8, s, end_marker[0..s.len]);
}

/// Cheap pre-handler prediction of whether a key event can mutate the edit
/// buffer, so we only snapshot for undo when a mutation is actually possible
/// (perf NEW-1). Pure navigation, history nav, control, and unknown keys return
/// false and skip the dupe+memcpy+free entirely.
///
/// CORRECTNESS CONTRACT: this MUST be a conservative over-approximation. It is
/// only allowed to return `false` for keys that can NEVER mutate the buffer in
/// the given keymap/mode; returning `false` for a mutating key would silently
/// break undo. It is free to return `true` for keys that turn out non-mutating
/// (e.g. backspace-at-BOL) -- the post-handler "did the buffer actually change"
/// check in `processReadBuffer` discards those dead snapshots (perf NEW-2).
///
/// Keep this in sync with keymap_emacs.handleKey / keymap_vi.handleKey: when in
/// doubt for a key, return true.
fn keyMayMutate(state: *const ReplState, key_event: KeyEvent) bool {
    return switch (state.keymap) {
        .emacs => emacsKeyMayMutate(key_event),
        .vi => viKeyMayMutate(state.vi_mode, state.pending_operator, key_event),
    };
}

/// Conservative mutation predictor for the Emacs keymap. Mirrors the
/// destructive arms of keymap_emacs.handleKey (insert / backspace / delete* /
/// reverse_tab / yank). Everything else (movement, history, search, complete,
/// clear, run/cancel/quit, ESC, unknown) is non-mutating.
fn emacsKeyMayMutate(key: KeyEvent) bool {
    if (key.ctrl and key.alt) {
        // Only Shift+Tab (reverse_tab) mutates here.
        return key.key == 'i';
    }
    if (key.ctrl) {
        return switch (key.key) {
            // delete_char/quit (d), delete_to_eol (k), delete_to_bol (u),
            // delete_word_backward (w), yank (y), undo restores buffer (0x7f).
            'd', 'k', 'u', 'w', 'y', 0x7f => true,
            else => false,
        };
    }
    if (key.alt) {
        return switch (key.key) {
            'd', 'w' => true, // delete_word / delete_word_backward
            else => false,
        };
    }
    // Printable insert.
    if (key.key >= 0x20 and key.key < 0x7f) return true;
    // Backspace (DEL/BS) and forward Delete mutate.
    return switch (key.key) {
        0x7f, 0x08, input_mod.SyntheticKey.delete => true,
        else => false,
    };
}

/// Conservative mutation predictor for the Vi keymap. Because Vi normal mode
/// mutates the buffer directly inside handleKey for many commands (o, O, dd,
/// dw, db, de, cc, cw, r<char>, s, S, x, X, p, ...), and a pending operator
/// makes the NEXT key destructive, this errs heavily toward `true` in normal
/// mode and only excludes keys that are unambiguously pure motion / mode
/// switches / history nav. Insert mode mirrors the Emacs predictor.
fn viKeyMayMutate(vi_mode: keymap_vi.ViMode, pending_operator: ?u8, key: KeyEvent) bool {
    switch (vi_mode) {
        .insert => {
            if (key.ctrl and key.alt) return key.key == 'i'; // reverse_tab
            if (key.ctrl) {
                return switch (key.key) {
                    'd', 'w', 'u', 'k', 'y' => true,
                    else => false,
                };
            }
            if (key.alt) return key.key == 'd';
            if (key.key >= 0x20 and key.key < 0x7f) return true;
            return switch (key.key) {
                0x7f, 0x08, input_mod.SyntheticKey.delete => true,
                else => false,
            };
        },
        .normal => {
            // A pending operator (d/c/r) makes the NEXT key destructive
            // (e.g. de, cw, r<char>); always snapshot.
            if (pending_operator != null) return true;
            if (key.ctrl and key.alt) return key.key == 'i'; // reverse_tab
            if (key.ctrl) {
                // Only Ctrl+D can mutate (delete_char) in normal mode.
                return key.key == 'd';
            }
            if (key.alt) return false; // word motions only
            // Pure-motion / mode / history / non-mutating normal-mode keys.
            // Anything NOT in this allow-list is treated as possibly mutating,
            // covering pending-operator state and direct-mutation commands.
            return switch (key.key) {
                'h', 'l', 'j', 'k', '0', '^', '$', 'w', 'b', 'e', 'G', 'g', 0x1b => false,
                else => true,
            };
        },
    }
}

/// Reset input state after a command is processed or cancelled.
fn resetLineState(state: *ReplState) void {
    state.buffer.clearRetainingCapacity();
    state.cursor = 0;
    state.undo_stack.clear();
    state.last_visual_lines = 0;
    state.last_cursor_row = 0;
    state.content_changed = true;
}

/// Handle bracketed paste sequences and character collection.
/// Returns true if the current byte was consumed (caller should `continue`).
///
/// When the paste buffer fills before the end marker is seen, the accumulated
/// content is flushed into `state.buffer` (after sanitization) and collection
/// continues. This allows pastes of arbitrary size without dynamic allocation.
fn consumeBracketedPaste(
    buf: []const u8,
    i: *usize,
    state: *ReplState,
    paste_buf: *[PASTE_BUF_SIZE]u8,
    paste_len: *usize,
    last_action: *KeyAction,
) bool {
    // Check for paste start: ESC[200~
    if (i.* + 5 < buf.len and std.mem.eql(u8, buf[i.*..][0..6], "\x1b[200~")) {
        state.in_bracketed_paste = true;
        state.paste_strip_leading = true;
        paste_len.* = 0;
        i.* += 6;
        return true;
    }
    // Check for paste end: ESC[201~
    if (i.* + 5 < buf.len and std.mem.eql(u8, buf[i.*..][0..6], "\x1b[201~")) {
        state.in_bracketed_paste = false;
        state.paste_strip_leading = false;
        if (paste_len.* > 0) {
            flushPasteBuffer(state, paste_buf, paste_len, last_action);
        }
        i.* += 6;
        return true;
    }
    // Collect characters while in paste mode
    if (state.in_bracketed_paste) {
        const c = buf[i.*];
        if (c != '\r') {
            if (state.paste_strip_leading and (c == ' ' or c == '\t')) {
                // skip leading whitespace
            } else {
                state.paste_strip_leading = false;
                if (c == '\n' or c == '\t' or c >= 0x20) {
                    // Flush the paste buffer when full to handle arbitrarily large pastes
                    if (paste_len.* >= paste_buf.len) {
                        flushPasteBuffer(state, paste_buf, paste_len, last_action);
                    }
                    paste_buf[paste_len.*] = c;
                    paste_len.* += 1;
                }
            }
        }
        i.* += 1;
        return true;
    }
    return false;
}

/// Flush accumulated paste buffer content into the edit buffer after sanitization.
/// Resets `paste_len` to 0 so collection can continue.
fn flushPasteBuffer(
    state: *ReplState,
    paste_buf: *[PASTE_BUF_SIZE]u8,
    paste_len: *usize,
    last_action: *KeyAction,
) void {
    const data = paste_buf[0..paste_len.*];
    const sanitized = sanitizePasteContent(data);
    state.buffer.insertSlice(state.allocator, state.cursor, sanitized) catch return;
    state.cursor += sanitized.len;
    state.content_changed = true;
    last_action.* = .insert;
    paste_len.* = 0;
}

/// Append current buffer to multi-line buffer, handling continuation.
fn appendToMultiLine(state: *ReplState, input: []const u8) !void {
    if (state.is_continuation) {
        try state.multi_line_buffer.append(state.allocator, '\n');
        try state.multi_line_buffer.appendSlice(state.allocator, input);
    } else {
        state.multi_line_buffer.clearRetainingCapacity();
        try state.multi_line_buffer.appendSlice(state.allocator, input);
    }
}

/// Handle the .run action: backslash continuation, command dispatch, history.
fn handleCommandSubmission(state: *ReplState) !void {
    const input = state.buffer.items;
    if (input.len == 0) return;

    // Check for backslash continuation
    if (input[input.len - 1] == '\\') {
        _ = state.buffer.pop();
        try appendToMultiLine(state, state.buffer.items);
        state.is_continuation = true;
        resetLineState(state);
        const stdout = platform.getStdoutHandle();
        try compat.writeAll(stdout, "\r\n");
        return;
    }

    try appendToMultiLine(state, input);
    const complete_input = state.multi_line_buffer.items;

    if (state.is_complete_fn(complete_input)) {
        // Save to history (skip commands starting with space for privacy)
        if (complete_input.len > 0 and complete_input[0] != ' ') {
            state.history.append(complete_input) catch |err| {
                if (state.verbose) {
                    const stderr = platform.getStderrHandle();
                    compat.writeAll(stderr, "Warning: failed to append to history: ") catch {};
                    compat.writeAll(stderr, @errorName(err)) catch {};
                    compat.writeAll(stderr, "\r\n") catch {};
                }
            };
        }

        const stdout = platform.getStdoutHandle();
        try compat.writeAll(stdout, "\r\n");

        if (state.run_fn) |handler| {
            // One span per eval cycle. PII INVARIANT: do NOT pass
            // `complete_input` (the raw user-typed line) to the seam —
            // REPL inputs may carry passwords, tokens, or file paths.
            // The seam itself accepts no input strings; the only string
            // we ever attach is `error_kind`, a bounded-cardinality
            // category label.
            const span = observability.startEvalSpan();
            var ok: bool = true;
            var error_kind: []const u8 = "ok";
            const should_continue = handler(state.user_context, state.allocator, complete_input, state.history) catch |err| blk: {
                ok = false;
                // The handler error name is bounded by the consumer's
                // declared error set; safe to use as a category label.
                error_kind = @errorName(err);
                const stderr = platform.getStderrHandle();
                compat.writeAll(stderr, "Error: ") catch {};
                compat.writeAll(stderr, @errorName(err)) catch {};
                compat.writeAll(stderr, "\r\n") catch {};
                break :blk true;
            };
            observability.endEvalSpan(span, ok, error_kind);
            if (!should_continue) state.quit_requested = true;
        }

        resetLineState(state);
        state.is_continuation = false;
        state.multi_line_buffer.clearRetainingCapacity();
        state.history_index = null;
    } else {
        state.is_continuation = true;
        resetLineState(state);
        const stdout = platform.getStdoutHandle();
        try compat.writeAll(stdout, "\r\n");
    }
}

/// Handle the .cancel action: Ctrl+C behavior.
fn handleCancellation(state: *ReplState) !void {
    const stdout = platform.getStdoutHandle();
    if (state.buffer.items.len == 0 and !state.is_continuation) {
        try compat.writeAll(stdout, "\r\n^C\r\n");
        state.quit_requested = true;
    } else {
        state.is_continuation = false;
        state.multi_line_buffer.clearRetainingCapacity();
        resetLineState(state);
        try compat.writeAll(stdout, "\r\n^C\r\n");
    }
}

const parseKeyEvent = input_mod.parseKeyEvent;
const getKeyEventLength = input_mod.getKeyEventLength;

fn processAction(state: *ReplState, action: KeyAction) !void {
    const content_modifying = switch (action) {
        .move_left, .move_right, .move_word_left, .move_word_right, .move_bol, .move_eol, .none, .history_prev, .history_next, .history_first, .history_last, .clear_screen => false,
        else => true,
    };
    if (content_modifying) {
        state.content_changed = true;
    }

    if (content_modifying and action != .complete) {
        state.completion_ctx.reset();
    }

    switch (action) {
        .none => {},
        .insert => {},
        .insert_tab => {
            state.buffer.insert(state.allocator, state.cursor, '\t') catch return;
            state.cursor += 1;
        },
        .reverse_tab => handleUnindent(state),
        .backspace => {
            if (state.cursor > 0) {
                state.cursor -= 1;
                _ = state.buffer.orderedRemove(state.cursor);
            }
        },
        .delete_char, .delete_char_forward => {
            if (state.cursor < state.buffer.items.len) {
                _ = state.buffer.orderedRemove(state.cursor);
            }
        },
        .delete_word => {
            const end = findWordEnd(state.buffer.items, state.cursor);
            if (end > state.cursor) {
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..end]) catch {};
                state.last_was_kill = true;
                // Single O(n) replaceRange instead of O(n*w) orderedRemove loop
                // Shrinking replaceRange with empty replacement cannot allocate.
                state.buffer.replaceRange(state.allocator, state.cursor, end - state.cursor, &.{}) catch unreachable;
            }
        },
        .delete_word_backward => {
            const start = findWordStart(state.buffer.items, state.cursor);
            if (state.cursor > start) {
                const count = state.cursor - start;
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..state.cursor]) catch {};
                // Single O(n) replaceRange instead of O(n*w) orderedRemove loop
                // Shrinking replaceRange with empty replacement cannot allocate.
                state.buffer.replaceRange(state.allocator, start, count, &.{}) catch unreachable;
                state.cursor = start;
            }
            state.last_was_kill = true;
        },
        .delete_to_eol => {
            state.kill_ring.clearRetainingCapacity();
            state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..]) catch {};
            state.buffer.shrinkRetainingCapacity(state.cursor);
            state.last_was_kill = true;
        },
        .delete_to_bol => {
            state.kill_ring.clearRetainingCapacity();
            state.kill_ring.appendSlice(state.allocator, state.buffer.items[0..state.cursor]) catch {};
            // Single O(n) replaceRange instead of alloc+copy+clear+append cycle
            // Shrinking replaceRange with empty replacement cannot allocate.
            state.buffer.replaceRange(state.allocator, 0, state.cursor, &.{}) catch unreachable;
            state.cursor = 0;
            state.last_was_kill = true;
        },
        .move_left => {
            if (state.cursor > 0) state.cursor -= 1;
        },
        .move_right => {
            if (state.cursor < state.buffer.items.len) state.cursor += 1;
        },
        .move_word_left => {
            state.cursor = findWordStart(state.buffer.items, state.cursor);
        },
        .move_word_right => {
            state.cursor = findWordEnd(state.buffer.items, state.cursor);
        },
        .move_bol => {
            state.cursor = 0;
        },
        .move_eol => {
            state.cursor = state.buffer.items.len;
        },
        .history_prev => {
            if (state.history.entries.items.len > 0) {
                if (state.history_index) |idx| {
                    if (idx > 0) state.history_index = idx - 1;
                } else {
                    state.history_index = state.history.entries.items.len - 1;
                }

                if (state.history_index) |idx| {
                    state.buffer.clearRetainingCapacity();
                    try appendHistoryFiltered(&state.buffer, state.allocator, state.history.entries.items[idx]);
                    state.cursor = state.buffer.items.len;
                }
            }
        },
        .history_next => {
            if (state.history_index) |idx| {
                if (idx < state.history.entries.items.len - 1) {
                    state.history_index = idx + 1;
                    state.buffer.clearRetainingCapacity();
                    try appendHistoryFiltered(&state.buffer, state.allocator, state.history.entries.items[idx + 1]);
                    state.cursor = state.buffer.items.len;
                } else {
                    state.history_index = null;
                    state.buffer.clearRetainingCapacity();
                    state.cursor = 0;
                }
            }
        },
        .history_first => {
            if (state.history.entries.items.len > 0) {
                state.history_index = 0;
                state.buffer.clearRetainingCapacity();
                try appendHistoryFiltered(&state.buffer, state.allocator, state.history.entries.items[0]);
                state.cursor = state.buffer.items.len;
            }
        },
        .history_last => {
            if (state.history.entries.items.len > 0) {
                state.history_index = state.history.entries.items.len - 1;
                state.buffer.clearRetainingCapacity();
                try appendHistoryFiltered(&state.buffer, state.allocator, state.history.entries.items[state.history_index.?]);
                state.cursor = state.buffer.items.len;
            }
        },
        .search => {
            state.searching = true;
            try handleSearch(state);
        },
        .complete => handleCompletion(state),
        .run, .cancel, .quit => {},
        .yank => {
            try state.buffer.insertSlice(state.allocator, state.cursor, state.kill_ring.items);
            state.cursor += state.kill_ring.items.len;
        },
        .undo => {
            if (state.undo_stack.pop()) |entry| {
                state.buffer.clearRetainingCapacity();
                state.buffer.appendSlice(state.allocator, entry.buffer) catch {
                    state.allocator.free(entry.buffer);
                    return;
                };
                state.cursor = entry.cursor;
                state.allocator.free(entry.buffer);
            }
        },
        .clear_screen => {
            const stdout = platform.getStdoutHandle();
            try compat.writeAll(stdout, "\x1b[2J\x1b[H");
            state.last_visual_lines = 0;
            state.last_cursor_row = 0;
            state.content_changed = true;
        },
        .vi_normal_mode, .vi_insert_mode => {},
    }

    if (action != .delete_to_eol and action != .delete_to_bol and
        action != .delete_word and action != .delete_word_backward)
    {
        state.last_was_kill = false;
    }
}

/// Remove one level of leading indentation (tab or up to 4 spaces) from
/// the current line in the edit buffer.
fn handleUnindent(state: *ReplState) void {
    var line_start: usize = state.cursor;
    while (line_start > 0 and state.buffer.items[line_start - 1] != '\n') {
        line_start -= 1;
    }

    if (line_start < state.buffer.items.len) {
        if (state.buffer.items[line_start] == '\t') {
            // Single O(n) replaceRange instead of orderedRemove
            // Shrinking replaceRange with empty replacement cannot allocate.
            state.buffer.replaceRange(state.allocator, line_start, 1, &.{}) catch unreachable;
            if (state.cursor > line_start) state.cursor -= 1;
        } else if (state.buffer.items[line_start] == ' ') {
            // Count leading spaces (up to 4)
            var count: usize = 0;
            while (count < 4 and line_start + count < state.buffer.items.len and state.buffer.items[line_start + count] == ' ') {
                count += 1;
            }
            if (count > 0) {
                // Single O(n) replaceRange instead of orderedRemove loop
                // Shrinking replaceRange with empty replacement cannot allocate.
                state.buffer.replaceRange(state.allocator, line_start, count, &.{}) catch unreachable;
                if (state.cursor > line_start) {
                    state.cursor -= @min(count, state.cursor - line_start);
                }
            }
        }
    }
}

/// Handle tab completion: start a new completion or cycle through candidates.
fn handleCompletion(state: *ReplState) void {
    const complete_fn = state.complete_fn orelse return;
    const ctx = &state.completion_ctx;

    if (!ctx.active) {
        // Start new completion
        ctx.reset();
        ctx.word_start = completion.findWordStart(state.buffer.items, state.cursor);
        const prefix = state.buffer.items[ctx.word_start..state.cursor];

        // Save original prefix
        if (prefix.len > 0) {
            ctx.original_prefix = ctx.arena.allocator().dupe(u8, prefix) catch return;
        }

        // Call user's completion function to populate candidates
        complete_fn(prefix, ctx);

        if (ctx.candidates.items.len > 0) {
            ctx.active = true;
        }
    } else {
        // Already active, cycle to next candidate
        ctx.nextCandidate();
    }

    // Apply current candidate
    if (ctx.getCurrentCandidate()) |candidate| {
        // Remove the current word
        const remove_len = state.cursor - ctx.word_start;
        if (remove_len > 0) {
            // Shrinking replaceRange with empty replacement cannot allocate.
            state.buffer.replaceRange(
                state.allocator,
                ctx.word_start,
                remove_len,
                &.{},
            ) catch unreachable;
            state.cursor = ctx.word_start;
        }

        // Insert the completion
        state.buffer.insertSlice(state.allocator, state.cursor, candidate) catch return;
        state.cursor += candidate.len;
        state.content_changed = true;
    }
}

const handleSearch = @import("search.zig").handleSearch;

// Key parsing tests are in input.zig; sanitization tests in text_utils.zig

// ============================================================================
// Tests for consumeBracketedPaste and renderPrompt buffer handling
// ============================================================================

/// Create a minimal ReplState suitable for testing paste and render logic.
/// The caller must call `deinit()` on the returned state and also deinit
/// the history store.
fn createTestState(allocator: std.mem.Allocator, hist: *history_mod.HistoryStore) ReplState {
    return ReplState{
        .allocator = allocator,
        .buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
        .cursor = 0,
        .history = hist,
        .history_index = null,
        .keymap = .emacs,
        .vi_mode = .insert,
        .quit_requested = false,
        .kill_ring = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
        .last_was_kill = false,
        .undo_stack = undo_mod.UndoStack.init(allocator, undo_mod.UndoStack.default_max_entries),
        .search_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
        .searching = false,
        .completion_ctx = completion.CompletionContext.init(allocator),
        .multi_line_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
        .is_continuation = false,
        .prompt = "> ",
        .continuation_prompt = "... ",
        .run_fn = null,
        .is_complete_fn = parse.isComplete,
        .complete_fn = null,
        .user_context = null,
        .verbose = false,
    };
}

test "consumeBracketedPaste: normal paste within buffer size" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
    var paste_len: usize = 0;
    var last_action: KeyAction = .none;

    // Simulate: ESC[200~ hello ESC[201~
    const input = "\x1b[200~hello\x1b[201~";
    var i: usize = 0;

    // Process all bytes
    while (i < input.len) {
        _ = consumeBracketedPaste(input, &i, &state, &paste_buf, &paste_len, &last_action);
    }

    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(KeyAction.insert, last_action);
    try std.testing.expectEqual(false, state.in_bracketed_paste);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "consumeBracketedPaste: paste exceeding buffer triggers flush" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
    var paste_len: usize = 0;
    var last_action: KeyAction = .none;

    // Build a paste sequence larger than PASTE_BUF_SIZE (4096 bytes).
    // Use 6000 'A' characters to exceed the 4096-byte buffer.
    const content_size = 6000;
    const total_size = 6 + content_size + 6; // start marker + content + end marker
    var input_buf: [total_size]u8 = undefined;
    @memcpy(input_buf[0..6], "\x1b[200~");
    @memset(input_buf[6 .. 6 + content_size], 'A');
    @memcpy(input_buf[6 + content_size ..], "\x1b[201~");

    const input = &input_buf;
    var i: usize = 0;

    while (i < input.len) {
        _ = consumeBracketedPaste(input, &i, &state, &paste_buf, &paste_len, &last_action);
    }

    // The full 6000 bytes should be in the edit buffer (no truncation)
    try std.testing.expectEqual(@as(usize, content_size), state.buffer.items.len);
    try std.testing.expectEqual(@as(usize, content_size), state.cursor);
    try std.testing.expectEqual(false, state.in_bracketed_paste);

    // Verify content is all 'A's
    for (state.buffer.items) |c| {
        try std.testing.expectEqual(@as(u8, 'A'), c);
    }
}

test "consumeBracketedPaste: paste at exact buffer boundary" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
    var paste_len: usize = 0;
    var last_action: KeyAction = .none;

    // Paste exactly PASTE_BUF_SIZE bytes plus 1 more byte to trigger flush
    const content_size = PASTE_BUF_SIZE + 1;
    const total_size = 6 + content_size + 6;
    var input_buf: [total_size]u8 = undefined;
    @memcpy(input_buf[0..6], "\x1b[200~");
    @memset(input_buf[6 .. 6 + content_size], 'B');
    @memcpy(input_buf[6 + content_size ..], "\x1b[201~");

    const input = &input_buf;
    var i: usize = 0;

    while (i < input.len) {
        _ = consumeBracketedPaste(input, &i, &state, &paste_buf, &paste_len, &last_action);
    }

    // All bytes should be present
    try std.testing.expectEqual(@as(usize, content_size), state.buffer.items.len);
    for (state.buffer.items) |c| {
        try std.testing.expectEqual(@as(u8, 'B'), c);
    }
}

test "consumeBracketedPaste: multiple flush cycles for very large paste" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
    var paste_len: usize = 0;
    var last_action: KeyAction = .none;

    // Paste 3x PASTE_BUF_SIZE to trigger multiple flush cycles
    const content_size = PASTE_BUF_SIZE * 3;
    const total_size = 6 + content_size + 6;
    var input_buf: [total_size]u8 = undefined;
    @memcpy(input_buf[0..6], "\x1b[200~");
    // Fill with a pattern so we can verify ordering
    for (0..content_size) |j| {
        input_buf[6 + j] = @as(u8, @intCast(0x41 + (j % 26))); // A-Z repeating
    }
    @memcpy(input_buf[6 + content_size ..], "\x1b[201~");

    const input = &input_buf;
    var i: usize = 0;

    while (i < input.len) {
        _ = consumeBracketedPaste(input, &i, &state, &paste_buf, &paste_len, &last_action);
    }

    // All bytes should be present and in correct order
    try std.testing.expectEqual(@as(usize, content_size), state.buffer.items.len);
    for (state.buffer.items, 0..) |c, j| {
        const expected = @as(u8, @intCast(0x41 + (j % 26)));
        try std.testing.expectEqual(expected, c);
    }
}

test "renderPrompt: buffer overflow produces valid partial output" {
    // This test verifies that the render buffer overflow detection works
    // by checking the fixedBufferStream overflow behavior directly.
    // When a fixedBufferStream is full, writeAll returns NoSpaceLeft.
    // Our render code must stop writing (not silently continue) to avoid
    // broken ANSI escape sequences.
    var buf: [16]u8 = undefined;
    var fbs = compat.FixedBufferStream.init(&buf);
    const w = fbs.writer();

    // Write data that fits
    w.writeAll("\x1b[1A") catch unreachable; // 4 bytes
    w.writeAll("\r\x1b[J") catch unreachable; // 4 bytes -- 8 total
    w.writeAll("> ") catch unreachable; // 2 bytes -- 10 total
    w.writeAll("ABCDE") catch unreachable; // 5 bytes -- 15 total

    // 1 byte remaining. A 2-byte write should fail with NoSpaceLeft.
    const result = w.writeAll("\r\n");
    try std.testing.expectError(error.NoSpaceLeft, result);

    // The buffer should contain exactly what was successfully written (15 bytes).
    // Our FixedBufferStream is atomic: the failed writeAll writes nothing.
    const written = fbs.getWritten();
    try std.testing.expectEqual(@as(usize, 15), written.len);

    // Verify the content is clean
    try std.testing.expectEqualStrings("\x1b[1A\r\x1b[J> ABCDE", written);
}

// ============================================================================
// Tests for processAction -- covers all non-I/O KeyAction variants (QF-026)
// ============================================================================

test "processAction: none and insert are no-ops" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello");
    state.cursor = 3;

    try processAction(&state, .none);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);

    try processAction(&state, .insert);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "processAction: insert_tab inserts tab at cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "ab");
    state.cursor = 1;

    try processAction(&state, .insert_tab);
    try std.testing.expectEqualStrings("a\tb", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "processAction: reverse_tab removes leading tab" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "\thello");
    state.cursor = 3;

    try processAction(&state, .reverse_tab);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "processAction: reverse_tab removes leading spaces (up to 4)" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "    hello");
    state.cursor = 6;

    try processAction(&state, .reverse_tab);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "processAction: backspace deletes char before cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 2;

    try processAction(&state, .backspace);
    try std.testing.expectEqualStrings("ac", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 1), state.cursor);
}

test "processAction: backspace at position 0 is no-op" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 0;

    try processAction(&state, .backspace);
    try std.testing.expectEqualStrings("abc", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "processAction: delete_char removes char at cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 1;

    try processAction(&state, .delete_char);
    try std.testing.expectEqualStrings("ac", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 1), state.cursor);
}

test "processAction: delete_char at end is no-op" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 3;

    try processAction(&state, .delete_char);
    try std.testing.expectEqualStrings("abc", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "processAction: delete_char_forward removes char at cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 1;

    try processAction(&state, .delete_char_forward);
    try std.testing.expectEqualStrings("ac", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 1), state.cursor);
}

test "processAction: delete_word deletes forward to word boundary and populates kill ring" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 0;

    try processAction(&state, .delete_word);
    // findWordEnd skips non-whitespace then whitespace, so "hello " is deleted
    try std.testing.expectEqualStrings("world", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
    try std.testing.expectEqualStrings("hello ", state.kill_ring.items);
    // delete_word is a kill action -- last_was_kill survives for Emacs kill-ring accumulation
    try std.testing.expect(state.last_was_kill);
}

test "processAction: delete_word_backward deletes backward to word boundary" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 11; // end

    try processAction(&state, .delete_word_backward);
    try std.testing.expectEqualStrings("hello ", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 6), state.cursor);
    try std.testing.expectEqualStrings("world", state.kill_ring.items);
    // delete_word_backward is a kill action -- last_was_kill survives for Emacs kill-ring accumulation
    try std.testing.expect(state.last_was_kill);
}

test "processAction: delete_to_eol deletes from cursor to end" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 5;

    try processAction(&state, .delete_to_eol);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
    try std.testing.expectEqualStrings(" world", state.kill_ring.items);
    try std.testing.expect(state.last_was_kill);
}

test "processAction: delete_to_bol deletes from start to cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 5;

    try processAction(&state, .delete_to_bol);
    try std.testing.expectEqualStrings(" world", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
    try std.testing.expectEqualStrings("hello", state.kill_ring.items);
    try std.testing.expect(state.last_was_kill);
}

test "processAction: move_left and move_right" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 2;

    try processAction(&state, .move_left);
    try std.testing.expectEqual(@as(usize, 1), state.cursor);

    try processAction(&state, .move_right);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);

    // Boundary: move_left at 0
    state.cursor = 0;
    try processAction(&state, .move_left);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);

    // Boundary: move_right at end
    state.cursor = 3;
    try processAction(&state, .move_right);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "processAction: move_word_left and move_word_right" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 8; // mid "world"

    try processAction(&state, .move_word_left);
    try std.testing.expectEqual(@as(usize, 6), state.cursor); // start of "world"

    try processAction(&state, .move_word_right);
    try std.testing.expectEqual(@as(usize, 11), state.cursor); // end of "world"
}

test "processAction: move_bol and move_eol" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello");
    state.cursor = 3;

    try processAction(&state, .move_bol);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);

    try processAction(&state, .move_eol);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "processAction: history_prev navigates backward" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("first");
    try hist.append("second");

    var state = createTestState(allocator, &hist);
    defer state.deinit();

    // First history_prev should show most recent entry
    try processAction(&state, .history_prev);
    try std.testing.expectEqualStrings("second", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 6), state.cursor);

    // Second should show first entry
    try processAction(&state, .history_prev);
    try std.testing.expectEqualStrings("first", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);

    // At beginning, should stay on first
    try processAction(&state, .history_prev);
    try std.testing.expectEqualStrings("first", state.buffer.items);
}

test "processAction: history_next navigates forward" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("first");
    try hist.append("second");

    var state = createTestState(allocator, &hist);
    defer state.deinit();

    // Navigate to first entry
    try processAction(&state, .history_prev);
    try processAction(&state, .history_prev);
    try std.testing.expectEqualStrings("first", state.buffer.items);

    // Navigate forward
    try processAction(&state, .history_next);
    try std.testing.expectEqualStrings("second", state.buffer.items);

    // Navigate past end clears buffer
    try processAction(&state, .history_next);
    try std.testing.expectEqualStrings("", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "processAction: history_first and history_last" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("first");
    try hist.append("second");
    try hist.append("third");

    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try processAction(&state, .history_first);
    try std.testing.expectEqualStrings("first", state.buffer.items);

    try processAction(&state, .history_last);
    try std.testing.expectEqualStrings("third", state.buffer.items);
}

test "processAction: yank inserts kill ring at cursor" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "ac");
    state.cursor = 1;
    try state.kill_ring.appendSlice(allocator, "b");

    try processAction(&state, .yank);
    try std.testing.expectEqualStrings("abc", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "processAction: undo restores previous state" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    // Push a snapshot
    try state.undo_stack.push("hello", 3);

    // Modify buffer
    try state.buffer.appendSlice(allocator, "world");
    state.cursor = 5;

    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "processAction: undo with empty stack is no-op" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello");
    state.cursor = 5;

    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "processAction: run, cancel, quit are no-ops" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello");
    state.cursor = 3;

    try processAction(&state, .run);
    try std.testing.expectEqualStrings("hello", state.buffer.items);

    try processAction(&state, .cancel);
    try std.testing.expectEqualStrings("hello", state.buffer.items);

    try processAction(&state, .quit);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
}

test "processAction: vi_normal_mode and vi_insert_mode are no-ops" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "test");
    state.cursor = 2;

    try processAction(&state, .vi_normal_mode);
    try std.testing.expectEqualStrings("test", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);

    try processAction(&state, .vi_insert_mode);
    try std.testing.expectEqualStrings("test", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "processAction: content_changed flag set for modifying actions" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello");
    state.cursor = 5;

    // Non-modifying action should not set content_changed
    state.content_changed = false;
    try processAction(&state, .move_left);
    try std.testing.expect(!state.content_changed);

    // Modifying action should set content_changed
    state.content_changed = false;
    try processAction(&state, .backspace);
    try std.testing.expect(state.content_changed);
}

test "processAction: last_was_kill reset after non-kill action" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hello world");
    state.cursor = 5;

    // delete_to_eol sets last_was_kill
    try processAction(&state, .delete_to_eol);
    try std.testing.expect(state.last_was_kill);

    // Non-kill action resets it
    try processAction(&state, .move_left);
    try std.testing.expect(!state.last_was_kill);
}

test "processAction: complete with completion function" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    state.complete_fn = struct {
        fn complete(prefix: []const u8, ctx: *completion.CompletionContext) void {
            _ = prefix;
            ctx.addCandidate("hello_world") catch return;
        }
    }.complete;

    try state.buffer.appendSlice(allocator, "hel");
    state.cursor = 3;

    try processAction(&state, .complete);
    try std.testing.expectEqualStrings("hello_world", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 11), state.cursor);
}

test "processAction: complete without function is no-op" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();

    try state.buffer.appendSlice(allocator, "hel");
    state.cursor = 3;

    try processAction(&state, .complete);
    try std.testing.expectEqualStrings("hel", state.buffer.items);
}

// ============================================================================
// ADV-001 / issue #142: bracketed-paste persistence across read() boundaries
//
// These tests drive the paste path across MULTIPLE independent read batches by
// calling processReadBuffer with separate input slices, mirroring how
// processInput loops over successive read(2) results with persistent state.
// ============================================================================

/// Helper: feed a sequence of independent "read batches" through
/// processReadBuffer with a single persistent PasteState, exactly as
/// processInput would across successive read(2) calls (including carry-over of
/// torn markers between batches).
fn feedBatches(state: *ReplState, paste_state: *PasteState, batches: []const []const u8) !KeyAction {
    var last_action: KeyAction = .none;
    var combined: [PASTE_CARRY_MAX + 4096]u8 = undefined;
    for (batches) |batch| {
        const carry_len = paste_state.carry_len;
        std.debug.assert(carry_len + batch.len <= combined.len);
        if (carry_len > 0) {
            @memcpy(combined[0..carry_len], paste_state.carry[0..carry_len]);
            paste_state.carry_len = 0;
        }
        @memcpy(combined[carry_len .. carry_len + batch.len], batch);
        try processReadBuffer(state, paste_state, combined[0 .. carry_len + batch.len], &last_action);
    }
    return last_action;
}

test "ADV-001: large paste (>256B) split across reads loses zero bytes" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // 600 'X' bytes, split into 256-byte reads, with start/end markers in
    // separate batches. The old code reset paste_len every read -> data loss.
    const content_size = 600;
    var content: [content_size]u8 = undefined;
    @memset(&content, 'X');

    // Batch 1: start marker + first 250 content bytes
    var b1: [6 + 250]u8 = undefined;
    @memcpy(b1[0..6], "\x1b[200~");
    @memcpy(b1[6..], content[0..250]);
    // Batch 2: next 250 content bytes (no markers)
    const b2 = content[250..500];
    // Batch 3: final 100 content bytes + end marker
    var b3: [100 + 6]u8 = undefined;
    @memcpy(b3[0..100], content[500..600]);
    @memcpy(b3[100..], "\x1b[201~");

    _ = try feedBatches(&state, &paste_state, &.{ &b1, b2, &b3 });

    try std.testing.expectEqual(@as(usize, content_size), state.buffer.items.len);
    try std.testing.expectEqual(false, state.in_bracketed_paste);
    for (state.buffer.items) |c| try std.testing.expectEqual(@as(u8, 'X'), c);
}

test "ADV-001: very large paste (>4096B) split across many reads loses zero bytes" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // 5000 bytes (> PASTE_BUF_SIZE=4096) streamed in 256-byte reads so flushes
    // happen mid-stream while paste accumulation must persist across reads.
    const content_size = 5000;
    var content: [content_size]u8 = undefined;
    for (0..content_size) |j| content[j] = @as(u8, @intCast(0x41 + (j % 26)));

    var batches = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer batches.deinit(allocator);

    // First batch carries the start marker; remaining batches are raw content.
    var first: [6 + 200]u8 = undefined;
    @memcpy(first[0..6], "\x1b[200~");
    @memcpy(first[6..], content[0..200]);
    try batches.append(allocator, &first);

    var off: usize = 200;
    while (off < content_size) {
        const end = @min(off + 256, content_size);
        try batches.append(allocator, content[off..end]);
        off = end;
    }
    try batches.append(allocator, "\x1b[201~");

    _ = try feedBatches(&state, &paste_state, batches.items);

    try std.testing.expectEqual(@as(usize, content_size), state.buffer.items.len);
    try std.testing.expectEqual(false, state.in_bracketed_paste);
    for (state.buffer.items, 0..) |c, j| {
        try std.testing.expectEqual(@as(u8, @intCast(0x41 + (j % 26))), c);
    }
}

test "ADV-001: torn end marker across reads -- REPL recovers, keystroke not swallowed" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Batch 1: start marker + "abc" + the FIRST 5 bytes of the end marker
    // ("\x1b[201"). The 6th byte ("~") arrives in batch 2. The old code would
    // consume "\x1b[201" as paste content and stay wedged in paste mode.
    const b1 = "\x1b[200~abc\x1b[201";
    // Batch 2: the trailing "~" completes the end marker, then a normal key.
    const b2 = "~d";

    _ = try feedBatches(&state, &paste_state, &.{ b1, b2 });

    // Paste mode must have exited cleanly (recovery), not stayed wedged.
    try std.testing.expectEqual(false, state.in_bracketed_paste);
    // "abc" pasted, then the post-paste 'd' keystroke processed normally.
    try std.testing.expectEqualStrings("abcd", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 4), state.cursor);
}

test "ADV-001: torn start marker across reads is reassembled" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Start marker split: batch 1 ends with "\x1b[20", batch 2 begins "0~hi"
    // then the end marker.
    const b1 = "\x1b[20";
    const b2 = "0~hi\x1b[201~";

    _ = try feedBatches(&state, &paste_state, &.{ b1, b2 });

    try std.testing.expectEqual(false, state.in_bracketed_paste);
    try std.testing.expectEqualStrings("hi", state.buffer.items);
}

test "ADV-001: safety bound force-exits paste mode when end marker never arrives" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Open a paste, then feed many reads of content with NO end marker.
    _ = try feedBatches(&state, &paste_state, &.{"\x1b[200~"});
    try std.testing.expectEqual(true, state.in_bracketed_paste);

    // Drive past PASTE_MAX_READS_WITHOUT_END reads of plain content.
    var last_action: KeyAction = .none;
    var k: usize = 0;
    while (k <= PASTE_MAX_READS_WITHOUT_END + 1) : (k += 1) {
        try processReadBuffer(&state, &paste_state, "z", &last_action);
        if (!state.in_bracketed_paste) break;
    }

    // The REPL must have recovered rather than wedging forever.
    try std.testing.expectEqual(false, state.in_bracketed_paste);

    // A subsequent normal keystroke is processed, not swallowed.
    const before_len = state.buffer.items.len;
    try processReadBuffer(&state, &paste_state, "Q", &last_action);
    try std.testing.expectEqual(before_len + 1, state.buffer.items.len);
    try std.testing.expectEqual(@as(u8, 'Q'), state.buffer.items[state.buffer.items.len - 1]);
}

test "ADV-001: lone trailing ESC outside paste is handled immediately (not carried)" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // A bare ESC at the end of a read, NOT in paste mode, must be consumed now
    // (emacs ESC -> .none), leaving no carry for the next read.
    var last_action: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "ab\x1b", &last_action);

    try std.testing.expectEqualStrings("ab", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), paste_state.carry_len);
}

test "ADV-001: contiguous paste (single batch) still works" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    _ = try feedBatches(&state, &paste_state, &.{"\x1b[200~hello world\x1b[201~"});

    try std.testing.expectEqualStrings("hello world", state.buffer.items);
    try std.testing.expectEqual(false, state.in_bracketed_paste);
}

// ============================================================================
// GAP-0072 / #52: processReadBuffer pipeline tests (mock-stdin, no TTY)
// ============================================================================

test "processReadBuffer: plain text inserts into buffer" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    var last_action: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "hello", &last_action);

    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
    try std.testing.expectEqual(KeyAction.insert, last_action);
}

test "processReadBuffer: control keys (left arrow) move cursor without mutation" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    var last_action: KeyAction = .none;
    // "ab" then Left arrow (ESC[D) then Left arrow.
    try processReadBuffer(&state, &paste_state, "ab\x1b[D", &last_action);
    try std.testing.expectEqualStrings("ab", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 1), state.cursor);
    try std.testing.expectEqual(KeyAction.move_left, last_action);
}

test "processReadBuffer: Enter produces run action" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    var last_action: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "cmd\r", &last_action);

    try std.testing.expectEqualStrings("cmd", state.buffer.items);
    try std.testing.expectEqual(KeyAction.run, last_action);
}

test "processReadBuffer: backspace deletes and records undo" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    var last_action: KeyAction = .none;
    // Type "abc" (3 inserts -> 3 undo entries) then backspace (1 more).
    try processReadBuffer(&state, &paste_state, "abc\x7f", &last_action);

    try std.testing.expectEqualStrings("ab", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
    // Each mutation snapshotted: 3 inserts + 1 backspace = 4 undo entries.
    try std.testing.expectEqual(@as(usize, 4), state.undo_stack.len());

    // Undo restores the backspaced char.
    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("abc", state.buffer.items);
}

test "processReadBuffer: multi-read paste embedded in a typed line submits correctly" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Type "a", paste "BC" split across two reads, type "d", then Enter.
    const last = try feedBatches(&state, &paste_state, &.{
        "a\x1b[200~B",
        "C\x1b[201~d\r",
    });

    try std.testing.expectEqualStrings("aBCd", state.buffer.items);
    try std.testing.expectEqual(KeyAction.run, last);
}

// ============================================================================
// perf NEW-1 / NEW-2: lazy undo snapshot (no dupe on pure cursor moves)
// ============================================================================

/// Allocator wrapper that counts the number of allocations larger than a
/// threshold, used to prove that pure cursor-movement keys perform ZERO buffer
/// dupes (perf NEW-1).
const CountingAllocator = struct {
    backing: std.mem.Allocator,
    alloc_count: usize = 0,
    min_size: usize,

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (len >= self.min_size) self.alloc_count += 1;
        return self.backing.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawResize(buf, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawRemap(buf, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(buf, alignment, ret_addr);
    }
};

test "perf NEW-1: pure cursor moves perform zero buffer dupes" {
    var counting = CountingAllocator{ .backing = std.testing.allocator, .min_size = 8 };
    const allocator = counting.allocator();

    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Pre-fill a 16-char line so any snapshot dupe (>= min_size) would be
    // counted.
    var fill: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "0123456789abcdef", &fill);

    // Reset the counter AFTER the inserts (those legitimately dupe).
    counting.alloc_count = 0;

    // Now drive ONLY cursor-movement / navigation keys against the filled line:
    // Left, Right, Home (Ctrl+A), End (Ctrl+E), word-left (ESC[1;5D-> handled),
    // plain Ctrl+B / Ctrl+F.
    var last_action: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "\x1b[D", &last_action); // Left
    try processReadBuffer(&state, &paste_state, "\x1b[C", &last_action); // Right
    try processReadBuffer(&state, &paste_state, "\x01", &last_action); // Ctrl+A move_bol
    try processReadBuffer(&state, &paste_state, "\x05", &last_action); // Ctrl+E move_eol
    try processReadBuffer(&state, &paste_state, "\x02", &last_action); // Ctrl+B move_left
    try processReadBuffer(&state, &paste_state, "\x06", &last_action); // Ctrl+F move_right

    // ZERO large allocations: no buffer dupes for pure navigation (perf NEW-1).
    try std.testing.expectEqual(@as(usize, 0), counting.alloc_count);
    // Buffer is unchanged by navigation.
    try std.testing.expectEqualStrings("0123456789abcdef", state.buffer.items);
}

test "perf NEW-1: insert/backspace sequence still builds correct undo history" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    var last_action: KeyAction = .none;
    // 5 inserts.
    try processReadBuffer(&state, &paste_state, "hello", &last_action);
    try std.testing.expectEqual(@as(usize, 5), state.undo_stack.len());

    // 2 backspaces (each mutates -> snapshot).
    try processReadBuffer(&state, &paste_state, "\x7f\x7f", &last_action);
    try std.testing.expectEqualStrings("hel", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 7), state.undo_stack.len());

    // Undo walks back correctly.
    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("hell", state.buffer.items);
    try processAction(&state, .undo);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
}

test "perf NEW-2: no-op backspace at BOL does not push a dead undo entry" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    var paste_state = PasteState{};

    // Cursor at beginning, buffer non-empty: backspace is a no-op.
    try state.buffer.appendSlice(allocator, "abc");
    state.cursor = 0;

    var last_action: KeyAction = .none;
    try processReadBuffer(&state, &paste_state, "\x7f", &last_action);

    // Buffer unchanged AND no dead undo entry recorded (perf NEW-2).
    try std.testing.expectEqualStrings("abc", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.undo_stack.len());
}

test "keyMayMutate: classifies common keys correctly (emacs)" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    state.keymap = .emacs;

    // Mutating.
    try std.testing.expect(keyMayMutate(&state, .{ .key = 'a' })); // insert
    try std.testing.expect(keyMayMutate(&state, .{ .key = 0x7f })); // backspace
    try std.testing.expect(keyMayMutate(&state, .{ .key = 'k', .ctrl = true })); // kill-eol
    try std.testing.expect(keyMayMutate(&state, .{ .key = 'y', .ctrl = true })); // yank
    try std.testing.expect(keyMayMutate(&state, .{ .key = 'd', .alt = true })); // delete-word

    // Non-mutating navigation / control.
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 'b', .ctrl = true })); // move_left
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 'f', .ctrl = true })); // move_right
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 'a', .ctrl = true })); // move_bol
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 'p', .ctrl = true })); // history_prev
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 0x1b })); // ESC
}

test "keyMayMutate: vi pending operator forces snapshot" {
    const allocator = std.testing.allocator;
    var hist = try history_mod.HistoryStore.init(allocator, null, false);
    defer hist.deinit();
    var state = createTestState(allocator, &hist);
    defer state.deinit();
    state.keymap = .vi;
    state.vi_mode = .normal;

    // Pure motion when no operator pending.
    try std.testing.expect(!keyMayMutate(&state, .{ .key = 'e' }));
    // With a pending 'd' operator, the next 'e' (de) is destructive.
    state.pending_operator = 'd';
    try std.testing.expect(keyMayMutate(&state, .{ .key = 'e' }));
}

// SAFETY-PROPERTY GUARD (perf NEW-1 correctness contract):
//
// For every possible KeyEvent and every keymap/mode, if running the real keymap
// handler either (a) returns a destructive action OR (b) mutates the edit buffer
// in-place inside handleKey, then `keyMayMutate` MUST have predicted `true`. A
// `false` prediction for such a key would silently drop the undo snapshot -- this
// test fails loudly if the predictor ever drifts out of sync with the handlers.
test "keyMayMutate: never under-predicts a mutating key (exhaustive)" {
    const allocator = std.testing.allocator;

    const Mode = enum { emacs, vi_normal, vi_insert };
    const modes = [_]Mode{ .emacs, .vi_normal, .vi_insert };
    const pendings = [_]?u8{ null, 'd', 'c', 'r' };

    for (modes) |mode| {
        for (pendings) |pending| {
            // Vi-only: pending operators only meaningful in vi normal mode.
            if (pending != null and mode != .vi_normal) continue;

            var key: u16 = 0;
            while (key <= 0xff) : (key += 1) {
                const ctrl_opts = [_]bool{ false, true };
                const alt_opts = [_]bool{ false, true };
                for (ctrl_opts) |ctrl| {
                    for (alt_opts) |alt| {
                        const ev = KeyEvent{ .key = @intCast(key), .ctrl = ctrl, .alt = alt };

                        // Fresh state per key so in-handler mutations are
                        // observed against a known pre-buffer.
                        var hist = try history_mod.HistoryStore.init(allocator, null, false);
                        defer hist.deinit();
                        var state = createTestState(allocator, &hist);
                        defer state.deinit();
                        try state.buffer.appendSlice(allocator, "sample text");
                        state.cursor = 4;

                        switch (mode) {
                            .emacs => state.keymap = .emacs,
                            .vi_normal => {
                                state.keymap = .vi;
                                state.vi_mode = .normal;
                                state.pending_operator = pending;
                            },
                            .vi_insert => {
                                state.keymap = .vi;
                                state.vi_mode = .insert;
                            },
                        }

                        const predicted = keyMayMutate(&state, ev);

                        const pre = try allocator.dupe(u8, state.buffer.items);
                        defer allocator.free(pre);

                        const action = switch (state.keymap) {
                            .emacs => keymap_emacs.handleKey(&state, ev),
                            .vi => keymap_vi.handleKey(&state, ev),
                        };
                        // Skip actions whose handlers perform real terminal I/O
                        // (read stdin / write stdout). They are non-edit actions,
                        // orthogonal to keyMayMutate's buffer-mutation contract,
                        // and dispatching them corrupts Zig's `zig build test`
                        // --listen IPC channel (fd 0/1): `.search` blocks reading
                        // the command pipe, the others inject bytes into the
                        // result pipe. The editing actions below still exercise
                        // the prediction fully.
                        switch (action) {
                            .search, .clear_screen, .complete, .run => continue,
                            else => {},
                        }
                        try processAction(&state, action);

                        const is_destructive = switch (action) {
                            .insert, .insert_tab, .reverse_tab, .backspace, .delete_char, .delete_char_forward, .delete_word, .delete_word_backward, .delete_to_eol, .delete_to_bol, .yank => true,
                            else => false,
                        };
                        const buffer_mutated = !std.mem.eql(u8, pre, state.buffer.items);

                        // The old code pushed an undo snapshot iff is_destructive.
                        // The new code pushes iff predicted AND is_destructive AND
                        // buffer changed. To never lose an undo entry the old code
                        // would have kept, predicted must be true whenever the
                        // action is destructive. Also guard direct in-handler
                        // mutations (e.g. vi `o`,`dd`) even though they are not in
                        // the destructive set -- there the old code ALSO did not
                        // snapshot, but predicting true keeps us conservative.
                        if (is_destructive or buffer_mutated) {
                            try std.testing.expect(predicted);
                        }
                    }
                }
            }
        }
    }
}
