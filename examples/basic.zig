// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Basic REPL Example
//!
//! This is the simplest possible REPL setup, demonstrating:
//! - Minimal configuration
//! - Basic command handling
//! - Graceful exit with "quit" command or Ctrl+D
//!
//! Run with: zig build run-basic

const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    // Step 1: Set up the memory allocator
    // GeneralPurposeAllocator is recommended for applications
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 2: Run the REPL with minimal configuration
    // Only the allocator and run_fn are required
    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "basic> ",
        .app_name = "basic-example",
        .run_fn = handleCommand,
        .welcome_fn = printWelcome,
    });
}

/// Welcome message displayed when the REPL starts.
/// This runs BEFORE raw mode is enabled, so regular newlines work.
fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Basic REPL Example\n");
    try out.write("Type 'quit' to exit, or press Ctrl+D on an empty line.\n");
    try out.write("Type anything else to see it echoed back.\n\n");
}

/// Command handler - the core of your REPL.
///
/// This function is called every time the user presses Enter.
/// Return `true` to continue the REPL, `false` to exit.
fn handleCommand(
    _: ?*anyopaque, // user_context - not used in this basic example
    _: std.mem.Allocator, // allocator for dynamic operations
    input: []const u8, // the user's input (trimmed of trailing newline)
    _: *repl.HistoryStore, // history store for advanced operations
) anyerror!bool {
    // Get a terminal writer for output
    // TerminalWriter handles raw mode correctly (converts \n to \r\n)
    const out = repl.terminalWriter();

    // Handle empty input (just pressing Enter)
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) {
        return true; // Continue the REPL
    }

    // Handle quit command
    if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
        try out.writeSuccess("Goodbye!");
        return false; // Exit the REPL
    }

    // Handle help command
    if (std.mem.eql(u8, trimmed, "help")) {
        try out.writeBold("Available commands:\n");
        try out.write("  help    - Show this message\n");
        try out.write("  quit    - Exit the REPL\n");
        try out.write("  <text>  - Echo the text back\n");
        return true;
    }

    // Echo back whatever the user typed
    try out.write("You typed: ");
    try out.writeColored(.cyan, input);
    try out.write("\n");

    return true; // Continue the REPL
}
