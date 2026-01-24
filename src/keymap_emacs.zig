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
            0x7f - 'a' + 1 => .delete_char_forward, // Delete key (mapped from ESC[3~)
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

test "emacs ctrl keys" {
    // This would need a mock state to test properly
    // For now, just ensure it compiles
    _ = handleKey;
}
