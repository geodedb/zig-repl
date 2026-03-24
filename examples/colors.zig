// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Terminal Colors and Styling Example
//!
//! This example demonstrates:
//! - 16-color terminal output (standard + bright variants)
//! - Text styles (bold, dim, italic, underline)
//! - Semantic message helpers (error, warning, success, info)
//! - Color detection and NO_COLOR support
//!
//! Run with: zig build run-colors

const std = @import("std");
const builtin = @import("builtin");
const repl = @import("repl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "colors> ",
        .app_name = "colors-example",
        .run_fn = handleCommand,
        .welcome_fn = printWelcome,
    });
}

fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Terminal Colors and Styling Example\n\n");

    if (use_color) {
        try out.writeColored(.green, "Colors are enabled!\n\n");
    } else {
        try out.write("Colors are disabled (NO_COLOR set or not a TTY)\n\n");
    }

    try out.write("Commands: palette, styles, messages, rainbow, demo, quit\n\n");
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

    if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
        try out.writeSuccess("Goodbye!");
        return false;
    }

    if (std.mem.eql(u8, trimmed, "help")) {
        try showHelp(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "palette")) {
        try showColorPalette(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "styles")) {
        try showStyles(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "messages")) {
        try showMessageTypes(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "rainbow")) {
        try showRainbow(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "demo")) {
        try showDemo(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "status")) {
        try showColorStatus(out);
        return true;
    }

    try out.writeInfo("Unknown command. Type 'help' for available commands.");
    return true;
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nColor Example Commands\n\n");
    try out.write("  palette   - Show all 16 colors\n");
    try out.write("  styles    - Show text styles (bold, italic, etc.)\n");
    try out.write("  messages  - Show message type helpers\n");
    try out.write("  rainbow   - Display a colorful rainbow\n");
    try out.write("  demo      - Show a comprehensive demo\n");
    try out.write("  status    - Show color detection status\n");
    try out.write("  quit      - Exit\n\n");
}

fn showColorPalette(out: repl.TerminalWriter) !void {
    try out.writeBold("\n16-Color Palette\n\n");

    // Standard colors
    try out.write("Standard colors:\n  ");
    const standard_colors = [_]struct { color: repl.Color, name: []const u8 }{
        .{ .color = .black, .name = "black" },
        .{ .color = .red, .name = "red" },
        .{ .color = .green, .name = "green" },
        .{ .color = .yellow, .name = "yellow" },
        .{ .color = .blue, .name = "blue" },
        .{ .color = .magenta, .name = "magenta" },
        .{ .color = .cyan, .name = "cyan" },
        .{ .color = .white, .name = "white" },
    };

    for (standard_colors) |c| {
        try out.setColor(c.color);
        try out.write(c.name);
        try out.resetStyle();
        try out.write(" ");
    }
    try out.write("\n\n");

    // Bright colors
    try out.write("Bright colors:\n  ");
    const bright_colors = [_]struct { color: repl.Color, name: []const u8 }{
        .{ .color = .bright_black, .name = "bright_black" },
        .{ .color = .bright_red, .name = "bright_red" },
        .{ .color = .bright_green, .name = "bright_green" },
        .{ .color = .bright_yellow, .name = "bright_yellow" },
        .{ .color = .bright_blue, .name = "bright_blue" },
        .{ .color = .bright_magenta, .name = "bright_magenta" },
        .{ .color = .bright_cyan, .name = "bright_cyan" },
        .{ .color = .bright_white, .name = "bright_white" },
    };

    for (bright_colors) |c| {
        try out.setColor(c.color);
        try out.write(c.name);
        try out.resetStyle();
        try out.write(" ");
    }
    try out.write("\n\n");

    try out.write("Usage: out.setColor(.green); out.write(\"text\"); out.resetStyle();\n");
    try out.write("   or: out.writeColored(.green, \"text\");\n\n");
}

fn showStyles(out: repl.TerminalWriter) !void {
    try out.writeBold("\nText Styles\n\n");

    try out.write("Available styles:\n\n");

    // Bold
    try out.write("  ");
    try out.setStyle(.bold);
    try out.write("Bold text");
    try out.resetStyle();
    try out.write(" - out.setStyle(.bold) or out.writeBold(\"text\")\n");

    // Dim
    try out.write("  ");
    try out.setStyle(.dim);
    try out.write("Dim text");
    try out.resetStyle();
    try out.write(" - out.setStyle(.dim)\n");

    // Italic
    try out.write("  ");
    try out.setStyle(.italic);
    try out.write("Italic text");
    try out.resetStyle();
    try out.write(" - out.setStyle(.italic)\n");

    // Underline
    try out.write("  ");
    try out.setStyle(.underline);
    try out.write("Underlined text");
    try out.resetStyle();
    try out.write(" - out.setStyle(.underline)\n");

    try out.write("\n");

    // Combined style and color
    try out.write("Combined styles:\n\n");
    try out.write("  ");
    try out.writeStyled(.bold, .cyan, "Bold cyan");
    try out.write(" - out.writeStyled(.bold, .cyan, \"text\")\n");

    try out.write("  ");
    try out.setStyle(.italic);
    try out.setColor(.magenta);
    try out.write("Italic magenta");
    try out.resetStyle();
    try out.write(" - setStyle + setColor\n\n");
}

