// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Cross-platform terminal I/O utilities
//!
//! Provides platform-agnostic access to standard I/O handles and TTY detection.

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");

// =============================================================================
// Signal-based terminal cleanup (POSIX only)
// =============================================================================
//
// When raw terminal mode is active (ISIG disabled), external signals such as
// SIGTERM and SIGHUP would leave the terminal in raw mode because the normal
// `defer restoreTerminalMode(...)` in core.zig cannot run during
// signal-based termination.  We register one-shot signal handlers that
// restore the original termios before re-raising the signal so the process
// terminates with the correct exit status.

/// Saved original terminal state for signal-handler restoration.
/// Written by `enterRawMode`, cleared by `restoreTerminalMode`.
/// Only used on POSIX targets; on Windows this is a no-op void.
var saved_termios: if (builtin.os.tag == .windows) void else ?std.posix.termios =
    if (builtin.os.tag == .windows) {} else null;

/// Cached terminal width (PF-021). Invalidated by SIGWINCH handler (PF-040).
var cached_terminal_width: usize = 0;

/// Flag set by SIGWINCH handler to indicate terminal resize.
/// Async-signal-safe: single atomic store from signal handler.
var terminal_resized: bool = true; // true initially to force first fetch

/// Signal handler that restores the terminal to its original state and
/// then re-raises the received signal with the default disposition so
/// the process exits with the standard signal semantics (correct exit
/// code / core dump).
///
/// Async-signal-safety: only uses raw syscalls via `std.posix.system`
/// (which resolves to `std.os.linux` or `std.c` depending on the
/// target) and does not allocate or acquire locks.
fn handleTerminalSignal(sig: std.posix.SIG) callconv(.c) void {
    if (builtin.os.tag == .windows) return;

    const sys = std.posix.system;

    // Restore original terminal attributes via the raw syscall (async-signal-safe).
    if (saved_termios) |original| {
        _ = sys.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, &original);
    }

    // Also attempt to disable bracketed paste mode.
    // write() is async-signal-safe per POSIX.
    const disable_bracketed_paste = "\x1b[?2004l";
    _ = sys.write(std.posix.STDOUT_FILENO, disable_bracketed_paste, disable_bracketed_paste.len);

    // Reset this signal to SIG_DFL and re-raise so the process exits
    // with the correct signal disposition (e.g. exit code 128+sig).
    const default_sa = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &default_sa, null);
    _ = sys.kill(sys.getpid(), sig);
}

/// SIGWINCH handler that sets the resize flag for cached width invalidation.
/// Async-signal-safe: only sets a volatile boolean.
fn handleResizeSignal(_: std.posix.SIG) callconv(.c) void {
    terminal_resized = true;
}

/// Register signal handlers for terminal cleanup on the given signals.
/// Called from `enterRawMode` after saving the original terminal state.
fn installTerminalSignalHandlers() void {
    if (builtin.os.tag == .windows) return;

    const sa = std.posix.Sigaction{
        .handler = .{ .handler = handleTerminalSignal },
        .mask = std.posix.sigemptyset(),
        // SA_RESETHAND: one-shot handler to avoid re-entry.
        .flags = std.posix.SA.RESETHAND,
    };

    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
    std.posix.sigaction(std.posix.SIG.HUP, &sa, null);

    // SIGWINCH handler for terminal resize detection (PF-040).
    // Not one-shot — must persist to detect repeated resizes.
    const winch_sa = std.posix.Sigaction{
        .handler = .{ .handler = handleResizeSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &winch_sa, null);
}

/// Remove the terminal signal handlers (restore default behavior).
/// Called from `restoreTerminalMode` when we no longer need cleanup.
fn removeTerminalSignalHandlers() void {
    if (builtin.os.tag == .windows) return;

    const default_sa = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.TERM, &default_sa, null);
    std.posix.sigaction(std.posix.SIG.HUP, &default_sa, null);
    std.posix.sigaction(std.posix.SIG.WINCH, &default_sa, null);
}

/// Get a handle to standard input.
/// Works on both POSIX systems and Windows.
pub fn getStdinHandle() std.Io.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch unreachable;
        return std.Io.File{ .handle = handle, .flags = .{ .nonblocking = false } };
    } else {
        return std.Io.File.stdin();
    }
}

