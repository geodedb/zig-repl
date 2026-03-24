// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Vi/Vim-style keybindings
//!
//! Vi keybindings with normal and insert modes:
//! - Normal mode: h,j,k,l navigation, w,b,e word movement
//! - Insert mode: Regular character input
//! - Mode switching: ESC for normal, i/a/A/o/O for insert
//! - Operators: d (delete), etc.

const std = @import("std");
const core = @import("core.zig");
const text_utils = @import("text_utils.zig");
const SyntheticKey = @import("input.zig").SyntheticKey;

const findWordStart = text_utils.findWordStart;
const findWordEnd = text_utils.findWordEnd;

/// Find the position one past the end of the current word (Vi `e` motion semantics).
///
/// Unlike `findWordEnd` (which skips past trailing whitespace to the start of
/// the next word), this function stops at the last character of the current
/// word. If the cursor is already on a non-whitespace character, it finds the
/// end of that word. Returns the position one past the last character of the
/// word (suitable for use with `replaceRange`).
///
/// This is the shared implementation backing both the `e` motion and the `de`
/// operator, eliminating the duplication noted in QF-043.
fn findEndOfWord(buffer: []const u8, start: usize) usize {
    var i = start;
    if (i < buffer.len and !std.ascii.isWhitespace(buffer[i])) {
        while (i + 1 < buffer.len and !std.ascii.isWhitespace(buffer[i + 1])) : (i += 1) {}
        i += 1;
    }
    return i;
}

/// Vi editing mode.
///
/// Visual mode is not yet implemented. When added it will likely require
/// selection-range tracking and its own handler; for now only normal and
/// insert modes are supported.
pub const ViMode = enum {
    normal,
    insert,
};

/// Handle a key event in Vi mode.
pub fn handleKey(state: anytype, key: core.KeyEvent) core.KeyAction {
    switch (state.vi_mode) {
        .normal => return handleNormalMode(state, key),
        .insert => return handleInsertMode(state, key),
    }
}

fn handleNormalMode(state: anytype, key: core.KeyEvent) core.KeyAction {
    // Handle Ctrl+Alt combinations first
    if (key.ctrl and key.alt) {
        return switch (key.key) {
            'a' => .history_first, // Ctrl+Home
            'e' => .history_last, // Ctrl+End
            'i' => .reverse_tab, // Shift+Tab: unindent
            else => .none,
        };
    }

    if (key.ctrl) {
        return switch (key.key) {
            'c' => .cancel,
            'd' => if (state.buffer.items.len == 0) .quit else .delete_char, // Ctrl+D: delete or EOF
            'a' => .move_bol, // Home
            'e' => .move_eol, // End
            'b' => .move_left, // Left arrow
            'f' => .move_right, // Right arrow
            'p' => .history_prev, // Up arrow
            'n' => .history_next, // Down arrow
            'l' => .clear_screen, // Ctrl+L
            'i', '\t' => .complete, // Tab: trigger tab completion
            else => .none,
        };
    }

    if (key.alt) {
        return switch (key.key) {
            'b' => .move_word_left, // Ctrl+Left
            'f' => .move_word_right, // Ctrl+Right
            else => .none,
        };
    }

    // Handle pending operators before normal commands so that e.g. 'rx' replaces
    // the character at cursor instead of triggering 'x' (delete_char_forward).
    if (state.pending_operator != null) {
        if (handlePendingOperator(state, key)) |action| return action;
    }

    // Vi normal mode commands
    switch (key.key) {
        // Mode changes
        'i' => {
            state.vi_mode = .insert;
            return .vi_insert_mode;
        },
        'a' => {
            state.vi_mode = .insert;
            if (state.cursor < state.buffer.items.len) state.cursor += 1;
            return .vi_insert_mode;
        },
        'A' => {
            state.vi_mode = .insert;
            state.cursor = state.buffer.items.len;
            return .vi_insert_mode;
        },
        'I' => {
            state.vi_mode = .insert;
            state.cursor = 0;
            return .vi_insert_mode;
        },
        'o' => {
            state.vi_mode = .insert;
            state.cursor = state.buffer.items.len;
            // Alloc failure is non-critical: cursor stays at end, user sees no newline
            state.buffer.append(state.allocator, '\n') catch {};
            state.cursor += 1;
            return .vi_insert_mode;
        },
        'O' => {
            state.vi_mode = .insert;
            // Alloc failure is non-critical: cursor stays at 0, user sees no newline
            state.buffer.insert(state.allocator, 0, '\n') catch {};
            state.cursor = 0;
            return .vi_insert_mode;
        },

        // Movement
        'h' => return .move_left,
        'l' => return .move_right,
        'j' => return .history_next,
        'k' => return .history_prev,
        '0' => return .move_bol,
        '^' => return .move_bol, // First non-whitespace (simplified)
        '$' => return .move_eol,
        'w' => return .move_word_right,
        'b' => return .move_word_left,
        'e' => {
            // Move to end of word (last char, not one past)
            const end = findEndOfWord(state.buffer.items, state.cursor);
            if (end > state.cursor) {
                state.cursor = end - 1;
            }
            return .none;
        },

        // Deletion
        'x', SyntheticKey.delete => return .delete_char_forward, // Delete char at cursor / Delete key
        'X' => return .backspace, // Delete char before cursor
        'd' => {
            // Wait for motion (simplified: dd deletes line)
            state.pending_operator = 'd';
            return .none;
        },
        'D' => return .delete_to_eol,
        'C' => {
            // Change to end of line (delete + insert mode)
            state.vi_mode = .insert;
            return .delete_to_eol;
        },
        'c' => {
            // Change operator (simplified)
            state.pending_operator = 'c';
            return .none;
        },
        's' => {
            // Substitute character
            state.vi_mode = .insert;
            return .delete_char_forward;
        },
        'S' => {
            // Substitute line
            state.vi_mode = .insert;
            state.cursor = 0;
            return .delete_to_eol;
        },

        // Other
        'u' => return .undo,
        'p' => return .yank, // Paste (simplified to yank)
        '/' => {
            // Start search
            state.vi_mode = .insert;
            return .search;
        },
        'G' => {
            // Go to end
            state.cursor = state.buffer.items.len;
            return .none;
        },
        'g' => {
            // gg goes to beginning (simplified)
            state.cursor = 0;
            return .none;
        },
        'r' => {
            // Replace single character (needs next char)
            state.pending_operator = 'r';
            return .none;
        },

        else => {},
    }

    return .none;
}

