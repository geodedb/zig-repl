// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Interactive reverse-incremental search
//!
//! Handles the Ctrl-R (reverse-i-search) interaction loop:
//! reads keystrokes from stdin, updates the search pattern,
//! and displays matching history entries.

const std = @import("std");
const platform = @import("platform.zig");
const text_utils = @import("text_utils.zig");
const core = @import("core.zig");

const appendHistoryFiltered = text_utils.appendHistoryFiltered;

/// Run the interactive reverse-incremental search loop.
/// Reads from stdin, searching history as the user types. Exits on
/// ESC / Enter / Ctrl-C. On Ctrl-C the edit buffer is cleared.
pub fn handleSearch(state: *core.ReplState) !void {
    const stdout = platform.getStdoutHandle();
    try stdout.writeAll("\r\n(reverse-i-search)`': ");

    state.search_buffer.clearRetainingCapacity();

    const stdin = platform.getStdinHandle();
    var search_buf: [256]u8 = undefined;

    outer: while (true) {
        const n = try stdin.read(&search_buf);
        if (n == 0) continue;

        for (search_buf[0..n]) |c| {
            // QF-087: Split ESC from Enter/newline to handle history_index correctly.
            // ESC cancels the search and resets history position so subsequent
            // Up/Down navigation starts from the end of history.
            if (c == 0x1b) {
                state.searching = false;
                state.history_index = null;
                break :outer;
            }

            // Enter/newline accepts the search result, keeping the found
            // history position so the user can continue navigating from there.
            if (c == '\r' or c == '\n') {
                state.searching = false;
                break :outer;
            }

            if (c == 0x03) { // Ctrl+C
                state.searching = false;
                state.history_index = null; // QF-087: reset stale position
                state.buffer.clearRetainingCapacity();
                state.cursor = 0;
                break :outer;
            }

            if (c == 0x7f or c == 0x08) {
                if (state.search_buffer.items.len > 0) {
                    _ = state.search_buffer.pop();
                }
            } else if (c >= 0x20 and c < 0x7f) {
                try state.search_buffer.append(state.allocator, c);
            }
        }

        // Find in history (after processing all bytes in this read batch)
        var found = false;
        if (state.history.searchBackward(state.search_buffer.items, null)) |result| {
            state.buffer.clearRetainingCapacity();
            try appendHistoryFiltered(&state.buffer, state.allocator, result.entry);
            state.cursor = state.buffer.items.len;
            state.history_index = result.index;
            found = true;
        }

        var line_buf: [4096]u8 = undefined;
        // Safety: search_buffer only contains printable ASCII (0x20-0x7f) filtered above
        const search_line = std.fmt.bufPrint(&line_buf, "\r(reverse-i-search)`{s}': {s}", .{
            state.search_buffer.items,
            if (found) state.buffer.items else "",
        }) catch &line_buf; // graceful truncation on overflow

        // SF-029: Replace newlines with spaces in the display output to prevent
        // garbled rendering in raw terminal mode. Multi-line history entries
        // contain raw \n which would move the cursor without a \r, causing
        // misaligned output. We modify only the display buffer, not state.buffer.
        const display_line = replaceNewlinesForDisplay(search_line);
        try stdout.writeAll(display_line);
    }
}

/// Replace newline characters with spaces in a mutable buffer slice.
///
/// In raw terminal mode, a bare `\n` moves the cursor down without returning
/// to column 0, causing garbled display output. This function substitutes
/// newlines with spaces so multi-line history entries display on a single
/// line in the search prompt. The replacement is done in-place on the
/// bufPrint output buffer -- the caller's `state.buffer` is never modified.
fn replaceNewlinesForDisplay(buf: []u8) []u8 {
    for (buf) |*ch| {
        if (ch.* == '\n') {
            ch.* = ' ';
        }
    }
    return buf;
}

// =============================================================================
// Tests
// =============================================================================

test "replaceNewlinesForDisplay replaces newlines with spaces" {
    var buf = "hello\nworld".*;
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqualStrings("hello world", result);
}

test "replaceNewlinesForDisplay handles multiple newlines" {
    var buf = "line1\nline2\nline3".*;
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqualStrings("line1 line2 line3", result);
}

test "replaceNewlinesForDisplay handles no newlines" {
    var buf = "no newlines here".*;
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqualStrings("no newlines here", result);
}

test "replaceNewlinesForDisplay handles empty input" {
    var buf = [_]u8{};
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "replaceNewlinesForDisplay handles only newlines" {
    var buf = "\n\n\n".*;
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqualStrings("   ", result);
}

test "replaceNewlinesForDisplay preserves carriage returns" {
    // \r is used for cursor positioning and should NOT be replaced
    var buf = "\r(search)`q': line1\nline2".*;
    const result = replaceNewlinesForDisplay(&buf);
    try std.testing.expectEqualStrings("\r(search)`q': line1 line2", result);
}
