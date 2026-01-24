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

/// Vi editing mode
pub const ViMode = enum {
    normal,
    insert,
    visual,
};

/// Handle a key event in Vi mode.
pub fn handleKey(state: anytype, key: core.KeyEvent) core.KeyAction {
    switch (state.vi_mode) {
        .normal => return handleNormalMode(state, key),
        .insert => return handleInsertMode(state, key),
        .visual => return handleNormalMode(state, key), // Simplified: treat as normal
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
            state.buffer.append(state.allocator, '\n') catch {};
            state.cursor += 1;
            return .vi_insert_mode;
        },
        'O' => {
            state.vi_mode = .insert;
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
            // Move to end of word
            var i = state.cursor;
            if (i < state.buffer.items.len and !std.ascii.isWhitespace(state.buffer.items[i])) {
                while (i < state.buffer.items.len - 1 and !std.ascii.isWhitespace(state.buffer.items[i + 1])) : (i += 1) {}
            }
            state.cursor = i;
            return .none;
        },

        // Deletion
        'x' => return .delete_char_forward, // Delete char at cursor
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

    // Handle pending operators
    if (state.pending_operator) |op| {
        if (op == 'd') {
            switch (key.key) {
                'd' => {
                    // dd: delete line
                    state.kill_ring.clearRetainingCapacity();
                    state.kill_ring.appendSlice(state.allocator, state.buffer.items) catch {};
                    state.buffer.clearRetainingCapacity();
                    state.cursor = 0;
                    state.last_was_kill = true;
                    state.pending_operator = null;
                    return .none;
                },
                'w' => {
                    // dw: delete word
                    const end = findWordEnd(state.buffer.items, state.cursor);
                    state.kill_ring.clearRetainingCapacity();
                    state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..end]) catch {};
                    while (state.cursor < end) {
                        _ = state.buffer.orderedRemove(state.cursor);
                    }
                    state.last_was_kill = true;
                    state.pending_operator = null;
                    return .none;
                },
                'b' => {
                    // db: delete word backward
                    const start = findWordStart(state.buffer.items, state.cursor);
                    state.kill_ring.clearRetainingCapacity();
                    state.kill_ring.appendSlice(state.allocator, state.buffer.items[start..state.cursor]) catch {};
                    while (state.cursor > start) {
                        state.cursor -= 1;
                        _ = state.buffer.orderedRemove(state.cursor);
                    }
                    state.last_was_kill = true;
                    state.pending_operator = null;
                    return .none;
                },
                'e' => {
                    // de: delete to end of word
                    var end = state.cursor;
                    if (end < state.buffer.items.len and !std.ascii.isWhitespace(state.buffer.items[end])) {
                        while (end < state.buffer.items.len - 1 and !std.ascii.isWhitespace(state.buffer.items[end + 1])) : (end += 1) {}
                        end += 1;
                    }
                    state.kill_ring.clearRetainingCapacity();
                    state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..end]) catch {};
                    while (state.cursor < end) {
                        _ = state.buffer.orderedRemove(state.cursor);
                    }
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
    }

    return .none;
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
            0x7f - 'a' + 1 => .delete_char_forward, // Delete key
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
        0x05 => .history_first, // Page Up
        0x06 => .history_last, // Page Down
        else => .none,
    };
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

test "vi mode transitions" {
    // This would need a mock state to test properly
    // For now, just ensure it compiles
    _ = handleKey;
    _ = ViMode.normal;
}
