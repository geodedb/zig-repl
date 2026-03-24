// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Emacs-style keybindings
//!
//! Standard Emacs keybindings for line editing:
//! - Ctrl+A/E: Beginning/end of line
//! - Ctrl+B/F: Backward/forward character
//! - Ctrl+P/N: Previous/next history
//! - Ctrl+K: Kill to end of line
//! - Ctrl+U: Kill to beginning of line
//! - Ctrl+W: Kill word backward
//! - Ctrl+Y: Yank from kill ring
//! - Alt+B/F: Backward/forward word
//! - Ctrl+R: Reverse search
//! - Ctrl+_: Undo last edit
//! - Ctrl+L: Clear screen

const std = @import("std");
const core = @import("core.zig");

/// Handle a key event in Emacs mode.
/// Returns the action to perform, potentially modifying state for insert actions.
pub fn handleKey(state: anytype, key: core.KeyEvent) core.KeyAction {
    // Handle Ctrl+Alt combinations first (Ctrl+Home, Ctrl+End for history navigation)
    if (key.ctrl and key.alt) {
        return switch (key.key) {
            'a' => .history_first, // Ctrl+Home: first history entry
            'e' => .history_last, // Ctrl+End: last history entry
            'i' => .reverse_tab, // Shift+Tab: unindent (remove leading spaces/tab)
            else => .none,
        };
    }

    if (key.ctrl) {
        return switch (key.key) {
            'a' => .move_bol, // Ctrl+A / Home: beginning of line
            'e' => .move_eol, // Ctrl+E / End: end of line
            'b' => .move_left, // Ctrl+B / Left: backward char
            'f' => .move_right, // Ctrl+F / Right: forward char
            'p' => .history_prev, // Ctrl+P / Up: previous history
            'n' => .history_next, // Ctrl+N / Down: next history
            'd' => if (state.buffer.items.len == 0) .quit else .delete_char, // Ctrl+D: delete char or EOF
            'k' => .delete_to_eol, // Ctrl+K: kill to end of line
            'u' => .delete_to_bol, // Ctrl+U: kill to beginning of line
            'w' => .delete_word_backward, // Ctrl+W: kill word backward
            'y' => .yank, // Ctrl+Y: yank from kill ring
            'l' => .clear_screen, // Ctrl+L: clear screen
            'r' => .search, // Ctrl+R: reverse search
            'c' => .cancel, // Ctrl+C: cancel
            'i', '\t' => .complete, // Tab: trigger tab completion
            'j', 'm', '\r', '\n' => .run, // Enter: run command
            0x7f => .undo, // Ctrl+_ (0x1f -> key 0x7f): undo last edit
            else => .none,
        };
    }

    if (key.alt) {
        return switch (key.key) {
            'b' => .move_word_left, // Alt+B / Ctrl+Left: backward word
            'f' => .move_word_right, // Alt+F / Ctrl+Right: forward word
            'd' => .delete_word, // Alt+D: delete word forward
            'w' => .delete_word_backward, // Alt+W: delete word backward (alternative)
            else => .none,
        };
    }

    // Regular characters
    if (key.key >= 0x20 and key.key < 0x7f) {
        state.buffer.insert(state.allocator, state.cursor, key.key) catch return .none;
        state.cursor += 1;
        return .insert;
    }

    // Special keys (codes from parseKeyEvent)
    return switch (key.key) {
        0x1b => .none, // ESC: do nothing in Emacs mode
        0x7f, 0x08 => .backspace, // Backspace (DEL or BS)
        0x02 => .none, // Insert key - no action in emacs mode
        0x05 => .history_first, // Page Up - go to first history
        0x06 => .history_last, // Page Down - go to last history
        else => .none,
    };
}

// =============================================================================
// Test support: mock state struct satisfying the `anytype` interface
//
// This TestState is intentionally separate from the one in keymap_vi.zig.
// The Vi version carries additional fields (vi_mode, pending_operator,
// kill_ring, last_was_kill) that are irrelevant to Emacs-mode tests.
// Keeping them independent avoids coupling test helpers to unrelated keymaps.
// =============================================================================

const TestState = struct {
    buffer: std.ArrayList(u8),
    cursor: usize,
    allocator: std.mem.Allocator,

    fn initWithContent(allocator: std.mem.Allocator, content: []const u8) !TestState {
        var buf = try std.ArrayList(u8).initCapacity(allocator, content.len);
        try buf.appendSlice(allocator, content);
        return .{
            .buffer = buf,
            .cursor = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestState) void {
        self.buffer.deinit(self.allocator);
    }
};

test "emacs Ctrl+A returns move_bol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'a', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.move_bol, action);
}

