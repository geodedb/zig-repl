// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Vi Mode Example
//!
//! This example demonstrates:
//! - Vi-style keybindings
//! - Normal mode vs Insert mode
//! - Common Vi commands (h/l, w/b, x, dd, etc.)
//!
//! Run with: zig build run-vi

const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "vi> ",
        .app_name = "vi-example",
        .keymap = .vi, // Enable Vi keybindings
        .run_fn = handleCommand,
        .welcome_fn = printWelcome,
    });
}

fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Vi Mode Example\n\n");
    try out.write("This REPL uses Vi-style keybindings.\n");
    try out.write("You start in INSERT mode. Press ESC for NORMAL mode.\n\n");

    try out.writeColored(.cyan, "Normal Mode Commands:\n");
    try out.write("  h/l       - Move cursor left/right\n");
    try out.write("  0/$       - Move to beginning/end of line\n");
    try out.write("  w/b       - Move word forward/backward\n");
    try out.write("  i/a       - Enter insert mode before/after cursor\n");
    try out.write("  I/A       - Insert at beginning/end of line\n");
    try out.write("  x         - Delete character at cursor\n");
    try out.write("  X         - Delete character before cursor\n");
    try out.write("  dd        - Delete entire line\n");
    try out.write("  dw        - Delete word forward\n");
    try out.write("  db        - Delete word backward\n");
    try out.write("  cw        - Change word (delete and enter insert)\n");
    try out.write("  cc        - Change line\n");
    try out.write("  j/k       - History next/previous\n");
    try out.write("  /         - Search history\n");
    try out.write("  u         - Undo\n\n");

    try out.writeColored(.cyan, "Insert Mode:\n");
    try out.write("  ESC       - Return to normal mode\n");
    try out.write("  Ctrl+C    - Cancel and return to normal mode\n");
    try out.write("  (All Ctrl shortcuts work as in Emacs mode)\n\n");

    try out.write("Commands: mode, help, demo, quit\n\n");
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

    if (std.mem.eql(u8, trimmed, "mode")) {
        try showModeInfo(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "demo")) {
        try showDemo(out);
        return true;
    }

    // Echo back the input
    try out.write("You typed: ");
    try out.writeColored(.cyan, input);
    try out.write("\n");

    return true;
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nVi Mode Quick Reference\n\n");

    try out.writeColored(.yellow, "Movement Commands (Normal Mode)\n");
    try out.write("  h         Move cursor left\n");
    try out.write("  l         Move cursor right\n");
    try out.write("  0         Move to beginning of line\n");
    try out.write("  $         Move to end of line\n");
    try out.write("  w         Move forward one word\n");
    try out.write("  b         Move backward one word\n");
    try out.write("  e         Move to end of word\n\n");

    try out.writeColored(.yellow, "Insert Commands\n");
    try out.write("  i         Insert before cursor\n");
    try out.write("  a         Insert after cursor (append)\n");
    try out.write("  I         Insert at beginning of line\n");
    try out.write("  A         Insert at end of line\n");
    try out.write("  ESC       Exit insert mode\n\n");

    try out.writeColored(.yellow, "Delete Commands (Normal Mode)\n");
    try out.write("  x         Delete character under cursor\n");
    try out.write("  X         Delete character before cursor\n");
    try out.write("  dw        Delete word forward\n");
    try out.write("  db        Delete word backward\n");
    try out.write("  dd        Delete entire line\n");
    try out.write("  D         Delete to end of line\n\n");

    try out.writeColored(.yellow, "Change Commands\n");
    try out.write("  cw        Change word (delete and insert)\n");
    try out.write("  cc        Change entire line\n");
    try out.write("  C         Change to end of line\n\n");

    try out.writeColored(.yellow, "History (Normal Mode)\n");
    try out.write("  j         Next history entry\n");
    try out.write("  k         Previous history entry\n");
    try out.write("  /pattern  Search history backward\n\n");

    try out.writeColored(.yellow, "Other\n");
    try out.write("  u         Undo last change\n");
    try out.write("  Ctrl+L    Clear screen\n\n");
}

fn showModeInfo(out: repl.TerminalWriter) !void {
    try out.writeBold("\nVi Mode Concepts\n\n");

    try out.writeColored(.green, "INSERT Mode\n");
    try out.write("  This is the default mode when you start typing.\n");
    try out.write("  Characters you type are inserted into the buffer.\n");
    try out.write("  Press ESC to switch to Normal mode.\n\n");

    try out.writeColored(.yellow, "NORMAL Mode\n");
    try out.write("  This is command mode - keys perform actions.\n");
    try out.write("  Navigation: h (left), l (right), w (word forward), b (word back)\n");
    try out.write("  Deletion: x (char), dw (word), dd (line)\n");
    try out.write("  Press i or a to return to Insert mode.\n\n");

    try out.writeColored(.cyan, "Mode Indicator\n");
    try out.write("  A real Vi implementation would show [INSERT] or [NORMAL]\n");
    try out.write("  in the prompt or status line. This example starts in INSERT.\n\n");

    try out.write("Tip: Press ESC ESC if you're not sure which mode you're in.\n");
    try out.write("     (The second ESC in insert mode just stays in normal.)\n\n");
}

fn showDemo(out: repl.TerminalWriter) !void {
    try out.writeBold("\nVi Mode Demo Exercises\n\n");

    try out.write("Try these exercises to practice Vi keybindings:\n\n");

    try out.writeColored(.cyan, "Exercise 1: Basic Navigation\n");
    try out.write("  1. Type: hello world\n");
    try out.write("  2. Press ESC (enter normal mode)\n");
    try out.write("  3. Press 0 (go to start of line)\n");
    try out.write("  4. Press w twice (move word by word)\n");
    try out.write("  5. Press i to insert, type 'big ', press ESC\n");
    try out.write("  6. Press Enter to see: hello big world\n\n");

    try out.writeColored(.cyan, "Exercise 2: Deletion\n");
    try out.write("  1. Type: The quick brown fox\n");
    try out.write("  2. Press ESC, then 0 (start of line)\n");
    try out.write("  3. Press w (move to 'quick')\n");
    try out.write("  4. Press dw (delete 'quick ')\n");
    try out.write("  5. Press Enter to see: The brown fox\n\n");

    try out.writeColored(.cyan, "Exercise 3: Change Command\n");
    try out.write("  1. Type: Hello world\n");
    try out.write("  2. Press ESC, then 0, then w (move to 'world')\n");
    try out.write("  3. Press cw (change word - deletes and enters insert)\n");
    try out.write("  4. Type: universe, press ESC\n");
    try out.write("  5. Press Enter to see: Hello universe\n\n");

    try out.writeColored(.cyan, "Exercise 4: History Navigation\n");
    try out.write("  1. Type and run several commands\n");
    try out.write("  2. On empty prompt, press ESC then k\n");
    try out.write("  3. Keep pressing k to go further back\n");
    try out.write("  4. Press j to go forward in history\n\n");
}
