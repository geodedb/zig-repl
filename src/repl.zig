// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Zig REPL Library
//!
//! A cross-platform, feature-rich REPL (Read-Eval-Print Loop) library for Zig.
//!
//! ## Features
//!
//! - **Raw terminal mode** with proper cleanup on exit/signals
//! - **Emacs and Vi keybindings** - switch modes at runtime
//! - **Persistent command history** - saved to disk, searchable
//! - **Tab completion** - extensible completion system
//! - **Multi-line input** - automatic detection of incomplete statements
//! - **Bracketed paste mode** - properly handles pasted text
//! - **Colored output** - 16-color support with semantic helpers
//! - **Cross-platform** - Linux, macOS, Windows
//!
//! ## Basic Usage
//!
//! ```zig
//! const std = @import("std");
//! const repl = @import("repl");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!
//!     try repl.Repl.run(.{
//!         .allocator = gpa.allocator(),
//!         .prompt = ">>> ",
//!         .execute_fn = executeCommand,
//!     });
//! }
//!
//! fn executeCommand(
//!     input: []const u8,
//!     out: repl.TerminalWriter,
//!     _: *repl.HistoryStore,
//!     _: *anyopaque,
//! ) !repl.KeyAction {
//!     if (std.mem.eql(u8, input, "quit")) return .quit;
//!     try out.writeLine(input);
//!     return .none;
//! }
//! ```
//!
//! ## Terminal Output
//!
//! Use `TerminalWriter` for proper output in raw terminal mode. It automatically
//! handles newline conversion (`\n` -> `\r\n`) and provides colored output:
//!
//! ```zig
//! // Basic output
//! try out.write("Hello\n");
//! try out.writeLine("World");
//! try out.print("Value: {d}\n", .{42});
//!
//! // Colored output
//! try out.writeColored(.green, "Success!");
//! try out.writeError("Something failed");
//! try out.writeWarning("Be careful");
//!
//! // Screen control
//! try out.clearScreen();
//! ```
//!
//! ## Tab Completion
//!
//! Provide a completion function to enable tab completion:
//!
//! ```zig
//! fn complete(prefix: []const u8, ctx: *repl.CompletionContext) void {
//!     const commands = [_][]const u8{ "help", "quit", "history" };
//!     for (commands) |cmd| {
//!         if (std.mem.startsWith(u8, cmd, prefix)) {
//!             ctx.addCandidate(cmd) catch {};
//!         }
//!     }
//! }
//! ```
//!
//! ## Multi-line Input
//!
//! Use the parsing utilities or provide a custom `is_complete_fn`:
//!
//! ```zig
//! fn isComplete(input: []const u8) bool {
//!     return repl.isBalanced(input);
//! }
//! ```
//!
//! ## Key Types
//!
//! - `Repl` - Main REPL runner with `run()` method
//! - `TerminalWriter` - Terminal output with color and raw mode support
//! - `HistoryStore` - Command history with search
//! - `CompletionContext` - Tab completion results
//! - `KeyAction` - Execute function return values (`.none`, `.quit`, `.continue_input`)
//! - `Color` - Terminal colors (16 colors)
//! - `Style` - Text styles (bold, dim, italic, underline)

const std = @import("std");

// =============================================================================
// Core Modules
// =============================================================================

/// Core REPL implementation with input handling and rendering.
pub const core = @import("core.zig");

/// Platform-specific terminal handling (POSIX and Windows).
pub const platform = @import("platform.zig");

/// Command history storage, search, and persistence.
pub const history = @import("history.zig");

/// Tab completion system.
pub const completion = @import("completion.zig");

/// Input parsing utilities for multi-line detection.
pub const parse = @import("parse.zig");

/// Configuration types and defaults.
pub const config = @import("config.zig");

/// Emacs-style keybinding handlers.
pub const keymap_emacs = @import("keymap_emacs.zig");

/// Vi-style keybinding handlers.
pub const keymap_vi = @import("keymap_vi.zig");

// =============================================================================
// Core Types
// =============================================================================

/// The main REPL runner. Call `Repl.run(config)` to start an interactive session.
pub const Repl = core.Repl;

/// Internal REPL state. Exposed for advanced use cases requiring direct access.
pub const ReplState = core.ReplState;

/// Parsed keyboard event (character, control key, arrow, etc.).
pub const KeyEvent = core.KeyEvent;

/// Return value from execute function to control REPL behavior.
/// - `.none` - Continue normally
/// - `.quit` - Exit the REPL
/// - `.continue_input` - Continue multi-line input
pub const KeyAction = core.KeyAction;

/// Keymap selection for keybindings.
/// - `.emacs` - Emacs-style bindings (default)
/// - `.vi` - Vi-style bindings with normal/insert modes
pub const Keymap = core.Keymap;

/// Tab completion callback function type.
/// Given a prefix, adds completion candidates to the context.
pub const CompleteFn = core.CompleteFn;

/// Terminal formatting utilities for cursor movement and colors.
pub const Format = core.Format;

/// Persistent command history with search capabilities.
pub const HistoryStore = history.HistoryStore;

/// Context passed to completion functions for adding results.
pub const CompletionContext = completion.CompletionContext;

/// REPL configuration options.
pub const Config = config.Config;

// =============================================================================
// Platform Utilities
// =============================================================================

/// Get a handle to stdin for direct I/O operations.
pub const getStdinHandle = platform.getStdinHandle;

/// Get a handle to stdout for direct I/O operations.
pub const getStdoutHandle = platform.getStdoutHandle;

/// Get a handle to stderr for direct I/O operations.
pub const getStderrHandle = platform.getStderrHandle;

/// Check if stdin is connected to a TTY (interactive terminal).
pub const isStdinTty = platform.isStdinTty;

/// Check if stdout is connected to a TTY (interactive terminal).
pub const isStdoutTty = platform.isStdoutTty;

// =============================================================================
// Terminal Output
// =============================================================================

/// Terminal output writer that handles raw mode requirements.
/// Automatically converts `\n` to `\r\n` for proper line breaks in raw mode.
/// Provides colored output, styling, and screen control methods.
pub const TerminalWriter = platform.TerminalWriter;

/// Create a TerminalWriter for the given file handle.
pub const terminalWriter = platform.terminalWriter;

/// Terminal colors (16-color palette).
/// Standard colors: black, red, green, yellow, blue, magenta, cyan, white.
/// Bright variants: bright_black, bright_red, etc.
pub const Color = platform.Color;

/// Text styles for terminal output.
/// Includes: reset, bold, dim, italic, underline.
pub const Style = platform.Style;

// =============================================================================
// Input Parsing
// =============================================================================

/// Check if input constitutes a complete statement.
/// Returns false if brackets are unbalanced or line ends with a continuation operator.
pub const isComplete = parse.isComplete;

/// Check if brackets, braces, and parentheses are balanced.
/// Useful for detecting incomplete multi-line expressions.
pub const isBalanced = parse.isBalanced;

/// Check if input ends with a continuation operator (e.g., backslash, trailing operator).
pub const needsContinuation = parse.needsContinuation;

/// Version information
pub const version = "0.1.0";
pub const version_major = 0;
pub const version_minor = 1;
pub const version_patch = 0;

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
