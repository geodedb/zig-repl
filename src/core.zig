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

/// Keymap selection
pub const Keymap = enum { emacs, vi };

/// Output format
pub const Format = enum { text, table, csv, json };

/// Key event from terminal input
pub const KeyEvent = struct {
    key: u8,
    ctrl: bool = false,
    alt: bool = false,
};

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
            .buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable,
            .cursor = 0,
            .history = &hist,
            .history_index = null,
            .keymap = opts.keymap,
            .vi_mode = .insert,
            .quit_requested = false,
            .kill_ring = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable,
            .last_was_kill = false,
            .search_buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable,
            .searching = false,
            .completion_ctx = completion.CompletionContext.init(opts.allocator),
            .multi_line_buffer = std.ArrayList(u8).initCapacity(opts.allocator, 0) catch unreachable,
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
        self.search_buffer.deinit(self.allocator);
        self.multi_line_buffer.deinit(self.allocator);
        self.completion_ctx.deinit();
    }

    /// Get the current prompt string
    pub fn getPrompt(self: *const ReplState) []const u8 {
        return if (self.is_continuation) self.continuation_prompt else self.prompt;
    }
};

/// Calculate tab width at a given column
fn tabWidth(col: usize) usize {
    const tab_stop = 8;
    return tab_stop - (col % tab_stop);
}

/// Calculate number of visual lines accounting for terminal width
fn calculateVisualLines(prompt_len: usize, buffer: []const u8, term_width: usize) usize {
    if (term_width == 0) return 1;

    var lines: usize = 0;
    var col: usize = prompt_len;

    for (buffer) |c| {
        if (c == '\n') {
            lines += 1;
            col = 0;
        } else if (c == '\t') {
            const width = tabWidth(col);
            col += width;
            if (col >= term_width) {
                lines += 1;
                col = 0;
            }
        } else {
            col += 1;
            if (col >= term_width) {
                lines += 1;
                col = 0;
            }
        }
    }

    return lines;
}

/// Calculate cursor position accounting for wraps
fn calculateCursorPosition(prompt_len: usize, buffer: []const u8, cursor: usize, term_width: usize) struct { rows_from_end: usize, col: usize } {
    if (term_width == 0) return .{ .rows_from_end = 0, .col = cursor + prompt_len };

    var total_lines: usize = 0;
    var cursor_line: usize = 0;
    var cursor_col: usize = 0;
    var col: usize = prompt_len;
    var found_cursor = false;

    for (buffer, 0..) |c, i| {
        if (i == cursor) {
            cursor_line = total_lines;
            cursor_col = col;
            found_cursor = true;
        }

        if (c == '\n') {
            total_lines += 1;
            col = 0;
        } else if (c == '\t') {
            const width = tabWidth(col);
            col += width;
            if (col >= term_width) {
                total_lines += 1;
                col = 0;
            }
        } else {
            col += 1;
            if (col >= term_width) {
                total_lines += 1;
                col = 0;
            }
        }
    }

    if (!found_cursor) {
        cursor_line = total_lines;
        cursor_col = col;
    }

    return .{
        .rows_from_end = total_lines - cursor_line,
        .col = cursor_col,
    };
}

fn renderPrompt(state: *ReplState) !void {
    const stdout = platform.getStdoutHandle();
    const term_width = platform.getTerminalWidth();

    const prompt = state.getPrompt();

    // Move cursor up from current row to start
    if (state.last_cursor_row > 0) {
        var move_buf: [32]u8 = undefined;
        const move_str = std.fmt.bufPrint(&move_buf, "\x1b[{d}A", .{state.last_cursor_row}) catch "\x1b[1A";
        try stdout.writeAll(move_str);
    }

    // Clear from cursor to end of screen
    try stdout.writeAll("\r\x1b[J");

    // Write prompt
    try stdout.writeAll(prompt);

    // Write buffer
    for (state.buffer.items) |c| {
        if (c == '\n') {
            try stdout.writeAll("\r\n");
        } else {
            try stdout.writeAll(&[_]u8{c});
        }
    }

    // Calculate visual lines
    const current_visual_lines = calculateVisualLines(prompt.len, state.buffer.items, term_width);

    // Position cursor
    const cursor_pos = calculateCursorPosition(prompt.len, state.buffer.items, state.cursor, term_width);

    if (cursor_pos.rows_from_end > 0) {
        var move_buf: [32]u8 = undefined;
        const move_str = std.fmt.bufPrint(&move_buf, "\x1b[{d}A", .{cursor_pos.rows_from_end}) catch return;
        try stdout.writeAll(move_str);
    }

    var col_buf: [32]u8 = undefined;
    const col_str = std.fmt.bufPrint(&col_buf, "\r\x1b[{d}C", .{cursor_pos.col}) catch return;
    try stdout.writeAll(col_str);

    // Update tracking state
    state.content_changed = false;
    state.last_buffer_len = state.buffer.items.len;
    state.last_visual_lines = current_visual_lines;
    state.last_cursor_row = current_visual_lines - cursor_pos.rows_from_end;
}