/// Get a handle to standard output.
/// Works on both POSIX systems and Windows.
pub fn getStdoutHandle() std.Io.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch unreachable;
        return std.Io.File{ .handle = handle, .flags = .{ .nonblocking = false } };
    } else {
        return std.Io.File.stdout();
    }
}

/// Get a handle to standard error.
/// Works on both POSIX systems and Windows.
pub fn getStderrHandle() std.Io.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch unreachable;
        return std.Io.File{ .handle = handle, .flags = .{ .nonblocking = false } };
    } else {
        return std.Io.File.stderr();
    }
}

/// Check if standard input is a TTY (interactive terminal).
pub fn isStdinTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return compat.isatty(std.posix.STDIN_FILENO);
    }
}

/// Check if standard output is a TTY (interactive terminal).
pub fn isStdoutTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return compat.isatty(std.posix.STDOUT_FILENO);
    }
}

/// Check if standard error is a TTY (interactive terminal).
pub fn isStderrTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return compat.isatty(std.posix.STDERR_FILENO);
    }
}

/// Terminal state for raw mode management.
/// Platform-specific: termios on POSIX, DWORD on Windows.
pub const TerminalState = if (builtin.os.tag == .windows) std.os.windows.DWORD else std.posix.termios;

/// Enter raw terminal mode for character-by-character input.
/// Returns the original terminal state for later restoration.
pub fn enterRawMode() !TerminalState {
    if (builtin.os.tag == .windows) {
        const ENABLE_LINE_INPUT: std.os.windows.DWORD = 0x0002;
        const ENABLE_ECHO_INPUT: std.os.windows.DWORD = 0x0004;
        const ENABLE_PROCESSED_INPUT: std.os.windows.DWORD = 0x0001;
        const ENABLE_VIRTUAL_TERMINAL_INPUT: std.os.windows.DWORD = 0x0200;

        const stdin_handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch unreachable;
        var mode: std.os.windows.DWORD = undefined;
        _ = std.os.windows.kernel32.GetConsoleMode(stdin_handle, &mode);
        const original = mode;

        // Disable line input, echo, and processed input (Ctrl+C as input)
        mode &= ~ENABLE_LINE_INPUT;
        mode &= ~ENABLE_ECHO_INPUT;
        mode &= ~ENABLE_PROCESSED_INPUT;
        // Enable VT input so ANSI escape sequences are passed through
        mode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
        _ = std.os.windows.kernel32.SetConsoleMode(stdin_handle, mode);

        // Enable VT processing on stdout so ANSI escape output works
        // in Windows Terminal and cmd.exe (Windows 10 1511+).
        const stdout_handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return original;
        var out_mode: std.os.windows.DWORD = undefined;
        if (std.os.windows.kernel32.GetConsoleMode(stdout_handle, &out_mode) != 0) {
            out_mode |= std.os.windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            _ = std.os.windows.kernel32.SetConsoleMode(stdout_handle, out_mode);
        }

        return original;
    }

    const stdin = getStdinHandle();
    const original = try std.posix.tcgetattr(stdin.handle);

    var raw = original;
    raw.iflag.ICRNL = false; // Don't translate CR to NL
    raw.iflag.IXON = false; // Disable XON/XOFF flow control
    raw.oflag.OPOST = false; // Disable output processing
    raw.lflag.ECHO = false; // Disable echo
    raw.lflag.ICANON = false; // Disable canonical mode
    raw.lflag.ISIG = false; // Disable signal generation
    raw.lflag.IEXTEN = false; // Disable extended input processing
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1; // Minimum bytes to read
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 0.1 second timeout for escape sequences

    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);
    // ADV-002 (#147): if anything after this point fails, restore cooked mode
    // before propagating -- the caller's `defer restoreTerminalMode` is not
    // registered until enterRawMode returns, so without this errdefer a
    // failed bracketed-paste enable would leave the terminal stuck in raw mode.
    errdefer std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};

    // Save original state for signal handler restoration and install handlers.
    saved_termios = original;
    installTerminalSignalHandlers();
    errdefer {
        removeTerminalSignalHandlers();
        saved_termios = null;
    }

    // Enable bracketed paste mode
    const stdout = getStdoutHandle();
    try compat.writeAll(stdout, "\x1b[?2004h");

    return original;
}

