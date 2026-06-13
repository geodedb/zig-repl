// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! # Zig REPL Library
//!
//! A cross-platform, feature-rich REPL (Read-Eval-Print Loop) library for Zig.
//!
//! ## Features
//!
//! - **Raw terminal mode** with cleanup on normal exit, on SIGTERM/SIGHUP, and
//!   on suspend/resume (SIGTSTP/SIGCONT). In raw mode Ctrl-C and Ctrl-Z are
//!   delivered as bytes (ISIG is disabled), not signals; SIGKILL cannot be
//!   handled.
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
//!     var da: std.heap.DebugAllocator(.{}) = .init;
//!     defer da.deinit();
//!
//!     try repl.Repl.run(.{
//!         .allocator = da.allocator(),
//!         .prompt = ">>> ",
//!         .run_fn = runCommand,
//!     });
//! }
//!
//! fn runCommand(
//!     _: ?*anyopaque,
//!     _: std.mem.Allocator,
//!     input: []const u8,
//!     _: *repl.HistoryStore,
//! ) anyerror!bool {
//!     if (std.mem.eql(u8, input, "quit")) return false;
//!     const out = repl.terminalWriter();
//!     try out.print("{s}\n", .{input});
//!     return true;
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
//! - `KeyAction` - Internal action enum for key dispatch (user callbacks return `bool`, not `KeyAction`)
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

/// Shared text utility functions for word boundary detection and sanitization.
pub const text_utils = @import("text_utils.zig");

/// Terminal input parsing (key event decoding).
pub const input = @import("input.zig");

/// Rendering calculation utilities.
pub const render = @import("render.zig");

/// OpenTelemetry seam. Surfaces the no-op-when-disabled instrumentation
/// helpers (`startEvalSpan`, `endEvalSpan`, etc.). When
/// `-Dwith_otel=false` (the default) every helper compiles to a
/// comptime-known no-op and the otel dependency is never resolved.
pub const observability = @import("observability");

/// OpenTelemetry bootstrap helper. Only available when `-Dwith_otel=true`;
/// in the disabled build this resolves to an empty struct so consumers
/// can still reference the namespace at compile time without pulling in
/// any otel symbols.
pub const observability_init = if (observability.enabled)
    @import("observability_init")
else
    struct {};

// =============================================================================
// Core Types
// =============================================================================

/// The main REPL runner. Call `Repl.run(config)` to start an interactive session.
pub const Repl = core.Repl;

/// Internal REPL state. Exposed for advanced use cases requiring direct access.
pub const ReplState = core.ReplState;

/// Parsed keyboard event (character, control key, arrow, etc.).
pub const KeyEvent = core.KeyEvent;

/// Named constants for synthetic key codes produced by escape sequences.
/// Use these instead of raw hex values when matching Insert, Delete, Page Up, or Page Down.
pub const SyntheticKey = core.SyntheticKey;

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

/// Check if stderr is connected to a TTY (interactive terminal).
pub const isStderrTty = platform.isStderrTty;

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

/// Version information.
///
/// Single source of truth: the string is threaded in from build.zig, which
/// parses `.version` out of build.zig.zon at configure time (see
/// `parseZonVersion` in build.zig). `version_major/minor/patch` are derived
/// from that same string at comptime so they can never drift from it. A
/// test below re-parses build.zig.zon and asserts the match, so any future
/// divergence between the manifest and this surface fails CI.
const build_options = @import("build_options");
pub const version = build_options.version;
pub const version_major = parseSemverField(version, 0);
pub const version_minor = parseSemverField(version, 1);
pub const version_patch = parseSemverField(version, 2);

/// Parse the Nth dot-separated numeric field of a semantic version string
/// at comptime. Stops the patch field at the first `-` or `+` so
/// pre-release / build-metadata suffixes (e.g. "1.2.3-beta.1") parse the
/// core number. Emits a comptime error on a malformed version.
fn parseSemverField(comptime ver: []const u8, comptime index: usize) u32 {
    comptime {
        var field: usize = 0;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= ver.len) : (i += 1) {
            const at_end = i == ver.len;
            const c = if (at_end) '.' else ver[i];
            // A '-' or '+' terminates the numeric portion of the patch
            // field (semver pre-release / build metadata).
            const sep = c == '.' or c == '-' or c == '+';
            if (sep or at_end) {
                if (field == index) {
                    const token = ver[start..i];
                    return std.fmt.parseInt(u32, token, 10) catch
                        @compileError("repl.version: malformed semver field in '" ++ ver ++ "'");
                }
                field += 1;
                start = i + 1;
                if (c == '-' or c == '+') break;
            }
        }
        @compileError("repl.version: missing semver field in '" ++ ver ++ "'");
    }
}

test "repl.version matches build.zig.zon .version" {
    // Re-parse the packaging manifest at test time and assert the exported
    // version matches. This makes manifest/version drift a CI failure.
    // `zig build test` runs with cwd at the build root, so build.zig.zon is
    // reachable relative to cwd. If the manifest cannot be located (e.g. a
    // packaged consumer running this test out of tree) skip rather than
    // misreport — the build-time parse already pins the value.
    const cio = @import("compat.zig").defaultIo();
    const zon = std.Io.Dir.cwd().readFileAlloc(
        cio,
        "build.zig.zon",
        std.testing.allocator,
        @enumFromInt(64 * 1024),
    ) catch return error.SkipZigTest;
    defer std.testing.allocator.free(zon);

    const marker = ".version";
    const marker_idx = std.mem.indexOf(u8, zon, marker) orelse return error.SkipZigTest;
    const after = zon[marker_idx + marker.len ..];
    const open = std.mem.indexOfScalar(u8, after, '"') orelse return error.SkipZigTest;
    const rest = after[open + 1 ..];
    const close = std.mem.indexOfScalar(u8, rest, '"') orelse return error.SkipZigTest;
    const zon_version = rest[0..close];
    try std.testing.expectEqualStrings(zon_version, version);
}

test "repl.version_major/minor/patch decompose version" {
    const expected = std.fmt.comptimePrint("{d}.{d}.{d}", .{
        version_major,
        version_minor,
        version_patch,
    });
    // The dotted major.minor.patch must be a prefix of `version` (allows a
    // pre-release/build suffix while still pinning the numeric core).
    try std.testing.expect(std.mem.startsWith(u8, version, expected));
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
