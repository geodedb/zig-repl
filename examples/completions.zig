// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Tab Completion Example
//!
//! This example demonstrates:
//! - Custom command completion with tab key
//! - Context-aware completion (file paths, arguments)
//! - Using the CompletionContext API
//!
//! Run with: zig build run-completions
//! Try typing "he<Tab>" or "ls <Tab>" for completion.

const std = @import("std");
const repl = @import("repl");

/// Available commands for tab completion
const COMMANDS = [_][]const u8{
    "help",
    "hello",
    "history",
    "list",
    "ls",
    "load",
    "save",
    "set",
    "show",
    "status",
    "quit",
    "exit",
};

/// Subcommands for "set" command
const SET_OPTIONS = [_][]const u8{
    "color",
    "verbose",
    "format",
    "timeout",
    "theme",
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "complete> ",
        .app_name = "completion-example",
        .run_fn = handleCommand,
        .complete_fn = handleCompletion, // Tab completion callback
        .welcome_fn = printWelcome,
    });
}

fn printWelcome(stdout: std.Io.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Tab Completion Example\n\n");
    try out.write("Features:\n");
    try out.write("  - Press Tab to complete commands\n");
    try out.write("  - Press Tab again to cycle through matches\n");
    try out.write("  - Type 'set ' then Tab for subcommand completion\n");
    try out.write("  - Type 'ls ' then Tab for file path completion\n\n");
    try out.write("Try: 'he<Tab>', 'set <Tab>', 'ls ~/<Tab>'\n\n");
}

/// Tab completion callback.
///
/// This function is called when the user presses Tab.
/// It receives the current prefix (word being typed) and a context
/// for adding completion candidates.
fn handleCompletion(prefix: []const u8, ctx: *repl.CompletionContext) void {
    // Check if we're completing a subcommand (e.g., "set <something>")
    // For that, we need to look at the full buffer, which we can reconstruct
    // from the word_start position

    // Simple case: complete commands that start with the prefix
    for (COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }

    // If completing a file path (prefix contains / or ~), add file completions
    if (prefix.len > 0 and (prefix[0] == '/' or prefix[0] == '~' or
        std.mem.indexOf(u8, prefix, "/") != null))
    {
        // Use the built-in file path completion
        repl.completion.generateFilePathCandidates(ctx, prefix) catch {};
    }
}

/// Extended completion that handles subcommands.
/// This demonstrates more sophisticated completion logic.
fn handleSubcommandCompletion(buffer: []const u8, cursor: usize, ctx: *repl.CompletionContext) void {
    // Find where the current word starts
    const word_start = repl.completion.findWordStart(buffer, cursor);
    const prefix = buffer[word_start..cursor];

    // Check if this is a subcommand completion
    if (word_start > 0) {
        // Look for the main command
        var cmd_end: usize = 0;
        for (buffer[0..word_start], 0..) |c, i| {
            if (!std.ascii.isWhitespace(c)) {
                cmd_end = i;
            }
        }

        const main_cmd = std.mem.trim(u8, buffer[0..word_start], " \t");

        // If the main command is "set", offer set subcommands
        if (std.mem.eql(u8, main_cmd, "set")) {
            for (SET_OPTIONS) |opt| {
                if (std.mem.startsWith(u8, opt, prefix)) {
                    ctx.addCandidate(opt) catch {};
                }
            }
            return;
        }

        // If the main command is "ls" or "load", offer file paths
        if (std.mem.eql(u8, main_cmd, "ls") or std.mem.eql(u8, main_cmd, "load")) {
            repl.completion.generateFilePathCandidates(ctx, prefix) catch {};
            return;
        }
    }

    // Fall back to command completion
    for (COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }
}

fn handleCommand(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    input: []const u8,
    _: *repl.HistoryStore,
) anyerror!bool {
    const out = repl.terminalWriter();
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    if (trimmed.len == 0) return true;

    // Parse command and arguments
    var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
    const cmd = parts.next() orelse return true;
    const args = parts.rest();

    if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")) {
        try out.writeSuccess("Goodbye!");
        return false;
    }

    if (std.mem.eql(u8, cmd, "help")) {
        try out.writeBold("Commands:\n");
        try out.write("  help     - Show this help\n");
        try out.write("  hello    - Say hello\n");
        try out.write("  history  - Show command history\n");
        try out.write("  ls       - List files (with path completion)\n");
        try out.write("  load     - Load a file (with path completion)\n");
        try out.write("  save     - Save to a file\n");
        try out.write("  set      - Set options (color, verbose, etc.)\n");
        try out.write("  show     - Show current settings\n");
        try out.write("  status   - Show status\n");
        try out.write("  quit     - Exit\n");
        return true;
    }

    if (std.mem.eql(u8, cmd, "hello")) {
        try out.writeColored(.green, "Hello, World!\n");
        return true;
    }

    if (std.mem.eql(u8, cmd, "set")) {
        if (args.len == 0) {
            try out.writeWarning("Usage: set <option> [value]");
            try out.write("Available options: ");
            for (SET_OPTIONS, 0..) |opt, i| {
                if (i > 0) try out.write(", ");
                try out.write(opt);
            }
            try out.write("\n");
        } else {
            try out.print("Setting: {s}\n", .{args});
        }
        return true;
    }

    if (std.mem.eql(u8, cmd, "ls")) {
        try out.print("Would list: {s}\n", .{if (args.len > 0) args else "."});
        return true;
    }

    try out.writeInfo("Unknown command. Type 'help' for available commands.");
    return true;
}