/// Handle a pending Vi operator (d, c, r) applied to the next key.
///
/// Returns the resulting `KeyAction` if the operator consumed the key,
/// or `null` if the key was unrecognized for this operator (the caller
/// should fall through to normal mode command handling).
fn handlePendingOperator(state: anytype, key: core.KeyEvent) ?core.KeyAction {
    const op = state.pending_operator orelse return null;

    if (op == 'd') {
        switch (key.key) {
            'd' => {
                // dd: delete line
                // Kill ring alloc failures are non-critical: delete still works, yank-back won't have data
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items) catch {};
                state.buffer.clearRetainingCapacity();
                state.cursor = 0;
                state.last_was_kill = true;
                state.pending_operator = null;
                return .none;
            },
            'w' => {
                // dw: delete word — single O(n) replaceRange instead of O(n*w) orderedRemove loop
                const end = findWordEnd(state.buffer.items, state.cursor);
                state.kill_ring.clearRetainingCapacity();
                // Kill ring alloc failures are non-critical: delete still works, yank-back won't have data
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..end]) catch {};
                state.buffer.replaceRange(state.allocator, state.cursor, end - state.cursor, &.{}) catch {};
                state.last_was_kill = true;
                state.pending_operator = null;
                return .none;
            },
            'b' => {
                // db: delete word backward — single O(n) replaceRange
                const start = findWordStart(state.buffer.items, state.cursor);
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..state.cursor]) catch {};
                state.buffer.replaceRange(state.allocator, start, state.cursor - start, &.{}) catch {};
                state.cursor = start;
                state.last_was_kill = true;
                state.pending_operator = null;
                return .none;
            },
            'e' => {
                // de: delete to end of word — single O(n) replaceRange
                const end = findEndOfWord(state.buffer.items, state.cursor);
                state.kill_ring.clearRetainingCapacity();
                state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..end]) catch {};
                state.buffer.replaceRange(state.allocator, state.cursor, end - state.cursor, &.{}) catch {};
                state.last_was_kill = true;
                state.pending_operator = null;
                return .none;
            },
            '$' => {
                // d$: delete to end of line (same as D)
                state.pending_operator = null;
                return .delete_to_eol;
            },
            '0' => {
                // d0: delete to beginning of line
                state.pending_operator = null;
                return .delete_to_bol;
            },
            else => {
                state.pending_operator = null;
                return null;
            },
        }
    } else if (op == 'c') {
        // Change operator - like delete but enter insert mode
        state.vi_mode = .insert;
        switch (key.key) {
            'c' => {
                // cc: change line
                state.buffer.clearRetainingCapacity();
                state.cursor = 0;
                state.pending_operator = null;
                return .vi_insert_mode;
            },
            'w' => {
                // cw: change word
                state.pending_operator = null;
                return .delete_word;
            },
            '$' => {
                state.pending_operator = null;
                return .delete_to_eol;
            },
            else => {
                state.pending_operator = null;
                state.vi_mode = .normal;
                return null;
            },
        }
    } else if (op == 'r') {
        // Replace with the typed character
        if (key.key >= 0x20 and key.key < 0x7f) {
            if (state.cursor < state.buffer.items.len) {
                state.buffer.items[state.cursor] = key.key;
            }
        }
        state.pending_operator = null;
        return .none;
    }

    // Unknown operator -- clear and fall through
    state.pending_operator = null;
    return null;
}