/// Restore terminal to its original state.
pub fn restoreTerminalMode(original: TerminalState) !void {
    // Disable bracketed paste mode
    const stdout = getStdoutHandle();
    compat.writeAll(stdout, "\x1b[?2004l") catch {};

    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return;
        _ = std.os.windows.kernel32.SetConsoleMode(handle, original);
        return;
    }

    const stdin = getStdinHandle();
    try std.posix.tcsetattr(stdin.handle, .FLUSH, original);

    // Remove signal handlers and clear saved state now that terminal is restored.
    removeTerminalSignalHandlers();
    saved_termios = null;
}

/// Get terminal width in columns (cached, invalidated by SIGWINCH).
/// Returns 80 as default if unavailable.
pub fn getTerminalWidth() usize {
    // On POSIX, return cached value unless SIGWINCH set the resize flag.
    if (builtin.os.tag != .windows and !terminal_resized and cached_terminal_width > 0) {
        return cached_terminal_width;
    }

    const width = getTerminalWidthUncached();

    if (builtin.os.tag != .windows) {
        cached_terminal_width = width;
        terminal_resized = false;
    }

    return width;
}

/// Perform the actual ioctl/syscall to fetch terminal width.
fn getTerminalWidthUncached() usize {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return 80;
        var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi) != 0) {
            const width = csbi.srWindow.Right - csbi.srWindow.Left + 1;
            if (width > 0) return @intCast(width);
        }
        return 80;
    } else {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0 and ws.col > 0) {
            return @as(usize, ws.col);
        }
        return 80;
    }
}

/// Get terminal height in rows.
/// Returns 24 as default if unavailable.
pub fn getTerminalHeight() usize {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return 24;
        var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi) != 0) {
            const height = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
            if (height > 0) return @intCast(height);
        }
        return 24;
    } else {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0 and ws.row > 0) {
            return @as(usize, ws.row);
        }
        return 24;
    }
}

/// Windows console input record and PeekConsoleInput binding.
/// These are not provided by Zig's stdlib so we declare them here.
const win32_console = if (builtin.os.tag == .windows) struct {
    const HANDLE = std.os.windows.HANDLE;
    const DWORD = std.os.windows.DWORD;
    const BOOL = std.os.windows.BOOL;
    const WORD = std.os.windows.WORD;
    const WCHAR = std.os.windows.WCHAR;

    const KEY_EVENT: WORD = 0x0001;

    const KEY_EVENT_RECORD = extern struct {
        bKeyDown: BOOL,
        wRepeatCount: WORD,
        wVirtualKeyCode: WORD,
        wVirtualScanCode: WORD,
        uChar: extern union { UnicodeChar: WCHAR, AsciiChar: u8 },
        dwControlKeyState: DWORD,
    };

    const INPUT_RECORD = extern struct {
        EventType: WORD,
        _padding: WORD = 0,
        Event: extern union { KeyEvent: KEY_EVENT_RECORD, _reserved: [16]u8 },
    };

    extern "kernel32" fn PeekConsoleInputW(
        hConsoleInput: HANDLE,
        lpBuffer: [*]INPUT_RECORD,
        nLength: DWORD,
        lpNumberOfEventsRead: *DWORD,
    ) callconv(.winapi) BOOL;
} else struct {};

/// Check if stdin has more data available (non-blocking).
pub fn stdinHasMoreData() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return false;
        var records: [8]win32_console.INPUT_RECORD = undefined;
        var count: std.os.windows.DWORD = 0;
        if (win32_console.PeekConsoleInputW(handle, &records, records.len, &count) == 0) {
            return false;
        }
        // Check if any of the peeked records are key-down events.
        for (records[0..count]) |rec| {
            if (rec.EventType == win32_console.KEY_EVENT and rec.Event.KeyEvent.bKeyDown != 0) {
                return true;
            }
        }
        return false;
    } else {
        // POSIX: use poll with 0 timeout to check if data is available
        var fds = [_]std.posix.pollfd{
            .{ .fd = std.posix.STDIN_FILENO, .events = std.posix.POLL.IN, .revents = 0 },
        };
        const result = std.posix.poll(&fds, 0) catch return false;
        return result > 0 and (fds[0].revents & std.posix.POLL.IN) != 0;
    }
}