fn processInput(state: *ReplState) !void {
    const stdin = platform.getStdinHandle();
    var buf: [256]u8 = undefined;

    outer: while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) continue;

        var i: usize = 0;
        var last_action: KeyAction = .none;

        while (i < n) {
            // Check for bracketed paste sequences
            if (i + 5 < n and buf[i] == 0x1b and buf[i + 1] == '[' and buf[i + 2] == '2' and buf[i + 3] == '0' and buf[i + 4] == '0' and buf[i + 5] == '~') {
                state.in_bracketed_paste = true;
                state.paste_strip_leading = true;
                i += 6;
                continue;
            }

            if (i + 5 < n and buf[i] == 0x1b and buf[i + 1] == '[' and buf[i + 2] == '2' and buf[i + 3] == '0' and buf[i + 4] == '1' and buf[i + 5] == '~') {
                state.in_bracketed_paste = false;
                state.paste_strip_leading = false;
                i += 6;
                continue;
            }

            const c = buf[i];

            // In bracketed paste mode, insert characters literally
            if (state.in_bracketed_paste) {
                if (c == '\r') {
                    i += 1;
                    continue;
                }
                if (state.paste_strip_leading) {
                    if (c == ' ' or c == '\t') {
                        i += 1;
                        continue;
                    }
                    state.paste_strip_leading = false;
                }
                if (c == '\n' or c == '\t' or c >= 0x20) {
                    state.buffer.insert(state.allocator, state.cursor, c) catch break;
                    state.cursor += 1;
                    state.content_changed = true;
                    last_action = .insert;
                }
                i += 1;
                continue;
            }

            const remaining = buf[i..n];
            const key_event = parseKeyEvent(remaining) catch break;
            const consumed = getKeyEventLength(remaining);
            i += consumed;

            const action = switch (state.keymap) {
                .emacs => keymap_emacs.handleKey(state, key_event),
                .vi => keymap_vi.handleKey(state, key_event),
            };

            processAction(state, action) catch break;
            last_action = action;
        }

        // Render when not in paste mode and stdin is quiet
        if (!state.in_bracketed_paste and !platform.stdinHasMoreData()) {
            renderPrompt(state) catch {};
        }

        // Handle command invocation
        if (last_action == .run) {
            const input = state.buffer.items;
            if (input.len > 0) {
                // Check for backslash continuation
                if (input[input.len - 1] == '\\') {
                    _ = state.buffer.pop();
                    if (state.is_continuation) {
                        try state.multi_line_buffer.append(state.allocator, '\n');
                        try state.multi_line_buffer.appendSlice(state.allocator, state.buffer.items);
                    } else {
                        state.multi_line_buffer.clearRetainingCapacity();
                        try state.multi_line_buffer.appendSlice(state.allocator, state.buffer.items);
                    }
                    state.is_continuation = true;
                    state.buffer.clearRetainingCapacity();
                    state.cursor = 0;
                    state.last_visual_lines = 0;
                    state.last_cursor_row = 0;
                    state.content_changed = true;
                    const stdout = platform.getStdoutHandle();
                    try stdout.writeAll("\r\n");
                    break :outer;
                }

                // Build complete input
                if (state.is_continuation) {
                    try state.multi_line_buffer.append(state.allocator, '\n');
                    try state.multi_line_buffer.appendSlice(state.allocator, input);
                } else {
                    state.multi_line_buffer.clearRetainingCapacity();
                    try state.multi_line_buffer.appendSlice(state.allocator, input);
                }

                const complete_input = state.multi_line_buffer.items;

                // Check if statement is complete
                if (state.is_complete_fn(complete_input)) {
                    // Save to history
                    if (complete_input.len > 0 and complete_input[0] != ' ') {
                        state.history.append(complete_input) catch {};
                    }

                    const stdout = platform.getStdoutHandle();
                    try stdout.writeAll("\r\n");

                    // Invoke handler
                    if (state.run_fn) |handler| {
                        const should_continue = handler(state.user_context, state.allocator, complete_input, state.history) catch |err| blk: {
                            const stderr = platform.getStderrHandle();
                            stderr.writeAll("Error: ") catch {};
                            stderr.writeAll(@errorName(err)) catch {};
                            stderr.writeAll("\r\n") catch {};
                            break :blk true;
                        };
                        if (!should_continue) {
                            state.quit_requested = true;
                        }
                    }

                    // Reset
                    state.buffer.clearRetainingCapacity();
                    state.cursor = 0;
                    state.is_continuation = false;
                    state.multi_line_buffer.clearRetainingCapacity();
                    state.last_visual_lines = 0;
                    state.last_cursor_row = 0;
                    state.content_changed = true;
                    state.history_index = null;
                } else {
                    // Continue multi-line input
                    state.is_continuation = true;
                    state.buffer.clearRetainingCapacity();
                    state.cursor = 0;
                    state.last_visual_lines = 0;
                    state.last_cursor_row = 0;
                    state.content_changed = true;
                    const stdout = platform.getStdoutHandle();
                    try stdout.writeAll("\r\n");
                }
            }
            break :outer;
        }

        if (last_action == .cancel) {
            const stdout = platform.getStdoutHandle();
            if (state.buffer.items.len == 0 and !state.is_continuation) {
                try stdout.writeAll("\r\n^C\r\n");
                state.quit_requested = true;
                break :outer;
            } else {
                state.is_continuation = false;
                state.multi_line_buffer.clearRetainingCapacity();
                state.buffer.clearRetainingCapacity();
                state.cursor = 0;
                state.last_visual_lines = 0;
                state.last_cursor_row = 0;
                state.content_changed = true;
                try stdout.writeAll("\r\n^C\r\n");
            }
            break :outer;
        }

        if (last_action == .quit) {
            if (state.buffer.items.len == 0) {
                state.quit_requested = true;
                break :outer;
            }
        }
    }
}