fn handleInsertMode(state: anytype, key: core.KeyEvent) core.KeyAction {
    // ESC returns to normal mode
    if (key.key == 0x1b) {
        state.vi_mode = .normal;
        if (state.cursor > 0) state.cursor -= 1;
        return .vi_normal_mode;
    }

    // Handle Ctrl+Alt combinations first
    if (key.ctrl and key.alt) {
        return switch (key.key) {
            'a' => .history_first, // Ctrl+Home
            'e' => .history_last, // Ctrl+End
            'i' => .reverse_tab, // Shift+Tab: unindent
            else => .none,
        };
    }

    // Ctrl keys work in insert mode
    if (key.ctrl) {
        return switch (key.key) {
            'c' => blk: {
                state.vi_mode = .normal;
                break :blk .cancel;
            },
            'd' => if (state.buffer.items.len == 0) .quit else .delete_char, // Ctrl+D: delete or EOF
            'a' => .move_bol, // Home
            'e' => .move_eol, // End
            'b' => .move_left, // Left arrow
            'f' => .move_right, // Right arrow
            'p' => .history_prev, // Up arrow
            'n' => .history_next, // Down arrow
            'w' => .delete_word_backward, // Ctrl+W: delete word backward
            'u' => .delete_to_bol, // Ctrl+U: delete to beginning of line
            'k' => .delete_to_eol, // Ctrl+K: delete to end of line
            'y' => .yank, // Ctrl+Y: yank
            'l' => .clear_screen, // Ctrl+L: clear screen
            'i', '\t' => .complete, // Tab: trigger tab completion
            'j', 'm', '\r', '\n' => .run,
            else => .none,
        };
    }

    // Alt keys for word movement
    if (key.alt) {
        return switch (key.key) {
            'b' => .move_word_left, // Ctrl+Left / Alt+B
            'f' => .move_word_right, // Ctrl+Right / Alt+F
            'd' => .delete_word, // Alt+D: delete word forward
            else => .none,
        };
    }

    // Regular characters
    if (key.key >= 0x20 and key.key < 0x7f) {
        state.buffer.insert(state.allocator, state.cursor, key.key) catch return .none;
        state.cursor += 1;
        return .insert;
    }

    // Special keys
    return switch (key.key) {
        0x7f, 0x08 => .backspace, // Backspace
        SyntheticKey.delete => .delete_char_forward, // Delete key - forward delete
        SyntheticKey.page_up => .history_first, // Page Up
        SyntheticKey.page_down => .history_last, // Page Down
        else => .none,
    };
}

// findWordStart and findWordEnd imported from text_utils.zig (see top of file)

// =============================================================================
// Test support: mock state struct satisfying the `anytype` interface for Vi
//
// This TestState is intentionally separate from the one in keymap_emacs.zig.
// It carries Vi-specific fields (vi_mode, pending_operator, kill_ring,
// last_was_kill) that the Emacs version does not need. Merging them would
// couple Emacs tests to Vi internals with no benefit.
// =============================================================================

const TestState = struct {
    buffer: std.ArrayList(u8),
    cursor: usize,
    allocator: std.mem.Allocator,
    vi_mode: ViMode,
    pending_operator: ?u8,
    kill_ring: std.ArrayList(u8),
    last_was_kill: bool,

    fn initWithContent(allocator: std.mem.Allocator, content: []const u8) !TestState {
        var buf = try std.ArrayList(u8).initCapacity(allocator, content.len);
        try buf.appendSlice(allocator, content);
        return .{
            .buffer = buf,
            .cursor = 0,
            .allocator = allocator,
            .vi_mode = .normal,
            .pending_operator = null,
            .kill_ring = try std.ArrayList(u8).initCapacity(allocator, 0),
            .last_was_kill = false,
        };
    }

    fn deinit(self: *TestState) void {
        self.buffer.deinit(self.allocator);
        self.kill_ring.deinit(self.allocator);
    }
};