/// Check if colors should be used based on environment and TTY status.
pub fn shouldUseColor() bool {
    if (builtin.os.tag == .windows) {
        // On Windows, check NO_COLOR via the wide-string environment API.
        // TERM is not meaningful on Windows so we skip that check.
        if (std.process.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("NO_COLOR"))) |_| {
            return false;
        }
        return isStdoutTty();
    } else {
        // POSIX: use the standard getenv for NO_COLOR and TERM.
        if (compat.getenvSlice("NO_COLOR")) |_| {
            return false;
        }
        if (compat.getenvSlice("TERM")) |term| {
            if (std.mem.eql(u8, term, "dumb")) {
                return false;
            }
        }
        return isStdoutTty();
    }
}

/// ANSI color codes for terminal output.
pub const Color = enum {
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    fn code(self: Color) []const u8 {
        return switch (self) {
            .default => "39",
            .black => "30",
            .red => "31",
            .green => "32",
            .yellow => "33",
            .blue => "34",
            .magenta => "35",
            .cyan => "36",
            .white => "37",
            .bright_black => "90",
            .bright_red => "91",
            .bright_green => "92",
            .bright_yellow => "93",
            .bright_blue => "94",
            .bright_magenta => "95",
            .bright_cyan => "96",
            .bright_white => "97",
        };
    }
};

/// Text style modifiers.
pub const Style = enum {
    reset,
    bold,
    dim,
    italic,
    underline,

    fn code(self: Style) []const u8 {
        return switch (self) {
            .reset => "0",
            .bold => "1",
            .dim => "2",
            .italic => "3",
            .underline => "4",
        };
    }
};

