// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Core REPL implementation
//!
//! The main REPL loop with:
//! - Raw terminal mode
//! - Input processing and key event parsing
//! - Multi-line input support
//! - Prompt rendering

const std = @import("std");
const builtin = @import("builtin");
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

const findWordStart = text_utils.findWordStart;
const findWordEnd = text_utils.findWordEnd;
const isUnsafeControlChar = text_utils.isUnsafeControlChar;
const appendHistoryFiltered = text_utils.appendHistoryFiltered;
const sanitizePasteContent = text_utils.sanitizePasteContent;

/// Size of the fixed buffer used for batching terminal render output.
const RENDER_BUF_SIZE = 8192;

/// Size of the fixed buffer used for accumulating bracketed-paste content.
const PASTE_BUF_SIZE = 4096;

/// Keymap selection.
/// Unified with Config.Keymap from config.zig; includes fromString() for parsing.
pub const Keymap = @import("config.zig").Config.Keymap;

/// Output format.
/// Unified with Config.Format from config.zig; includes fromString() for parsing.
pub const Format = @import("config.zig").Config.Format;

/// Key event from terminal input (defined in input.zig)
pub const KeyEvent = input_mod.KeyEvent;

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
pub const WelcomeFn = *const fn (stdout: std.fs.File, use_color: bool) anyerror!void;

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
            try stderr.writeAll("Error: interactive shell requires a TTY\n");
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
        stdout.writeAll("\r\n") catch {};
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
    var fbs = std.io.fixedBufferStream(&render_buf);
    const w = fbs.writer();

    var buffer_full = false;

    // Move cursor up from current row to start
    if (state.last_cursor_row > 0) {
        std.fmt.format(w, "\x1b[{d}A", .{state.last_cursor_row}) catch {
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
    // If the render buffer fills, stop immediately to avoid broken ANSI sequences.
    if (!buffer_full) for (state.buffer.items) |c| {
        const write_result = if (c == '\n')
            w.writeAll("\r\n")
        else if (c == '\t' or (c >= 0x20 and c != 0x7F))
            w.writeAll(&[_]u8{c})
        else
            // Control characters and DEL - show visual indicator
            w.writeAll("?");

        write_result catch {
            buffer_full = true;
            break;
        };
    };

    // Calculate visual lines
    const current_visual_lines = render.calculateVisualLines(prompt.len, state.buffer.items, term_width);

    // Position cursor -- only if the buffer has not overflowed, since writing
    // partial ANSI escape sequences would corrupt the terminal.
    if (!buffer_full) {
        const cursor_pos = render.calculateCursorPosition(prompt.len, state.buffer.items, state.cursor, term_width);

        if (cursor_pos.rows_from_end > 0) {
            std.fmt.format(w, "\x1b[{d}A", .{cursor_pos.rows_from_end}) catch {
                buffer_full = true;
            };
        }

        if (!buffer_full) {
            std.fmt.format(w, "\r\x1b[{d}C", .{cursor_pos.col}) catch {
                buffer_full = true;
            };
        }

        // Single write for entire render output
        try stdout.writeAll(fbs.getWritten());

        // Update tracking state
        state.last_cursor_row = current_visual_lines - cursor_pos.rows_from_end;
    } else {
        // Buffer overflowed -- write the valid partial content we have.
        // Cursor positioning is skipped to avoid broken ANSI sequences.
        try stdout.writeAll(fbs.getWritten());

        // Without cursor positioning, assume cursor is at the end
        state.last_cursor_row = 0;
    }

    state.content_changed = false;
    state.last_buffer_len = state.buffer.items.len;
    state.last_visual_lines = current_visual_lines;
}

fn processInput(state: *ReplState) !void {
    const stdin = platform.getStdinHandle();
    var buf: [256]u8 = undefined;

    outer: while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) continue;

        var last_action: KeyAction = .none;
        var paste_buf: [PASTE_BUF_SIZE]u8 = undefined;
        var paste_len: usize = 0;

        var i: usize = 0;
        while (i < n) {
            if (consumeBracketedPaste(buf[0..n], &i, state, &paste_buf, &paste_len, &last_action)) continue;

            const remaining = buf[i..n];
            const key_event = parseKeyEvent(remaining) catch break;
            i += getKeyEventLength(remaining);

            // Snapshot buffer state before the keymap handler runs, since
            // some keymaps (emacs, vi) modify the buffer directly for
            // insert actions.  The snapshot is kept only if the resulting
            // action is destructive; otherwise it is discarded.
            const pre_buffer = state.allocator.dupe(u8, state.buffer.items) catch null;
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

            if (is_destructive) {
                if (pre_buffer) |buf_snap| {
                    // pushOwned takes ownership; no extra free needed.
                    state.undo_stack.pushOwned(buf_snap, pre_cursor) catch {
                        // On error, we still own the buffer.
                        state.allocator.free(buf_snap);
                    };
                }
            } else {
                if (pre_buffer) |buf_snap| state.allocator.free(buf_snap);
            }

            processAction(state, action) catch break;
            last_action = action;
        }

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
        try stdout.writeAll("\r\n");
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
                    stderr.writeAll("Warning: failed to append to history: ") catch {};
                    stderr.writeAll(@errorName(err)) catch {};
                    stderr.writeAll("\r\n") catch {};
                }
            };
        }

        const stdout = platform.getStdoutHandle();
        try stdout.writeAll("\r\n");

        if (state.run_fn) |handler| {
            const should_continue = handler(state.user_context, state.allocator, complete_input, state.history) catch |err| blk: {
                const stderr = platform.getStderrHandle();
                stderr.writeAll("Error: ") catch {};
                stderr.writeAll(@errorName(err)) catch {};
                stderr.writeAll("\r\n") catch {};
                break :blk true;
            };
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
        try stdout.writeAll("\r\n");
    }
}

