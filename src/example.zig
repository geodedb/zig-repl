// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Example REPL Application
//!
//! A comprehensive example demonstrating all major features of the REPL library:
//!
//! - Custom command handling with arguments
//! - Tab completion for commands
//! - Persistent command history
//! - Multi-line input support
//! - Vi and Emacs keybinding modes
//! - Colored output and styling
//! - Configuration management
//!
//! Run with: zig build run
//! Or with Vi mode: zig build run -- --vi

const std = @import("std");
const repl = @import("repl");

// =============================================================================
// Application State
// =============================================================================

/// Application context passed to command handlers.
/// This demonstrates how to maintain state across REPL commands.
const AppContext = struct {
    /// Simple counter for demonstration
    counter: usize = 0,
    /// Toggle for verbose output
    verbose: bool = false,
    /// Current keymap mode
    keymap: repl.Keymap = .emacs,
    /// Allocator for dynamic allocations
    allocator: std.mem.Allocator,
    /// Available commands for tab completion
    commands: []const []const u8,
};

/// List of available commands (used for tab completion)
const COMMANDS = [_][]const u8{
    "help",
    "quit",
    "exit",
    "echo",
    "count",
    "reset",
    "history",
    "history-clear",
    "history-search",
    "clear",
    "verbose",
    "colors",
    "multiline",
    "eval",
    "env",
    "keymap",
    "version",
};

// =============================================================================
// Entry Point
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments for keymap selection
    var keymap: repl.Keymap = .emacs;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--vi") or std.mem.eql(u8, arg, "-v")) {
            keymap = .vi;
        }
    }

    // Initialize application context
    var ctx = AppContext{
        .allocator = allocator,
        .keymap = keymap,
        .commands = &COMMANDS,
    };

    // Run the REPL
    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "demo> ",
        .continuation_prompt = "  ... ",
        .keymap = keymap,
        .history_enabled = true,
        .app_name = "repl-demo",
        .run_fn = handleCommand,
        .is_complete_fn = isStatementComplete,
        .complete_fn = completeCommand,
        .welcome_fn = printWelcome,
        .user_context = @ptrCast(&ctx),
        .verbose = false,
    });
}

// =============================================================================
// Welcome Message
// =============================================================================

/// Print the welcome banner when the REPL starts.
/// This runs BEFORE raw mode is enabled, so regular newlines work.
fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.write("\n");
    try out.writeStyled(.bold, .cyan, "╔══════════════════════════════════════════╗\n");
    try out.writeStyled(.bold, .cyan, "║     Zig REPL Library - Demo Application  ║\n");
    try out.writeStyled(.bold, .cyan, "╚══════════════════════════════════════════╝\n");
    try out.write("\n");

    try out.write("A feature-rich, cross-platform REPL library for Zig.\n\n");

    try out.writeBold("Quick Start:\n");
    try out.write("  • Type ");
    try out.writeColored(.green, "help");
    try out.write(" for available commands\n");
    try out.write("  • Type ");
    try out.writeColored(.green, "quit");
    try out.write(" or press ");
    try out.writeColored(.yellow, "Ctrl+D");
    try out.write(" to exit\n");
    try out.write("  • Use ");
    try out.writeColored(.yellow, "Tab");
    try out.write(" for command completion\n");
    try out.write("  • Use ");
    try out.writeColored(.yellow, "Ctrl+R");
    try out.write(" to search history\n");
    try out.write("\n");

    try out.writeColored(.bright_black, "Library version: ");
    try out.write(repl.version);
    try out.write("\n\n");
}

// =============================================================================
// Input Completion Detection
// =============================================================================

/// Determine if the input constitutes a complete statement.
/// This enables multi-line input for incomplete statements.
fn isStatementComplete(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    // Empty input is complete
    if (trimmed.len == 0) return true;

    // Check for explicit multi-line mode (backslash continuation)
    if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\\') {
        return false;
    }

    // Check for balanced brackets/quotes
    if (!repl.isBalanced(input)) return false;

    // Check for operators suggesting continuation
    if (repl.needsContinuation(input)) return false;

    return true;
}