/// Writer that converts \n to \r\n for raw terminal mode.
/// Use this for all output when the terminal is in raw mode.
pub const TerminalWriter = struct {
    file: std.Io.File,
    use_color: bool,

    const Self = @This();

    /// Create a new terminal writer wrapping the given file handle.
    pub fn init(file: std.Io.File) Self {
        return .{ .file = file, .use_color = shouldUseColor() };
    }

    /// Create a terminal writer for stdout.
    pub fn stdout() Self {
        return init(getStdoutHandle());
    }

    /// Create a terminal writer for stderr.
    pub fn stderr() Self {
        return init(getStderrHandle());
    }

    /// Size of the stack buffer used for newline conversion in `write`.
    const WRITE_BUF_SIZE = 8192;

    /// Write a string, converting \n to \r\n for raw terminal mode.
    /// Buffers the converted output and flushes in as few writeAll calls
    /// as possible (typically one) instead of issuing a separate syscall
    /// per text segment and newline.
    pub fn write(self: Self, data: []const u8) !void {
        var buf: [WRITE_BUF_SIZE]u8 = undefined;
        var pos: usize = 0;
        for (data) |c| {
            if (c == '\n') {
                if (pos + 2 > buf.len) {
                    try compat.writeAll(self.file, buf[0..pos]);
                    pos = 0;
                }
                buf[pos] = '\r';
                buf[pos + 1] = '\n';
                pos += 2;
            } else {
                if (pos + 1 > buf.len) {
                    try compat.writeAll(self.file, buf[0..pos]);
                    pos = 0;
                }
                buf[pos] = c;
                pos += 1;
            }
        }
        if (pos > 0) try compat.writeAll(self.file, buf[0..pos]);
    }

    /// Write a string followed by a newline (converted to \r\n).
    pub fn writeLine(self: Self, data: []const u8) !void {
        try self.write(data);
        try compat.writeAll(self.file, "\r\n");
    }

    /// Size of the stack buffer used by `print`. Extracted as a named constant
    /// so callers can reason about the truncation threshold.
    const PRINT_BUF_SIZE = 4096;

    /// Print formatted output, converting \n to \r\n.
    /// If the formatted output exceeds `PRINT_BUF_SIZE`, writes the partial
    /// content that fits rather than silently dropping all output.
    pub fn print(self: Self, comptime fmt: []const u8, args: anytype) !void {
        var buf: [PRINT_BUF_SIZE]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // Buffer too small -- write everything that fits rather than
                // silently discarding all output.
                try self.write(&buf);
                return;
            },
        };
        try self.write(formatted);
    }

    /// Get the underlying file for direct access (bypasses \n conversion).
    pub fn raw(self: Self) std.Io.File {
        return self.file;
    }

    // ========================================================================
    // Screen control
    // ========================================================================

    /// Clear the entire screen and move cursor to top-left.
    pub fn clearScreen(self: Self) !void {
        try compat.writeAll(self.file, "\x1b[2J\x1b[H");
    }

    /// Clear from cursor to end of screen.
    pub fn clearToEnd(self: Self) !void {
        try compat.writeAll(self.file, "\x1b[J");
    }

    /// Clear the current line.
    pub fn clearLine(self: Self) !void {
        try compat.writeAll(self.file, "\r\x1b[K");
    }

    // ========================================================================
    // Color and styling
    // ========================================================================

    /// Set the foreground color. Only applies if color is enabled.
    /// Composes the full ANSI sequence in a stack buffer so only one
    /// writeAll syscall is needed instead of three.
    pub fn setColor(self: Self, color: Color) !void {
        if (self.use_color) {
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{s}m", .{color.code()}) catch return;
            try compat.writeAll(self.file, seq);
        }
    }

    /// Set text style (bold, underline, etc). Only applies if color is enabled.
    /// Composes the full ANSI sequence in a stack buffer so only one
    /// writeAll syscall is needed instead of three.
    pub fn setStyle(self: Self, style: Style) !void {
        if (self.use_color) {
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{s}m", .{style.code()}) catch return;
            try compat.writeAll(self.file, seq);
        }
    }

    /// Reset all colors and styles to default.
    pub fn resetStyle(self: Self) !void {
        if (self.use_color) {
            try compat.writeAll(self.file, "\x1b[0m");
        }
    }

    /// Write text with a specific color, then reset.
    pub fn writeColored(self: Self, color: Color, data: []const u8) !void {
        try self.setColor(color);
        try self.write(data);
        try self.resetStyle();
    }

    /// Write text with bold style, then reset.
    pub fn writeBold(self: Self, data: []const u8) !void {
        try self.setStyle(.bold);
        try self.write(data);
        try self.resetStyle();
    }

    /// Write text with color and style, then reset.
    pub fn writeStyled(self: Self, style: Style, color: Color, data: []const u8) !void {
        try self.setStyle(style);
        try self.setColor(color);
        try self.write(data);
        try self.resetStyle();
    }

    // ========================================================================
    // Common message patterns
    // ========================================================================

    /// Print an error message in red.
    pub fn writeError(self: Self, msg: []const u8) !void {
        try self.setStyle(.bold);
        try self.setColor(.red);
        try self.write("Error: ");
        try self.resetStyle();
        try self.setColor(.red);
        try self.writeLine(msg);
        try self.resetStyle();
    }

    /// Print a warning message in yellow.
    pub fn writeWarning(self: Self, msg: []const u8) !void {
        try self.setStyle(.bold);
        try self.setColor(.yellow);
        try self.write("Warning: ");
        try self.resetStyle();
        try self.setColor(.yellow);
        try self.writeLine(msg);
        try self.resetStyle();
    }

    /// Print a success message in green.
    pub fn writeSuccess(self: Self, msg: []const u8) !void {
        try self.setColor(.green);
        try self.writeLine(msg);
        try self.resetStyle();
    }

    /// Print an info message in cyan.
    pub fn writeInfo(self: Self, msg: []const u8) !void {
        try self.setColor(.cyan);
        try self.writeLine(msg);
        try self.resetStyle();
    }
};

/// Convenience function to get a terminal writer for stdout.
pub fn terminalWriter() TerminalWriter {
    return TerminalWriter.stdout();
}

test "platform handles" {
    _ = getStdinHandle();
    _ = getStdoutHandle();
    _ = getStderrHandle();
}

test "tty detection" {
    _ = isStdinTty();
    _ = isStdoutTty();
    _ = isStderrTty();
}

test "terminal dimensions" {
    const width = getTerminalWidth();
    const height = getTerminalHeight();
    try std.testing.expect(width > 0);
    try std.testing.expect(height > 0);
}