/// Handle the .cancel action: Ctrl+C behavior.
fn handleCancellation(state: *ReplState) !void {
    const stdout = platform.getStdoutHandle();
    if (state.buffer.items.len == 0 and !state.is_continuation) {
        try stdout.writeAll("\r\n^C\r\n");
        state.quit_requested = true;
    } else {
        state.is_continuation = false;
        state.multi_line_buffer.clearRetainingCapacity();
        resetLineState(state);
        try stdout.writeAll("\r\n^C\r\n");
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
                // Single O(n) replaceRange instead of O(n*w) orderedRemove loop
                state.buffer.replaceRange(state.allocator, state.cursor, end - state.cursor, &.{}) catch {};
            }
        },
        .delete_word_backward => {
            const start = findWordStart(state.buffer.items, state.cursor);
            if (state.cursor > start) {
                const count = state.cursor - start;
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..state.cursor]) catch {};
                // Single O(n) replaceRange instead of O(n*w) orderedRemove loop
                state.buffer.replaceRange(state.allocator, start, count, &.{}) catch {};
                state.cursor = start;
            }
            state.last_was_kill = true;
        },
        .delete_to_eol => {
            state.kill_ring.clearRetainingCapacity();
            try state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..]);
            state.buffer.items.len = state.cursor;
            state.last_was_kill = true;
        },
        .delete_to_bol => {
            state.kill_ring.clearRetainingCapacity();
            try state.kill_ring.appendSlice(state.allocator, state.buffer.items[0..state.cursor]);
            // Single O(n) replaceRange instead of alloc+copy+clear+append cycle
            state.buffer.replaceRange(state.allocator, 0, state.cursor, &.{}) catch {};
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
            try stdout.writeAll("\x1b[2J\x1b[H");
            state.last_visual_lines = 0;
            state.last_cursor_row = 0;
            state.content_changed = true;
        },
        .vi_normal_mode, .vi_insert_mode => {},
    }

    if (action != .delete_to_eol and action != .delete_to_bol) {
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
            state.buffer.replaceRange(state.allocator, line_start, 1, &.{}) catch {};
            if (state.cursor > line_start) state.cursor -= 1;
        } else if (state.buffer.items[line_start] == ' ') {
            // Count leading spaces (up to 4)
            var count: usize = 0;
            while (count < 4 and line_start + count < state.buffer.items.len and state.buffer.items[line_start + count] == ' ') {
                count += 1;
            }
            if (count > 0) {
                // Single O(n) replaceRange instead of orderedRemove loop
                state.buffer.replaceRange(state.allocator, line_start, count, &.{}) catch {};
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
            ctx.original_prefix = state.allocator.dupe(u8, prefix) catch "";
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
            state.buffer.replaceRange(
                state.allocator,
                ctx.word_start,
                remove_len,
                &.{},
            ) catch {};
            state.cursor = ctx.word_start;
        }

        // Insert the completion
        state.buffer.insertSlice(state.allocator, state.cursor, candidate) catch {};
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
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    // Write data that fits
    w.writeAll("\x1b[1A") catch unreachable; // 4 bytes
    w.writeAll("\r\x1b[J") catch unreachable; // 4 bytes -- 8 total
    w.writeAll("> ") catch unreachable; // 2 bytes -- 10 total
    w.writeAll("ABCDE") catch unreachable; // 5 bytes -- 15 total

    // 1 byte remaining. A 2-byte write should fail with NoSpaceLeft.
    const result = w.writeAll("\r\n");
    try std.testing.expectError(error.NoSpaceLeft, result);

    // The buffer should contain exactly what was successfully written.
    // Importantly, the failed "\r\n" should NOT have partially written "\r".
    // (fixedBufferStream.write does partial writes, but the second iteration
    // of writeAll propagates the error, so at most 1 extra byte.)
    const written = fbs.getWritten();
    // The partial write means "\r" (1 byte) was written, then "\n" failed.
    // Total = 16 bytes (buffer full).
    try std.testing.expectEqual(@as(usize, 16), written.len);

    // Verify the content up to byte 15 is clean
    try std.testing.expectEqualStrings("\x1b[1A\r\x1b[J> ABCDE\r", written);
}