// =============================================================================
// Tab Completion
// =============================================================================

/// Tab completion function - provides command completion candidates.
fn completeCommand(prefix: []const u8, ctx: *repl.CompletionContext) void {
    // Complete command names that start with the prefix
    for (COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }
}

// =============================================================================
// Command Handler
// =============================================================================

/// Main command handler - processes user input and executes commands.
fn handleCommand(
    user_context: ?*anyopaque,
    allocator: std.mem.Allocator,
    input: []const u8,
    history: *repl.HistoryStore,
) anyerror!bool {
    const out = repl.terminalWriter();

    // Get application context
    const ctx: *AppContext = if (user_context) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        return true;

    // Trim and parse input
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) return true;

    // Parse command and arguments
    var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
    const command = parts.next() orelse return true;
    const args_rest = parts.rest();

    // Verbose logging
    if (ctx.verbose) {
        try out.writeColored(.bright_black, "[verbose] Command: ");
        try out.write(command);
        if (args_rest.len > 0) {
            try out.writeColored(.bright_black, ", Args: ");
            try out.write(args_rest);
        }
        try out.write("\n");
    }

    // =========================================================================
    // Command Dispatch
    // =========================================================================

    // Exit commands
    if (std.mem.eql(u8, command, "quit") or std.mem.eql(u8, command, "exit")) {
        try out.writeSuccess("Goodbye! Thanks for using the REPL library.");
        return false;
    }

    // Help command
    if (std.mem.eql(u8, command, "help")) {
        try showHelp(out, ctx);
        return true;
    }

    // Echo command - demonstrates argument handling
    if (std.mem.eql(u8, command, "echo")) {
        if (args_rest.len == 0) {
            try out.writeWarning("Usage: echo <text>");
        } else {
            try out.writeLine(args_rest);
        }
        return true;
    }

    // Counter commands - demonstrates state management
    if (std.mem.eql(u8, command, "count")) {
        ctx.counter += 1;
        try out.setColor(.green);
        try out.print("Counter: {d}\n", .{ctx.counter});
        try out.resetStyle();
        return true;
    }

    if (std.mem.eql(u8, command, "reset")) {
        ctx.counter = 0;
        try out.writeInfo("Counter reset to 0");
        return true;
    }

    // History commands
    if (std.mem.eql(u8, command, "history")) {
        try showHistory(out, history);
        return true;
    }

    if (std.mem.eql(u8, command, "history-clear")) {
        try history.clear();
        try out.writeSuccess("History cleared");
        return true;
    }

    if (std.mem.eql(u8, command, "history-search")) {
        if (args_rest.len == 0) {
            try out.writeWarning("Usage: history-search <pattern>");
        } else {
            try searchHistory(out, history, args_rest);
        }
        return true;
    }

    // Screen control
    if (std.mem.eql(u8, command, "clear")) {
        try out.clearScreen();
        return true;
    }

    // Verbose mode toggle
    if (std.mem.eql(u8, command, "verbose")) {
        ctx.verbose = !ctx.verbose;
        if (ctx.verbose) {
            try out.writeSuccess("Verbose mode enabled");
        } else {
            try out.writeInfo("Verbose mode disabled");
        }
        return true;
    }

    // Colors demo
    if (std.mem.eql(u8, command, "colors")) {
        try showColorDemo(out);
        return true;
    }

    // Multi-line demo
    if (std.mem.eql(u8, command, "multiline")) {
        try showMultilineDemo(out);
        return true;
    }

    // Eval command - demonstrates multi-line input
    if (std.mem.eql(u8, command, "eval")) {
        try out.writeBold("Input received:\n");
        try out.writeColored(.cyan, args_rest);
        try out.write("\n");

        // Show line count for multi-line input
        var line_count: usize = 1;
        for (args_rest) |c| {
            if (c == '\n') line_count += 1;
        }
        try out.print("({d} line(s), {d} bytes)\n", .{ line_count, args_rest.len });
        return true;
    }

    // Environment info
    if (std.mem.eql(u8, command, "env")) {
        try showEnvironmentInfo(out, allocator);
        return true;
    }

    // Keymap info
    if (std.mem.eql(u8, command, "keymap")) {
        try showKeymapHelp(out, ctx);
        return true;
    }

    // Version info
    if (std.mem.eql(u8, command, "version")) {
        try out.writeBold("REPL Library Version: ");
        try out.write(repl.version);
        try out.write("\n");
        return true;
    }

    // Unknown command
    try out.writeError(command);
    try out.writeInfo("Type 'help' for available commands.");
    return true;
}