fn parseKeyEvent(data: []const u8) !KeyEvent {
    if (data.len == 0) return error.NoInput;

    if (data[0] == 0x1b) {
        if (data.len > 1) {
            if (data[1] == '[') {
                if (data.len > 2) {
                    // Extended sequences: ESC [ n ~
                    if (data.len > 3 and data[3] == '~') {
                        return switch (data[2]) {
                            '2' => KeyEvent{ .key = 0x02 }, // Insert
                            '3' => KeyEvent{ .key = 0x7f, .ctrl = true }, // Delete
                            '5' => KeyEvent{ .key = 0x05 }, // Page Up
                            '6' => KeyEvent{ .key = 0x06 }, // Page Down
                            else => KeyEvent{ .key = data[2] },
                        };
                    }

                    // Modifier sequences: ESC [ 1 ; n X
                    if (data.len > 5 and data[2] == '1' and data[3] == ';') {
                        const modifier = data[4];
                        const key_char = data[5];

                        const is_ctrl = (modifier == '5' or modifier == '7');
                        const is_alt = (modifier == '3' or modifier == '7');

                        return switch (key_char) {
                            'A' => KeyEvent{ .key = 'p', .ctrl = true, .alt = is_alt },
                            'B' => KeyEvent{ .key = 'n', .ctrl = true, .alt = is_alt },
                            'C' => if (is_ctrl) KeyEvent{ .key = 'f', .alt = true } else KeyEvent{ .key = 'f', .ctrl = true },
                            'D' => if (is_ctrl) KeyEvent{ .key = 'b', .alt = true } else KeyEvent{ .key = 'b', .ctrl = true },
                            'H' => KeyEvent{ .key = 'a', .ctrl = true, .alt = is_ctrl },
                            'F' => KeyEvent{ .key = 'e', .ctrl = true, .alt = is_ctrl },
                            else => KeyEvent{ .key = key_char },
                        };
                    }

                    // Standard arrow keys
                    return switch (data[2]) {
                        'A' => KeyEvent{ .key = 'p', .ctrl = true }, // Up
                        'B' => KeyEvent{ .key = 'n', .ctrl = true }, // Down
                        'C' => KeyEvent{ .key = 'f', .ctrl = true }, // Right
                        'D' => KeyEvent{ .key = 'b', .ctrl = true }, // Left
                        'H' => KeyEvent{ .key = 'a', .ctrl = true }, // Home
                        'F' => KeyEvent{ .key = 'e', .ctrl = true }, // End
                        'Z' => KeyEvent{ .key = 'i', .ctrl = true, .alt = true }, // Shift+Tab
                        else => KeyEvent{ .key = data[2] },
                    };
                }
            } else if (data[1] == 'O') {
                if (data.len > 2) {
                    return switch (data[2]) {
                        'H' => KeyEvent{ .key = 'a', .ctrl = true }, // Home
                        'F' => KeyEvent{ .key = 'e', .ctrl = true }, // End
                        'A' => KeyEvent{ .key = 'p', .ctrl = true }, // Up
                        'B' => KeyEvent{ .key = 'n', .ctrl = true }, // Down
                        'C' => KeyEvent{ .key = 'f', .ctrl = true }, // Right
                        'D' => KeyEvent{ .key = 'b', .ctrl = true }, // Left
                        else => KeyEvent{ .key = data[2] },
                    };
                }
            } else if ((data[1] & 0x7f) >= 'a' and (data[1] & 0x7f) <= 'z') {
                return KeyEvent{ .key = @intCast(data[1] & 0x7f), .alt = true };
            } else if (data[1] >= 'A' and data[1] <= 'Z') {
                return KeyEvent{ .key = @intCast(data[1] - 'A' + 'a'), .alt = true };
            }
        }
        return KeyEvent{ .key = 0x1b };
    }

    // Control characters
    if (data[0] < 0x20) {
        return KeyEvent{ .key = @intCast(data[0] + 'a' - 1), .ctrl = true };
    }

    return KeyEvent{ .key = data[0] };
}