test "emacs Ctrl+E returns move_eol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'e', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.move_eol, action);
}

test "emacs Ctrl+K returns delete_to_eol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 5;

    const action = handleKey(&state, .{ .key = 'k', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.delete_to_eol, action);
}

test "emacs Ctrl+D deletes char when buffer non-empty" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 2;

    const action = handleKey(&state, .{ .key = 'd', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.delete_char, action);
}

test "emacs Ctrl+D quits on empty buffer" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'd', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.quit, action);
}

test "emacs Tab triggers completion" {
    var state = try TestState.initWithContent(std.testing.allocator, "sel");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'i', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.complete, action);
}

test "emacs Ctrl+B returns move_left" {
    var state = try TestState.initWithContent(std.testing.allocator, "ab");
    defer state.deinit();
    state.cursor = 1;

    const action = handleKey(&state, .{ .key = 'b', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.move_left, action);
}

test "emacs Ctrl+F returns move_right" {
    var state = try TestState.initWithContent(std.testing.allocator, "ab");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'f', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.move_right, action);
}

test "emacs Ctrl+P returns history_prev" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'p', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.history_prev, action);
}

test "emacs Ctrl+N returns history_next" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'n', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.history_next, action);
}

test "emacs Ctrl+U returns delete_to_bol" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'u', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.delete_to_bol, action);
}

test "emacs Ctrl+W returns delete_word_backward" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 11;

    const action = handleKey(&state, .{ .key = 'w', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.delete_word_backward, action);
}

test "emacs Ctrl+Y returns yank" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'y', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.yank, action);
}

test "emacs Ctrl+L returns clear_screen" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'l', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.clear_screen, action);
}

test "emacs Ctrl+R returns search" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'r', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.search, action);
}

test "emacs Ctrl+C returns cancel" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'c', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.cancel, action);
}

test "emacs Enter (Ctrl+J) returns run" {
    var state = try TestState.initWithContent(std.testing.allocator, "cmd");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 'j', .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.run, action);
}

test "emacs Alt+B returns move_word_left" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 8;

    const action = handleKey(&state, .{ .key = 'b', .alt = true });
    try std.testing.expectEqual(core.KeyAction.move_word_left, action);
}

test "emacs Alt+F returns move_word_right" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'f', .alt = true });
    try std.testing.expectEqual(core.KeyAction.move_word_right, action);
}

test "emacs Alt+D returns delete_word" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello world");
    defer state.deinit();
    state.cursor = 0;

    const action = handleKey(&state, .{ .key = 'd', .alt = true });
    try std.testing.expectEqual(core.KeyAction.delete_word, action);
}

test "emacs printable character inserts into buffer" {
    var state = try TestState.initWithContent(std.testing.allocator, "hllo");
    defer state.deinit();
    state.cursor = 1;

    const action = handleKey(&state, .{ .key = 'e' });
    try std.testing.expectEqual(core.KeyAction.insert, action);
    try std.testing.expectEqualStrings("hello", state.buffer.items);
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

test "emacs Backspace returns backspace" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    const action = handleKey(&state, .{ .key = 0x7f });
    try std.testing.expectEqual(core.KeyAction.backspace, action);
}

test "emacs ESC returns none" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 0x1b });
    try std.testing.expectEqual(core.KeyAction.none, action);
}

test "emacs Ctrl+Alt+A returns history_first" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'a', .ctrl = true, .alt = true });
    try std.testing.expectEqual(core.KeyAction.history_first, action);
}

test "emacs Ctrl+Alt+E returns history_last" {
    var state = try TestState.initWithContent(std.testing.allocator, "");
    defer state.deinit();

    const action = handleKey(&state, .{ .key = 'e', .ctrl = true, .alt = true });
    try std.testing.expectEqual(core.KeyAction.history_last, action);
}

test "emacs Ctrl+_ returns undo" {
    var state = try TestState.initWithContent(std.testing.allocator, "hello");
    defer state.deinit();
    state.cursor = 3;

    // Ctrl+_ sends raw 0x1f which the input parser maps to key=0x7f, ctrl=true
    const action = handleKey(&state, .{ .key = 0x7f, .ctrl = true });
    try std.testing.expectEqual(core.KeyAction.undo, action);
}