// =============================================================================
// Command Implementations
// =============================================================================

fn showHelp(out: repl.TerminalWriter, ctx: *AppContext) !void {
    try out.writeBold("\n═══ Available Commands ═══\n\n");

    try out.writeColored(.cyan, "General:\n");
    try out.write("  help              Show this help message\n");
    try out.write("  quit, exit        Exit the REPL\n");
    try out.write("  clear             Clear the screen\n");
    try out.write("  version           Show library version\n");
    try out.write("\n");

    try out.writeColored(.cyan, "I/O Commands:\n");
    try out.write("  echo <text>       Echo text back to the terminal\n");
    try out.write("  eval <expr>       Evaluate/display multi-line input\n");
    try out.write("  verbose           Toggle verbose mode\n");
    try out.write("\n");

    try out.writeColored(.cyan, "State Commands:\n");
    try out.write("  count             Increment and display counter\n");
    try out.write("  reset             Reset counter to zero\n");
    try out.write("\n");

    try out.writeColored(.cyan, "History Commands:\n");
    try out.write("  history           Show command history\n");
    try out.write("  history-clear     Clear all history\n");
    try out.write("  history-search    Search history for pattern\n");
    try out.write("\n");

    try out.writeColored(.cyan, "Demo Commands:\n");
    try out.write("  colors            Show color palette demo\n");
    try out.write("  multiline         Show multi-line input demo\n");
    try out.write("  keymap            Show keybinding help\n");
    try out.write("  env               Show environment info\n");
    try out.write("\n");

    try out.writeBold("═══ Keybindings ═══\n\n");

    if (ctx.keymap == .vi) {
        try out.writeColored(.yellow, "Vi mode active\n");
        try out.write("  ESC         Enter normal mode\n");
        try out.write("  i/a/A/I     Enter insert mode\n");
        try out.write("  h/l         Move left/right\n");
        try out.write("  j/k         History prev/next\n");
        try out.write("  w/b         Word forward/back\n");
        try out.write("  x/X         Delete char\n");
        try out.write("  dd          Delete line\n");
    } else {
        try out.writeColored(.yellow, "Emacs mode active\n");
        try out.write("  Ctrl+A/E    Beginning/end of line\n");
        try out.write("  Ctrl+B/F    Back/forward one char\n");
        try out.write("  Ctrl+P/N    Previous/next history\n");
        try out.write("  Ctrl+K      Kill to end of line\n");
        try out.write("  Ctrl+U      Kill to beginning\n");
        try out.write("  Ctrl+W      Kill word backward\n");
        try out.write("  Ctrl+Y      Yank (paste)\n");
    }
    try out.write("\n");

    try out.writeColored(.yellow, "Common:\n");
    try out.write("  Tab         Tab completion\n");
    try out.write("  Ctrl+R      Reverse history search\n");
    try out.write("  Ctrl+L      Clear screen\n");
    try out.write("  Ctrl+C      Cancel input\n");
    try out.write("  Ctrl+D      Exit (empty line)\n");
    try out.write("\n");
}

fn showHistory(out: repl.TerminalWriter, history: *repl.HistoryStore) !void {
    const count = history.count();
    if (count == 0) {
        try out.writeInfo("No history entries yet.");
        return;
    }

    try out.writeBold("Command History:\n");
    const start = if (count > 20) count - 20 else 0;

    for (history.entries.items[start..], start..) |entry, i| {
        try out.setColor(.bright_black);
        try out.print("{d:>4}  ", .{i + 1});
        try out.resetStyle();
        try out.writeLine(entry);
    }

    if (start > 0) {
        try out.writeColored(.bright_black, "  ... (");
        try out.print("{d} earlier entries)\n", .{start});
    }
}