test "vi normal h returns move_left" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'h' });
    try std.testing.expectEqual(core.KeyAction.move_left, action);
}

test "vi normal l returns move_right" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 1;

    const action = handleKey(&state, .{ .key = 'l' });
    try std.testing.expectEqual(core.KeyAction.move_right, action);
}

test "vi normal i enters insert mode" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 2;

    const action = handleKey(&state, .{ .key = 'i' });
    try std.testing.expectEqual(core.KeyAction.vi_insert_mode, action);
    try std.testing.expectEqual(ViMode.insert, state.vi_mode);
}

test "vi normal $ returns move_eol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = '$' });
    try std.testing.expectEqual(core.KeyAction.move_eol, action);
}

test "vi normal 0 returns move_bol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 5;

    const action = handleKey(&state, .{ .key = '0' });
    try std.testing.expectEqual(core.KeyAction.move_bol, action);
}

test "vi normal w returns move_word_right" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'w' });
    try std.testing.expectEqual(core.KeyAction.move_word_right, action);
}

test "vi normal b returns move_word_left" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 8;

    const action = handleKey(&state, .{ .key = 'b' });
    try std.testing.expectEqual(core.KeyAction.move_word_left, action);
}

test "vi normal x returns delete_char_forward" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 2;

    const action = handleKey(&state, .{ .key = 'x' });
    try std.testing.expectEqual(core.KeyAction.delete_char_forward, action);
}

test "vi normal D returns delete_to_eol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 5;

    const action = handleKey(&state, .{ .key = 'D' });
    try std.testing.expectEqual(core.KeyAction.delete_to_eol, action);
}

test "vi normal d sets pending operator" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 3;

    // 'd' sets pending_operator
    const action = handleKey(&state, .{ .key = 'd' });
    try std.testing.expectEqual(core.KeyAction.none, action);
    try std.testing.expectEqual(@as(?u8, 'd'), state.pending_operator);
}

test "vi pending d with unhandled key clears operator via else" {
    // The pending operator handler runs for keys not in the normal mode switch.
    // Explicitly set pending_operator and send an unmatched key (e.g., 'z').
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 3;
    state.pending_operator = 'd';

    // 'z' is not in the normal switch, so falls to else => {} then pending handler
    // But 'd' pending with 'z' hits the else in the pending handler which clears it
    const action = handleKey(&state, .{ .key = 'z' });
    try std.testing.expectEqual(core.KeyAction.none, action);
    try std.testing.expectEqual(@as(?u8, null), state.pending_operator);
}

test "vi pending d with dollar sign deletes to eol" {
    // '$' is handled in the normal mode switch and returns immediately.
    // The pending operator handler is unreachable for '$'.
    // Instead, pre-set pending_operator and use a key not in the switch.
    // Actually, '$' IS in the switch and returns .move_eol immediately.
    // So d$ through handleKey returns .move_eol for the second key.
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 3;

    // Set pending operator
    _ = handleKey(&state, .{ .key = 'd' });
    try std.testing.expectEqual(@as(?u8, 'd'), state.pending_operator);

    // '$' with pending 'd' operator returns .delete_to_eol
    const action2 = handleKey(&state, .{ .key = '$' });
    try std.testing.expectEqual(core.KeyAction.delete_to_eol, action2);
}

test "vi insert Escape returns to normal mode" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.vi_mode = .insert;
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 0x1b });
    try std.testing.expectEqual(core.KeyAction.vi_normal_mode, action);
    try std.testing.expectEqual(ViMode.normal, state.vi_mode);
    // Cursor moves back one position on ESC in vi
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "vi insert mode character insertion" {
    var state = try TestState.initWithContent(std.testing.allocator, "hllo");
    defer state.deinit();
    state.vi_mode = .insert;
    state.cursor = 1;

    const action = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqual(core.KeyAction.insert, action);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "vi normal A enters insert mode at end of line" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 2;

    const action = handleKey(&state, .{ .key = 'A' });
    try std.testing.expectEqual(core.KeyAction.vi_insert_mode, action);
    try std.testing.expectEqual(ViMode.insert, state.vi_mode);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "vi normal I enters insert mode at beginning" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'I' });
    try std.testing.expectEqual(core.KeyAction.vi_insert_mode, action);
    try std.testing.expectEqual(ViMode.insert, state.vi_mode);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "vi normal j returns history_next" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'j' });
    try std.testing.expectEqual(core.KeyAction.history_next, action);
}

