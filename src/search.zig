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
            if (c == 0x1b or c == '\r' or c == '\n') {
                state.searching = false;
                break :outer;
            }

            if (c == 0x03) { // Ctrl+C
                state.searching = false;
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
        try stdout.writeAll(search_line);
    }
}