fn searchHistory(out: repl.TerminalWriter, history: *repl.HistoryStore, pattern: []const u8) !void {
    var found: usize = 0;
    var result_indices: [10]usize = undefined;
    var result_entries: [10][]const u8 = undefined;

    var start_idx: ?usize = null;
    while (found < 10) {
        if (history.searchBackward(pattern, start_idx)) |result| {
            result_indices[found] = result.index;
            result_entries[found] = result.entry;
            found += 1;
            start_idx = result.index;
        } else {
            break;
        }
    }

    if (found == 0) {
        try out.writeWarning("No matches found for: ");
        try out.writeLine(pattern);
        return;
    }

    try out.writeBold("Search results for '");
    try out.writeColored(.cyan, pattern);
    try out.write("':\n");

    var i: usize = 0;
    while (i < found) : (i += 1) {
        try out.setColor(.bright_black);
        try out.print("{d:>4}  ", .{result_indices[i] + 1});
        try out.resetStyle();
        try out.writeLine(result_entries[i]);
    }
}

fn showColorDemo(out: repl.TerminalWriter) !void {
    try out.writeBold("\n═══ Color Palette Demo ═══\n\n");

    // Standard colors
    try out.write("Standard colors:\n  ");
    const colors = [_]repl.Color{ .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white };
    const names = [_][]const u8{ "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" };

    for (colors, names) |color, name| {
        try out.setColor(color);
        try out.write(name);
        try out.resetStyle();
        try out.write(" ");
    }
    try out.write("\n\n");

    // Bright colors
    try out.write("Bright colors:\n  ");
    const bright_colors = [_]repl.Color{ .bright_black, .bright_red, .bright_green, .bright_yellow, .bright_blue, .bright_magenta, .bright_cyan, .bright_white };

    for (bright_colors, names) |color, name| {
        try out.setColor(color);
        try out.write(name);
        try out.resetStyle();
        try out.write(" ");
    }
    try out.write("\n\n");

    // Styles
    try out.write("Text styles:\n  ");
    try out.setStyle(.bold);
    try out.write("bold");
    try out.resetStyle();
    try out.write(" ");
    try out.setStyle(.dim);
    try out.write("dim");
    try out.resetStyle();
    try out.write(" ");
    try out.setStyle(.italic);
    try out.write("italic");
    try out.resetStyle();
    try out.write(" ");
    try out.setStyle(.underline);
    try out.write("underline");
    try out.resetStyle();
    try out.write("\n\n");

    // Message types
    try out.write("Message types:\n");
    try out.writeError("This is an error message");
    try out.writeWarning("This is a warning message");
    try out.writeSuccess("This is a success message");
    try out.writeInfo("This is an info message");
    try out.write("\n");
}

fn showMultilineDemo(out: repl.TerminalWriter) !void {
    try out.writeBold("\n═══ Multi-line Input Demo ═══\n\n");

    try out.write("The REPL supports multi-line input in several ways:\n\n");

    try out.writeColored(.cyan, "1. Backslash continuation:\n");
    try out.write("   End a line with \\ to continue on the next line.\n");
    try out.writeColored(.bright_black, "   Example: echo hello \\\n            world\n\n");

    try out.writeColored(.cyan, "2. Unbalanced brackets:\n");
    try out.write("   Input with unclosed (, [, or { will continue.\n");
    try out.writeColored(.bright_black, "   Example: echo (this is\n            multi-line)\n\n");

    try out.writeColored(.cyan, "3. Trailing operators:\n");
    try out.write("   Lines ending with +, -, =, etc. will continue.\n");
    try out.writeColored(.bright_black, "   Example: eval 1 +\n            2\n\n");

    try out.write("Try it: type 'eval hello \\' and press Enter.\n\n");
}