test "vi normal k returns history_prev" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'k' });
    try std.testing.expectEqual(core.KeyAction.history_prev, action);
}

test "vi normal u returns undo" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'u' });
    try std.testing.expectEqual(core.KeyAction.undo, action);
}

test "vi normal p returns yank" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'p' });
    try std.testing.expectEqual(core.KeyAction.yank, action);
}

test "vi insert Ctrl+C returns cancel and enters normal mode" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.vi_mode = .insert;

    const action = handleKey(&state, .{ .key = 'c', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.cancel, action);
    try std.testing.expectEqual(ViMode.normal, state.vi_mode);
}

test "vi insert backspace returns backspace" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.vi_mode = .insert;
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 0x7f });
    try std.testing.expectEqual(core.KeyAction.backspace, action);
}

test "vi normal C enters insert mode and returns delete_to_eol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 5;

    const action = handleKey(&state, .{ .key = 'C' });
    try std.testing.expectEqual(core.KeyAction.delete_to_eol, action);
    try std.testing.expectEqual(ViMode.insert, state.vi_mode);
}

test "vi normal r sets pending operator for replace" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 1;

    // First 'r' sets pending operator
    const action1 = handleKey(&state, .{ .key = 'r' });
    try std.testing.expectEqual(core.KeyAction.none, action1);
    try std.testing.expectEqual(@as(?u8, 'r'), state.pending_operator);

    // Typing 'x' replaces character at cursor
    const action2 = handleKey(&state, .{ .key = 'x' });
    try std.testing.expectEqual(core.KeyAction.none, action2);
    try std.testing.expectEqual(@as(u8, 'x'), state.buffer.items[1]);
    try std.testing.expectEqual(@as(?u8, null), state.pending_operator);
}

// =============================================================================
// findEndOfWord helper tests (QF-043)
// =============================================================================

test "findEndOfWord at start of single word returns one past end" {
    const buf = "hello";
    try std.testing.expectEqual(@as(usize, 5), findEndOfWord(buf, 0));
}

test "findEndOfWord at middle of word returns one past end" {
    const buf = "hello world";
    try std.testing.expectEqual(@as(usize, 5), findEndOfWord(buf, 2));
}

test "findEndOfWord on whitespace returns same position" {
    const buf = "hello world";
    try std.testing.expectEqual(@as(usize, 5), findEndOfWord(buf, 5));
}

test "findEndOfWord on second word" {
    const buf = "hello world";
    try std.testing.expectEqual(@as(usize, 11), findEndOfWord(buf, 6));
}

test "findEndOfWord with empty buffer" {
    try std.testing.expectEqual(@as(usize, 0), findEndOfWord("", 0));
}

test "findEndOfWord at end of buffer" {
    const buf = "hello";
    try std.testing.expectEqual(@as(usize, 5), findEndOfWord(buf, 5));
}

test "vi normal e motion moves cursor to last char of word" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 0;

    _ = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqual(@as(usize, 4), state.cursor); // 'o' in "hello"
}

test "vi normal e motion on whitespace stays put" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 5; // on the space

    _ = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqual(@as(usize, 5), state.cursor); // no change
}

test "vi de operator deletes to end of word" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 0;
    state.pending_operator = 'd';

    _ = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqualStrings(" world", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "vi de operator from middle of word" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 2;
    state.pending_operator = 'd';

    _ = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqualStrings("he world", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

// =============================================================================
// Delete key tests (GAP-0045/GAP-0046)
// =============================================================================

test "vi normal Delete key returns delete_char_forward" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 2;

    // Delete key (ESC[3~) → SyntheticKey.delete, no ctrl
    const action = handleKey(&state, .{ .key = SyntheticKey.delete });
    try std.testing.expectEqual(core.KeyAction.delete_char_forward, action);
}

test "vi insert Delete key returns delete_char_forward" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.vi_mode = .insert;
    state.cursor = 2;

    // Delete key (ESC[3~) → SyntheticKey.delete, no ctrl
    const action = handleKey(&state, .{ .key = SyntheticKey.delete });
    try std.testing.expectEqual(core.KeyAction.delete_char_forward, action);
}