test "terminal writer newline conversion" {
    const convertNewlines = struct {
        fn convert(data: []const u8, buf: []u8) []const u8 {
            var out_idx: usize = 0;
            for (data) |c| {
                if (c == '\n') {
                    buf[out_idx] = '\r';
                    out_idx += 1;
                    buf[out_idx] = '\n';
                    out_idx += 1;
                } else {
                    buf[out_idx] = c;
                    out_idx += 1;
                }
            }
            return buf[0..out_idx];
        }
    };

    var buf: [256]u8 = undefined;
    const result1 = convertNewlines.convert("hello\nworld\n", &buf);
    try std.testing.expectEqualStrings("hello\r\nworld\r\n", result1);
    const result2 = convertNewlines.convert("no newlines", &buf);
    try std.testing.expectEqualStrings("no newlines", result2);
    const result3 = convertNewlines.convert("a\n\nb", &buf);
    try std.testing.expectEqualStrings("a\r\n\r\nb", result3);
    const result4 = convertNewlines.convert("", &buf);
    try std.testing.expectEqualStrings("", result4);
    const result5 = convertNewlines.convert("\nstart", &buf);
    try std.testing.expectEqualStrings("\r\nstart", result5);
}

/// Helper: create a TerminalWriter backed by a temporary file for testing,
/// then read back everything that was written. Color is disabled so that
/// test assertions do not depend on the test runner's TTY status.
fn createTestWriter() !struct { writer: TerminalWriter, tmp: std.Io.File } {
    const tmp = try compat.cwdCreateFile("/tmp/zig-repl-test-tw", .{
        .read = true,
        .truncate = true,
    });
    return .{
        .writer = .{ .file = tmp, .use_color = false },
        .tmp = tmp,
    };
}

fn readBackTestOutputPath(path: []const u8, buf: []u8) ![]const u8 {
    // Re-open the file for reading since createFile opens write-only in 0.16.0
    const io = compat.defaultIo();
    const rf = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer rf.close(io);
    const n = try rf.readPositionalAll(io, buf, 0);
    return buf[0..n];
}

fn readBackTestOutput(_: std.Io.File, buf: []u8) ![]const u8 {
    return readBackTestOutputPath("/tmp/zig-repl-test-tw", buf);
}

test "TerminalWriter.write converts newlines via buffered path" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    try ctx.writer.write("hello\nworld\n");
    var buf: [256]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("hello\r\nworld\r\n", out);
}

test "TerminalWriter.write handles empty input" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    try ctx.writer.write("");
    var buf: [256]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("", out);
}

test "TerminalWriter.write handles data with no newlines" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    try ctx.writer.write("no newlines here");
    var buf: [256]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("no newlines here", out);
}

test "TerminalWriter.write handles data larger than WRITE_BUF_SIZE" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    // Generate data larger than 8192 bytes with embedded newlines
    const size = TerminalWriter.WRITE_BUF_SIZE + 1000;
    var input: [size]u8 = undefined;
    for (&input, 0..) |*c, i| {
        // Place newlines every 100 chars to exercise the conversion
        if (i % 100 == 99) {
            c.* = '\n';
        } else {
            c.* = 'A';
        }
    }

    try ctx.writer.write(&input);

    // Read back and verify
    var read_buf: [size * 2]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &read_buf);

    // Count expected newlines
    var expected_newlines: usize = 0;
    for (input) |c| {
        if (c == '\n') expected_newlines += 1;
    }

    // Output should be input.len + expected_newlines bytes (each \n -> \r\n adds 1 byte)
    try std.testing.expectEqual(size + expected_newlines, out.len);

    // Verify no bare \n exists (all should be \r\n)
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        if (out[i] == '\n') {
            try std.testing.expect(i > 0);
            try std.testing.expectEqual(@as(u8, '\r'), out[i - 1]);
        }
    }
}

test "TerminalWriter.print writes formatted output" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    try ctx.writer.print("hello {s} {d}", .{ "world", 42 });
    var buf: [256]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("hello world 42", out);
}

