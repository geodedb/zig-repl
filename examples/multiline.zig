// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Multi-line Input Example
//!
//! This example demonstrates:
//! - Automatic multi-line detection (unbalanced brackets)
//! - Backslash continuation (line ending with \)
//! - Custom is_complete_fn for language-specific syntax
//! - Continuation prompts
//!
//! Run with: zig build run-multiline

const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "multi> ",
        .continuation_prompt = "  ... ", // Shown when input continues to next line
        .app_name = "multiline-example",
        .run_fn = handleCommand,
        .is_complete_fn = isInputComplete, // Custom completion detection
        .welcome_fn = printWelcome,
    });
}

fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Multi-line Input Example\n\n");
    try out.write("This REPL automatically continues input when:\n\n");

    try out.writeColored(.cyan, "1. Unbalanced brackets:\n");
    try out.writeColored(.bright_black, "   multi> function(arg1,\n");
    try out.writeColored(.bright_black, "     ...   arg2,\n");
    try out.writeColored(.bright_black, "     ...   arg3)\n\n");

    try out.writeColored(.cyan, "2. Backslash continuation:\n");
    try out.writeColored(.bright_black, "   multi> this is a long \\\n");
    try out.writeColored(.bright_black, "     ...  line that continues\n\n");

    try out.writeColored(.cyan, "3. Trailing operators:\n");
    try out.writeColored(.bright_black, "   multi> value1 +\n");
    try out.writeColored(.bright_black, "     ...  value2\n\n");

    try out.writeColored(.cyan, "4. Unclosed strings:\n");
    try out.writeColored(.bright_black, "   multi> \"this string\n");
    try out.writeColored(.bright_black, "     ...  spans lines\"\n\n");

    try out.write("Commands: show, json, code, quit\n\n");
}

/// Custom input completion checker.
///
/// This function determines whether the input is a complete statement.
/// Return false to continue reading input on the next line.
fn isInputComplete(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    // Empty input is complete
    if (trimmed.len == 0) return true;

    // Check for explicit backslash continuation
    if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\\') {
        return false;
    }

    // Use the library's built-in bracket balancing check
    if (!repl.isBalanced(input)) {
        return false;
    }

    // Check for trailing operators that suggest continuation
    if (repl.needsContinuation(input)) {
        return false;
    }

    return true;
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

    // Parse first word as command
    var it = std.mem.tokenizeAny(u8, trimmed, " \t\n");
    const first_word = it.next() orelse return true;

    if (std.mem.eql(u8, first_word, "quit") or std.mem.eql(u8, first_word, "exit")) {
        try out.writeSuccess("Goodbye!");
        return false;
    }

    if (std.mem.eql(u8, first_word, "help")) {
        try showHelp(out);
        return true;
    }

    if (std.mem.eql(u8, first_word, "show")) {
        try showInput(out, input);
        return true;
    }

    if (std.mem.eql(u8, first_word, "json")) {
        try showJsonExample(out);
        return true;
    }

    if (std.mem.eql(u8, first_word, "code")) {
        try showCodeExample(out);
        return true;
    }

    // Default: show the received input with analysis
    try showInput(out, input);
    return true;
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nMulti-line Example Commands\n\n");
    try out.write("  show         - Display how your input was parsed\n");
    try out.write("  json         - Example JSON input prompt\n");
    try out.write("  code         - Example code block prompt\n");
    try out.write("  quit         - Exit the REPL\n\n");

    try out.write("Try typing multi-line input:\n");
    try out.write("  - Open a bracket: (\n");
    try out.write("  - End with backslash: \\\n");
    try out.write("  - End with operator: +\n\n");
}

fn showInput(out: repl.TerminalWriter, input: []const u8) !void {
    // Count lines
    var line_count: usize = 1;
    for (input) |c| {
        if (c == '\n') line_count += 1;
    }

    try out.writeBold("\nReceived Input:\n");
    try out.write("---------------\n");

    // Show each line numbered
    var lines = std.mem.splitScalar(u8, input, '\n');
    var line_num: usize = 1;
    while (lines.next()) |line| {
        try out.setColor(.bright_black);
        try out.print("{d:>3} | ", .{line_num});
        try out.resetStyle();
        try out.write(line);
        try out.write("\n");
        line_num += 1;
    }

    try out.write("---------------\n");
    try out.print("Lines: {d}, Total bytes: {d}\n\n", .{ line_count, input.len });

    // Analyze the input
    try out.writeColored(.cyan, "Analysis:\n");
    try out.print("  Brackets balanced: {s}\n", .{if (repl.isBalanced(input)) "yes" else "no"});
    try out.print("  Needs continuation: {s}\n", .{if (repl.needsContinuation(input)) "yes" else "no"});
    try out.print("  Is complete: {s}\n\n", .{if (repl.isComplete(input)) "yes" else "no"});
}

fn showJsonExample(out: repl.TerminalWriter) !void {
    try out.writeBold("\nJSON Input Example\n");
    try out.write("Type a JSON object - it will continue until braces are balanced:\n\n");
    try out.writeColored(.bright_black, "  multi> {\n");
    try out.writeColored(.bright_black, "    ...   \"name\": \"example\",\n");
    try out.writeColored(.bright_black, "    ...   \"values\": [\n");
    try out.writeColored(.bright_black, "    ...     1,\n");
    try out.writeColored(.bright_black, "    ...     2,\n");
    try out.writeColored(.bright_black, "    ...     3\n");
    try out.writeColored(.bright_black, "    ...   ]\n");
    try out.writeColored(.bright_black, "    ... }\n\n");
    try out.write("Try it yourself! Type '{' and press Enter.\n\n");
}

fn showCodeExample(out: repl.TerminalWriter) !void {
    try out.writeBold("\nCode Block Example\n");
    try out.write("Enter code with proper bracket matching:\n\n");
    try out.writeColored(.bright_black, "  multi> fn calculate(\n");
    try out.writeColored(.bright_black, "    ...     x: i32,\n");
    try out.writeColored(.bright_black, "    ...     y: i32\n");
    try out.writeColored(.bright_black, "    ... ) i32 {\n");
    try out.writeColored(.bright_black, "    ...     return x + y;\n");
    try out.writeColored(.bright_black, "    ... }\n\n");
    try out.write("The REPL tracks (, [, and { to determine completeness.\n\n");
}
