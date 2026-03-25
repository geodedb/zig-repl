// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Rendering calculation utilities for terminal output.
//!
//! Pure functions for computing visual line counts and cursor positions,
//! accounting for terminal width, tabs, and newlines.

/// Standard tab stop interval for visual width calculations.
pub const TAB_STOP = 8;

/// Calculate tab width at a given column.
pub fn tabWidth(col: usize) usize {
    return TAB_STOP - (col % TAB_STOP);
}

/// Calculate number of visual lines accounting for terminal width.
pub fn calculateVisualLines(prompt_len: usize, buffer: []const u8, term_width: usize) usize {
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

/// Calculate cursor position accounting for wraps.
pub fn calculateCursorPosition(prompt_len: usize, buffer: []const u8, cursor: usize, term_width: usize) struct { rows_from_end: usize, col: usize } {
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

// =============================================================================
// Tests
// =============================================================================

const testing = @import("std").testing;

// --- tabWidth tests ---

test "tabWidth at column 0 returns full tab stop" {
    try testing.expectEqual(@as(usize, 8), tabWidth(0));
}

test "tabWidth at column 1 returns 7" {
    try testing.expectEqual(@as(usize, 7), tabWidth(1));
}

test "tabWidth at column 7 returns 1" {
    try testing.expectEqual(@as(usize, 1), tabWidth(7));
}

test "tabWidth at column 8 returns full tab stop again" {
    try testing.expectEqual(@as(usize, 8), tabWidth(8));
}

test "tabWidth at column 9 returns 7" {
    try testing.expectEqual(@as(usize, 7), tabWidth(9));
}

test "tabWidth at column 15 returns 1" {
    try testing.expectEqual(@as(usize, 1), tabWidth(15));
}

// --- calculateVisualLines tests ---

test "calculateVisualLines empty buffer returns 0 lines" {
    try testing.expectEqual(@as(usize, 0), calculateVisualLines(0, "", 80));
}

test "calculateVisualLines short text no wrap returns 0 extra lines" {
    try testing.expectEqual(@as(usize, 0), calculateVisualLines(0, "hello", 80));
}

test "calculateVisualLines text exactly at terminal width wraps" {
    // 10 chars in a 10-wide terminal: col reaches 10 on the last char, triggering a wrap
    try testing.expectEqual(@as(usize, 1), calculateVisualLines(0, "1234567890", 10));
}

test "calculateVisualLines text wrapping multiple times" {
    // 25 chars in a 10-wide terminal: wraps at 10, 20, remainder 5
    try testing.expectEqual(@as(usize, 2), calculateVisualLines(0, "1234567890123456789012345", 10));
}

test "calculateVisualLines text with newlines" {
    // "abc\ndef" = newline at index 3, so 1 extra line
    try testing.expectEqual(@as(usize, 1), calculateVisualLines(0, "abc\ndef", 80));
}

test "calculateVisualLines text with multiple newlines" {
    try testing.expectEqual(@as(usize, 2), calculateVisualLines(0, "a\nb\nc", 80));
}

test "calculateVisualLines text with tabs" {
    // Single tab at column 0 takes 8 chars; in an 80-wide terminal, no wrap
    try testing.expectEqual(@as(usize, 0), calculateVisualLines(0, "\t", 80));
}

test "calculateVisualLines tab causing wrap" {
    // Tab at col 0 = 8 chars wide; terminal width 5 -> col becomes 8 >= 5, wraps
    try testing.expectEqual(@as(usize, 1), calculateVisualLines(0, "\t", 5));
}

test "calculateVisualLines terminal_width 0 edge case returns 1" {
    try testing.expectEqual(@as(usize, 1), calculateVisualLines(0, "anything", 0));
}

test "calculateVisualLines with prompt_len" {
    // prompt_len=4, buffer="123456", terminal=10: col starts at 4, reaches 10 at 6th char -> wrap
    try testing.expectEqual(@as(usize, 1), calculateVisualLines(4, "123456", 10));
}

test "calculateVisualLines prompt_len alone causes no wrap" {
    // prompt_len=4, buffer="12345", terminal=10: col reaches 9, no wrap
    try testing.expectEqual(@as(usize, 0), calculateVisualLines(4, "12345", 10));
}

// --- calculateCursorPosition tests ---

test "calculateCursorPosition cursor at 0 with empty buffer" {
    const pos = calculateCursorPosition(0, "", 0, 80);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 0), pos.col);
}