fn getKeyEventLength(data: []const u8) usize {
    if (data.len == 0) return 0;

    if (data[0] == 0x1b) {
        if (data.len > 1 and data[1] == '[') {
            if (data.len > 3 and data[3] == '~') return 4;
            if (data.len > 5 and data[2] == '1' and data[3] == ';') return 6;
            if (data.len > 2) return 3;
            return 2;
        } else if (data.len > 1 and data[1] == 'O') {
            if (data.len > 2) return 3;
            return 2;
        } else if (data.len > 1) {
            return 2;
        }
        return 1;
    }

    return 1;
}

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
        .reverse_tab => {
            var line_start: usize = state.cursor;
            while (line_start > 0 and state.buffer.items[line_start - 1] != '\n') {
                line_start -= 1;
            }

            if (line_start < state.buffer.items.len) {
                if (state.buffer.items[line_start] == '\t') {
                    _ = state.buffer.orderedRemove(line_start);
                    if (state.cursor > line_start) state.cursor -= 1;
                } else if (state.buffer.items[line_start] == ' ') {
                    var removed: usize = 0;
                    while (removed < 4 and line_start < state.buffer.items.len and state.buffer.items[line_start] == ' ') {
                        _ = state.buffer.orderedRemove(line_start);
                        removed += 1;
                        if (state.cursor > line_start) state.cursor -= 1;
                    }
                }
            }
        },
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
            while (state.cursor < end) {
                _ = state.buffer.orderedRemove(state.cursor);
            }
        },
        .delete_word_backward => {
            const start = findWordStart(state.buffer.items, state.cursor);
            state.kill_ring.clearRetainingCapacity();
            state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..state.cursor]) catch {};
            while (state.cursor > start) {
                state.cursor -= 1;
                _ = state.buffer.orderedRemove(state.cursor);
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
            const remaining = state.buffer.items[state.cursor..];
            const remaining_copy = try state.allocator.dupe(u8, remaining);
            defer state.allocator.free(remaining_copy);
            state.buffer.clearRetainingCapacity();
            try state.buffer.appendSlice(state.allocator, remaining_copy);
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
                    try state.buffer.appendSlice(state.allocator, state.history.entries.items[idx]);
                    state.cursor = state.buffer.items.len;
                }
            }
        },
        .history_next => {
            if (state.history_index) |idx| {
                if (idx < state.history.entries.items.len - 1) {
                    state.history_index = idx + 1;
                    state.buffer.clearRetainingCapacity();
                    try state.buffer.appendSlice(state.allocator, state.history.entries.items[idx + 1]);
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
                try state.buffer.appendSlice(state.allocator, state.history.entries.items[0]);
                state.cursor = state.buffer.items.len;
            }
        },
        .history_last => {
            if (state.history.entries.items.len > 0) {
                state.history_index = state.history.entries.items.len - 1;
                state.buffer.clearRetainingCapacity();
                try state.buffer.appendSlice(state.allocator, state.history.entries.items[state.history_index.?]);
                state.cursor = state.buffer.items.len;
            }
        },
        .search => {
            state.searching = true;
            try handleSearch(state);
        },
        .complete => {
            if (state.complete_fn) |complete_fn| {
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
        },
        .run, .cancel, .quit => {},
        .yank => {
            try state.buffer.insertSlice(state.allocator, state.cursor, state.kill_ring.items);
            state.cursor += state.kill_ring.items.len;
        },
        .undo => {
            state.buffer.clearRetainingCapacity();
            try state.buffer.appendSlice(state.allocator, state.kill_ring.items);
            state.cursor = state.buffer.items.len;
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

fn handleSearch(state: *ReplState) !void {
    const stdout = platform.getStdoutHandle();
    try stdout.writeAll("\r\n(reverse-i-search)`': ");

    state.search_buffer.clearRetainingCapacity();

    const stdin = platform.getStdinHandle();
    var search_buf: [256]u8 = undefined;

    while (true) {
        const n = try stdin.read(&search_buf);
        if (n == 0) continue;

        const c = search_buf[0];

        if (c == 0x1b or c == '\r' or c == '\n') {
            state.searching = false;
            break;
        }

        if (c == 0x03) { // Ctrl+C
            state.searching = false;
            state.buffer.clearRetainingCapacity();
            state.cursor = 0;
            break;
        }

        if (c == 0x7f or c == 0x08) {
            if (state.search_buffer.items.len > 0) {
                _ = state.search_buffer.pop();
            }
        } else if (c >= 0x20 and c < 0x7f) {
            try state.search_buffer.append(state.allocator, c);
        }

        // Find in history
        var found = false;
        if (state.history.searchBackward(state.search_buffer.items, null)) |result| {
            state.buffer.clearRetainingCapacity();
            try state.buffer.appendSlice(state.allocator, result.entry);
            state.cursor = state.buffer.items.len;
            state.history_index = result.index;
            found = true;
        }

        var line_buf: [1024]u8 = undefined;
        const search_line = try std.fmt.bufPrint(&line_buf, "\r(reverse-i-search)`{s}': {s}", .{
            state.search_buffer.items,
            if (found) state.buffer.items else "",
        });
        try stdout.writeAll(search_line);
    }
}

fn findWordStart(text: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var i = pos;
    while (i > 0 and std.ascii.isWhitespace(text[i - 1])) : (i -= 1) {}
    while (i > 0 and !std.ascii.isWhitespace(text[i - 1])) : (i -= 1) {}
    return i;
}

fn findWordEnd(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return text.len;
    var i = pos;
    while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    return i;
}

test "key event parsing" {
    // Regular character
    const regular = try parseKeyEvent("a");
    try std.testing.expect(regular.key == 'a');
    try std.testing.expect(!regular.ctrl);
    try std.testing.expect(!regular.alt);

    // Escape sequence for up arrow
    const up = try parseKeyEvent("\x1b[A");
    try std.testing.expect(up.key == 'p');
    try std.testing.expect(up.ctrl);
}

test "word navigation" {
    const text = "hello world test";
    try std.testing.expect(findWordEnd(text, 0) == 6);
    try std.testing.expect(findWordStart(text, 11) == 6);
}
