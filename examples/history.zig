// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Command History Example
//!
//! This example demonstrates:
//! - Persistent history (saved to disk)
//! - History navigation (Ctrl+P/N or Up/Down arrows)
//! - Reverse history search (Ctrl+R)
//! - Programmatic history access
//! - Privacy feature (lines starting with space are not saved)
//!
//! Run with: zig build run-history

const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "history> ",
        .app_name = "history-example",
        .history_enabled = true, // Enable persistent history (default is true)
        // History is automatically saved to ~/.history-example_history
        // Or you can specify a custom path:
        // .history_path = "/custom/path/to/history",
        .run_fn = handleCommand,
        .welcome_fn = printWelcome,
    });
}

fn printWelcome(stdout: std.Io.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Command History Example\n\n");
    try out.write("Navigation:\n");
    try out.write("  Ctrl+P or Up     - Previous command\n");
    try out.write("  Ctrl+N or Down   - Next command\n");
    try out.write("  Ctrl+R           - Reverse search history\n\n");

    try out.write("Commands:\n");
    try out.write("  history          - Show all history entries\n");
    try out.write("  history <n>      - Show last n entries\n");
    try out.write("  search <pattern> - Search history for pattern\n");
    try out.write("  clear-history    - Clear all history\n");
    try out.write("  stats            - Show history statistics\n\n");

    try out.write("Privacy tip: Start a line with a space to prevent\n");
    try out.write("it from being saved to history.\n\n");
}

fn handleCommand(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    input: []const u8,
    history: *repl.HistoryStore,
) anyerror!bool {
    const out = repl.terminalWriter();
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    if (trimmed.len == 0) return true;

    // Parse command and arguments
    var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
    const cmd = parts.next() orelse return true;
    const args = parts.rest();

    if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")) {
        try out.writeSuccess("Goodbye! History has been saved.");
        return false;
    }

    if (std.mem.eql(u8, cmd, "help")) {
        try showHelp(out);
        return true;
    }

    if (std.mem.eql(u8, cmd, "history")) {
        try showHistory(out, history, args);
        return true;
    }

    if (std.mem.eql(u8, cmd, "search")) {
        if (args.len == 0) {
            try out.writeWarning("Usage: search <pattern>");
        } else {
            try searchHistory(out, history, args);
        }
        return true;
    }

    if (std.mem.eql(u8, cmd, "clear-history")) {
        try history.clear();
        try out.writeSuccess("History cleared.");
        return true;
    }

    if (std.mem.eql(u8, cmd, "stats")) {
        try showStats(out, history);
        return true;
    }

    // Echo other commands
    try out.write("Command: ");
    try out.writeColored(.cyan, trimmed);
    try out.write("\n");

    return true;
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nHistory Example Commands\n\n");
    try out.write("  history [n]      - Show history (optionally last n entries)\n");
    try out.write("  search <pattern> - Search history for entries containing pattern\n");
    try out.write("  clear-history    - Delete all history entries\n");
    try out.write("  stats            - Show history statistics\n");
    try out.write("  quit             - Exit the REPL\n\n");

    try out.writeBold("Keyboard Shortcuts\n\n");
    try out.write("  Ctrl+P / Up      - Previous history entry\n");
    try out.write("  Ctrl+N / Down    - Next history entry\n");
    try out.write("  Ctrl+R           - Start reverse history search\n");
    try out.write("                     Type to search, Enter to select\n\n");
}

fn showHistory(out: repl.TerminalWriter, history: *repl.HistoryStore, args: []const u8) !void {
    const count = history.count();

    if (count == 0) {
        try out.writeInfo("No history entries.");
        return;
    }

    // Parse optional limit argument
    var limit: usize = count;
    if (args.len > 0) {
        limit = std.fmt.parseInt(usize, args, 10) catch {
            try out.writeWarning("Invalid number. Usage: history [n]");
            return;
        };
        if (limit > count) limit = count;
    }

    const start = count - limit;

    try out.writeBold("Command History:\n");
    try out.write("(Most recent last)\n\n");

    for (history.entries.items[start..], start..) |entry, i| {
        try out.setColor(.bright_black);
        try out.print("{d:>4}  ", .{i + 1});
        try out.resetStyle();
        try out.writeLine(entry);
    }

    try out.write("\n");
    try out.print("Total: {d} entries\n", .{count});
}

fn searchHistory(out: repl.TerminalWriter, history: *repl.HistoryStore, pattern: []const u8) !void {
    try out.writeBold("Search results for '");
    try out.writeColored(.cyan, pattern);
    try out.write("':\n\n");

    var found: usize = 0;
    var current_idx: ?usize = null;

    // Search backwards through history
    while (found < 20) { // Limit to 20 results
        if (history.searchBackward(pattern, current_idx)) |result| {
            try out.setColor(.bright_black);
            try out.print("{d:>4}  ", .{result.index + 1});
            try out.resetStyle();

            // Highlight the matching portion
            try highlightMatch(out, result.entry, pattern);
            try out.write("\n");

            found += 1;
            current_idx = result.index;
        } else {
            break;
        }
    }

    if (found == 0) {
        try out.writeInfo("No matches found.");
    } else {
        try out.print("\nFound {d} matches.\n", .{found});
    }
}

fn highlightMatch(out: repl.TerminalWriter, text: []const u8, pattern: []const u8) !void {
    var pos: usize = 0;

    while (pos < text.len) {
        if (std.mem.indexOf(u8, text[pos..], pattern)) |match_offset| {
            // Write text before match
            if (match_offset > 0) {
                try out.write(text[pos .. pos + match_offset]);
            }

            // Write highlighted match
            try out.writeColored(.yellow, pattern);

            pos += match_offset + pattern.len;
        } else {
            // Write remaining text
            try out.write(text[pos..]);
            break;
        }
    }
}

fn showStats(out: repl.TerminalWriter, history: *repl.HistoryStore) !void {
    const count = history.count();

    try out.writeBold("\nHistory Statistics\n\n");
    try out.print("  Total entries: {d}\n", .{count});
    try out.print("  Max entries:   {d}\n", .{history.max_entries});
    try out.print("  Persistence:   {s}\n", .{if (history.enabled) "enabled" else "disabled"});

    if (history.path) |path| {
        try out.write("  History file:  ");
        try out.writeLine(path);
    } else {
        try out.write("  History file:  (none)\n");
    }

    try out.write("\n");

    // Calculate some interesting stats
    if (count > 0) {
        var total_len: usize = 0;
        var longest: usize = 0;

        for (history.entries.items) |entry| {
            total_len += entry.len;
            if (entry.len > longest) {
                longest = entry.len;
            }
        }

        try out.print("  Avg length:    {d} chars\n", .{total_len / count});
        try out.print("  Longest:       {d} chars\n", .{longest});
    }

    try out.write("\n");
}