test "calculateCursorPosition cursor at 0 with text" {
    const pos = calculateCursorPosition(0, "hello", 0, 80);
    // cursor is at start; total_lines=0 (no wrap for 5 chars in 80 cols)
    // rows_from_end = 0 - 0 = 0, col = 0
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 0), pos.col);
}

test "calculateCursorPosition cursor at end of short text" {
    const pos = calculateCursorPosition(0, "hello", 5, 80);
    // cursor past end, found_cursor=false, cursor_line = total_lines=0, cursor_col = col=5
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 5), pos.col);
}

test "calculateCursorPosition cursor past terminal width wrapping" {
    // Buffer: 15 chars, terminal width 10.
    // Chars 0..9: col goes from 0 to 10, wraps -> total_lines=1, col=0
    // Chars 10..14: col goes from 0 to 5 -> total_lines=1
    // Cursor at 12: found at i=12, cursor_line=1, cursor_col=2
    // rows_from_end = 1 - 1 = 0
    const pos = calculateCursorPosition(0, "123456789012345", 12, 10);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 2), pos.col);
}

test "calculateCursorPosition cursor at newline" {
    // "abc\ndef": at i=3 (the \n), cursor is found with col=3, total_lines=0
    // After processing \n: total_lines=1, col=0
    // Then 'd','e','f': col=3, total_lines=1
    // rows_from_end = 1 - 0 = 1
    const pos = calculateCursorPosition(0, "abc\ndef", 3, 80);
    try testing.expectEqual(@as(usize, 1), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 3), pos.col);
}

test "calculateCursorPosition cursor after newline" {
    // Cursor at 4 (the 'd'): total_lines=1 (after \n), col=0 at that point
    // After processing rest: total_lines=1, col=3
    // rows_from_end = 1 - 1 = 0, col = 0
    const pos = calculateCursorPosition(0, "abc\ndef", 4, 80);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 0), pos.col);
}

test "calculateCursorPosition cursor with tabs" {
    // Buffer: "\thello", cursor at 1 ('h')
    // At i=0 (tab): cursor not yet found. Tab width at col 0 = 8. col=8, <80 no wrap.
    // At i=1 ('h'): cursor found. cursor_line=0, cursor_col=8. col becomes 9.
    // rows_from_end = 0 - 0 = 0
    const pos = calculateCursorPosition(0, "\thello", 1, 80);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 8), pos.col);
}

test "calculateCursorPosition terminal_width 0 edge case" {
    const pos = calculateCursorPosition(0, "test", 2, 0);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 2), pos.col);
}

test "calculateCursorPosition terminal_width 0 with prompt" {
    const pos = calculateCursorPosition(4, "test", 2, 0);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 6), pos.col);
}

test "calculateCursorPosition with prompt_len" {
    // prompt_len=4, buffer="123456", cursor=6 (end), term_width=10
    // col starts at 4, reaches 10 at i=5 (6th char), wraps
    // cursor=6 not found in loop, cursor_line = total_lines = 1, cursor_col = col = 0
    const pos = calculateCursorPosition(4, "123456", 6, 10);
    try testing.expectEqual(@as(usize, 0), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 0), pos.col);
}

test "calculateCursorPosition cursor on first line of multiline" {
    // "1234567890abcde", cursor=3, term_width=10
    // At i=3: cursor found, cursor_line=0, cursor_col=3
    // Processing continues: wraps at i=9 (col reaches 10)
    // At end: total_lines=1, rows_from_end = 1 - 0 = 1
    const pos = calculateCursorPosition(0, "1234567890abcde", 3, 10);
    try testing.expectEqual(@as(usize, 1), pos.rows_from_end);
    try testing.expectEqual(@as(usize, 3), pos.col);
}