test "TerminalWriter.print writes partial buffer on overflow instead of dropping" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    // Build a format string argument larger than PRINT_BUF_SIZE (4096).
    // We pass a long string that will exceed the buffer.
    const big = "X" ** (TerminalWriter.PRINT_BUF_SIZE + 100);
    try ctx.writer.print("{s}", .{big});

    // Read back -- should have written PRINT_BUF_SIZE bytes (the full buffer),
    // NOT zero bytes (old silent-drop behavior).
    var read_buf: [TerminalWriter.PRINT_BUF_SIZE + 200]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &read_buf);
    try std.testing.expectEqual(TerminalWriter.PRINT_BUF_SIZE, out.len);

    // Verify content is all 'X's
    for (out) |c| {
        try std.testing.expectEqual(@as(u8, 'X'), c);
    }
}

test "TerminalWriter.setColor composes single ANSI sequence" {
    // Create a writer with color enabled to test setColor
    const tmp = try compat.cwdCreateFile("/tmp/zig-repl-test-color", .{
        .read = true,
        .truncate = true,
    });
    defer tmp.close(compat.defaultIo());

    const writer = TerminalWriter{ .file = tmp, .use_color = true };
    try writer.setColor(.red);

    var buf: [64]u8 = undefined;
    const out = try readBackTestOutputPath("/tmp/zig-repl-test-color", &buf);
    try std.testing.expectEqualStrings("\x1b[31m", out);
}

test "TerminalWriter.setStyle composes single ANSI sequence" {
    const tmp = try compat.cwdCreateFile("/tmp/zig-repl-test-style", .{
        .read = true,
        .truncate = true,
    });
    defer tmp.close(compat.defaultIo());

    const writer = TerminalWriter{ .file = tmp, .use_color = true };
    try writer.setStyle(.bold);

    var buf: [64]u8 = undefined;
    const out = try readBackTestOutputPath("/tmp/zig-repl-test-style", &buf);
    try std.testing.expectEqualStrings("\x1b[1m", out);
}

test "TerminalWriter.setColor is no-op when color disabled" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    // ctx.writer has use_color = false
    try ctx.writer.setColor(.red);

    var buf: [64]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("", out);
}

test "TerminalWriter.setStyle is no-op when color disabled" {
    const ctx = try createTestWriter();
    defer ctx.tmp.close(compat.defaultIo());

    try ctx.writer.setStyle(.bold);

    var buf: [64]u8 = undefined;
    const out = try readBackTestOutput(ctx.tmp, &buf);
    try std.testing.expectEqualStrings("", out);
}

test "Color.code returns correct ANSI codes" {
    try std.testing.expectEqualStrings("39", Color.default.code());
    try std.testing.expectEqualStrings("31", Color.red.code());
    try std.testing.expectEqualStrings("32", Color.green.code());
    try std.testing.expectEqualStrings("97", Color.bright_white.code());
}

test "Style.code returns correct ANSI codes" {
    try std.testing.expectEqualStrings("0", Style.reset.code());
    try std.testing.expectEqualStrings("1", Style.bold.code());
    try std.testing.expectEqualStrings("2", Style.dim.code());
    try std.testing.expectEqualStrings("4", Style.underline.code());
}

test "buffer size constants are accessible" {
    try std.testing.expectEqual(@as(usize, 4096), TerminalWriter.PRINT_BUF_SIZE);
    try std.testing.expectEqual(@as(usize, 8192), TerminalWriter.WRITE_BUF_SIZE);
}

test "shouldUseColor returns bool" {
    // Smoke test: shouldUseColor should not crash and should return a bool.
    // The actual value depends on the test runner's environment (TTY, NO_COLOR, TERM).
    const result = shouldUseColor();
    try std.testing.expect(result == true or result == false);
}

test "stdinHasMoreData returns bool without blocking" {
    // stdinHasMoreData must return quickly (non-blocking) and produce a bool.
    const result = stdinHasMoreData();
    try std.testing.expect(result == true or result == false);
}

test "win32_console types compile on all platforms" {
    // Verify that the win32_console struct compiles without errors even on
    // non-Windows targets. On POSIX it is an empty struct.
    const T = win32_console;
    try std.testing.expect(@sizeOf(T) >= 0);
}

test "ENABLE_VIRTUAL_TERMINAL_PROCESSING constant exists" {
    // This constant is defined in std.os.windows and used in enterRawMode.
    // Verify it compiles as a constant expression.
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(u32, 0x4), std.os.windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
}