fn showMessageTypes(out: repl.TerminalWriter) !void {
    try out.writeBold("\nMessage Type Helpers\n\n");

    try out.write("The library provides semantic message helpers:\n\n");

    try out.writeError("This is an error message");
    try out.writeWarning("This is a warning message");
    try out.writeSuccess("This is a success message");
    try out.writeInfo("This is an info message");

    try out.write("\nUsage:\n");
    try out.write("  out.writeError(\"message\");   // Red with 'Error: ' prefix\n");
    try out.write("  out.writeWarning(\"message\"); // Yellow with 'Warning: ' prefix\n");
    try out.write("  out.writeSuccess(\"message\"); // Green text\n");
    try out.write("  out.writeInfo(\"message\");    // Cyan text\n\n");
}

fn showRainbow(out: repl.TerminalWriter) !void {
    try out.write("\n");

    const colors = [_]repl.Color{ .red, .yellow, .green, .cyan, .blue, .magenta };
    const text = "RAINBOW";

    // Print multiple lines of rainbow text
    for (0..3) |_| {
        try out.write("  ");
        for (text, 0..) |c, i| {
            try out.setColor(colors[i % colors.len]);
            try out.setStyle(.bold);
            try out.write(&[_]u8{c});
        }
        try out.resetStyle();
        try out.write("  ");
        for (text, 0..) |c, i| {
            try out.setColor(colors[(i + 2) % colors.len]);
            try out.write(&[_]u8{c});
        }
        try out.resetStyle();
        try out.write("  ");
        for (text, 0..) |c, i| {
            try out.setColor(colors[(i + 4) % colors.len]);
            try out.setStyle(.italic);
            try out.write(&[_]u8{c});
        }
        try out.resetStyle();
        try out.write("\n");
    }
    try out.write("\n");
}

fn showDemo(out: repl.TerminalWriter) !void {
    try out.writeBold("\nComprehensive Color Demo\n");
    try out.write("=========================\n\n");

    // Show a sample "log output" with different colors
    try out.setColor(.bright_black);
    try out.write("[2024-01-15 10:30:45] ");
    try out.setColor(.cyan);
    try out.write("INFO  ");
    try out.resetStyle();
    try out.write("Application started\n");

    try out.setColor(.bright_black);
    try out.write("[2024-01-15 10:30:46] ");
    try out.setColor(.green);
    try out.write("OK    ");
    try out.resetStyle();
    try out.write("Connected to database\n");

    try out.setColor(.bright_black);
    try out.write("[2024-01-15 10:30:47] ");
    try out.setColor(.yellow);
    try out.write("WARN  ");
    try out.resetStyle();
    try out.write("Cache miss for key 'user:123'\n");

    try out.setColor(.bright_black);
    try out.write("[2024-01-15 10:30:48] ");
    try out.setColor(.red);
    try out.write("ERROR ");
    try out.resetStyle();
    try out.write("Failed to process request: timeout\n");

    try out.write("\n");

    // Show a table-like output
    try out.writeBold("Status Report\n");
    try out.setColor(.bright_black);
    try out.write("-------------\n");
    try out.resetStyle();

    try out.write("  Service A: ");
    try out.writeColored(.green, "RUNNING");
    try out.write("\n");

    try out.write("  Service B: ");
    try out.writeColored(.yellow, "DEGRADED");
    try out.write("\n");

    try out.write("  Service C: ");
    try out.writeColored(.red, "DOWN");
    try out.write("\n\n");
}

fn showColorStatus(out: repl.TerminalWriter) !void {
    try out.writeBold("\nColor Detection Status\n\n");

    try out.print("  TTY detected:       {s}\n", .{if (repl.isStdoutTty()) "yes" else "no"});
    try out.print("  Colors enabled:     {s}\n", .{if (out.use_color) "yes" else "no"});
    try out.print("  shouldUseColor():   {s}\n", .{if (repl.platform.shouldUseColor()) "yes" else "no"});

    // Check environment
    if (builtin.os.tag == .windows) {
        if (std.process.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("NO_COLOR"))) |_| {
            try out.write("  NO_COLOR:           set (colors disabled)\n");
        } else {
            try out.write("  NO_COLOR:           not set\n");
        }
        try out.write("  TERM:               (not applicable on Windows)\n");
    } else {
        if (std.posix.getenv("NO_COLOR")) |_| {
            try out.write("  NO_COLOR:           set (colors disabled)\n");
        } else {
            try out.write("  NO_COLOR:           not set\n");
        }
        if (std.posix.getenv("TERM")) |term| {
            try out.write("  TERM:               ");
            try out.writeLine(term);
        } else {
            try out.write("  TERM:               not set\n");
        }
    }

    try out.write("\nTo disable colors: export NO_COLOR=1\n\n");
}