fn showEnvironmentInfo(out: repl.TerminalWriter, allocator: std.mem.Allocator) !void {
    try out.writeBold("\n═══ Environment Info ═══\n\n");

    // Terminal info
    try out.writeColored(.cyan, "Terminal:\n");
    try out.print("  Width:  {d} columns\n", .{repl.platform.getTerminalWidth()});
    try out.print("  Height: {d} rows\n", .{repl.platform.getTerminalHeight()});
    try out.print("  TTY:    {s}\n", .{if (repl.isStdinTty()) "yes" else "no"});
    try out.print("  Colors: {s}\n", .{if (repl.platform.shouldUseColor()) "enabled" else "disabled"});
    try out.write("\n");

    // History path
    try out.writeColored(.cyan, "History:\n");
    const hist_path = repl.history.getDefaultHistoryPath(allocator, "repl-demo") catch "unknown";
    defer if (!std.mem.eql(u8, hist_path, "unknown")) allocator.free(hist_path);
    try out.write("  Path: ");
    try out.writeLine(hist_path);
    try out.write("\n");

    // Library info
    try out.writeColored(.cyan, "Library:\n");
    try out.write("  Version: ");
    try out.write(repl.version);
    try out.write("\n");
    try out.write("  Features: history, completion, emacs/vi modes\n");
    try out.write("\n");
}

fn showKeymapHelp(out: repl.TerminalWriter, ctx: *AppContext) !void {
    try out.writeBold("\n═══ Keymap Information ═══\n\n");

    try out.write("Current mode: ");
    if (ctx.keymap == .vi) {
        try out.writeColored(.yellow, "Vi");
    } else {
        try out.writeColored(.yellow, "Emacs");
    }
    try out.write("\n\n");

    try out.write("To switch modes, restart with:\n");
    try out.writeColored(.bright_black, "  zig build run         ");
    try out.write("# Emacs mode (default)\n");
    try out.writeColored(.bright_black, "  zig build run -- --vi ");
    try out.write("# Vi mode\n\n");

    if (ctx.keymap == .vi) {
        try out.writeBold("Vi Normal Mode:\n");
        try out.write("  h/l       Move cursor left/right\n");
        try out.write("  j/k       History next/previous\n");
        try out.write("  w/b/e     Word forward/back/end\n");
        try out.write("  0/$       Beginning/end of line\n");
        try out.write("  x/X       Delete char at/before cursor\n");
        try out.write("  dw/db/dd  Delete word/word-back/line\n");
        try out.write("  cw/cc     Change word/line\n");
        try out.write("  i/a/A/I   Enter insert mode\n");
        try out.write("  u         Undo\n");
        try out.write("  /         Search\n\n");

        try out.writeBold("Vi Insert Mode:\n");
        try out.write("  ESC       Return to normal mode\n");
        try out.write("  Ctrl+C    Cancel and return to normal\n");
        try out.write("  (All Ctrl keys work as in Emacs mode)\n\n");
    } else {
        try out.writeBold("Movement:\n");
        try out.write("  Ctrl+A    Beginning of line (Home)\n");
        try out.write("  Ctrl+E    End of line (End)\n");
        try out.write("  Ctrl+B    Back one character (Left)\n");
        try out.write("  Ctrl+F    Forward one character (Right)\n");
        try out.write("  Alt+B     Back one word\n");
        try out.write("  Alt+F     Forward one word\n\n");

        try out.writeBold("Editing:\n");
        try out.write("  Ctrl+D    Delete character (or EOF if empty)\n");
        try out.write("  Ctrl+K    Kill to end of line\n");
        try out.write("  Ctrl+U    Kill to beginning of line\n");
        try out.write("  Ctrl+W    Kill word backward\n");
        try out.write("  Alt+D     Kill word forward\n");
        try out.write("  Ctrl+Y    Yank (paste) killed text\n\n");

        try out.writeBold("History:\n");
        try out.write("  Ctrl+P    Previous history (Up)\n");
        try out.write("  Ctrl+N    Next history (Down)\n");
        try out.write("  Ctrl+R    Reverse search history\n\n");
    }
}
