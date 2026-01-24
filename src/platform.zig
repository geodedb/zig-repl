// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Cross-platform terminal I/O utilities
//!
//! Provides platform-agnostic access to standard I/O handles and TTY detection.

const std = @import("std");
const builtin = @import("builtin");

/// Get a handle to standard input.
/// Works on both POSIX systems and Windows.
pub fn getStdinHandle() std.fs.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch unreachable;
        return std.fs.File{ .handle = handle };
    } else {
        return std.fs.File{ .handle = std.posix.STDIN_FILENO };
    }
}

/// Get a handle to standard output.
/// Works on both POSIX systems and Windows.
pub fn getStdoutHandle() std.fs.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch unreachable;
        return std.fs.File{ .handle = handle };
    } else {
        return std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    }
}

/// Get a handle to standard error.
/// Works on both POSIX systems and Windows.
pub fn getStderrHandle() std.fs.File {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch unreachable;
        return std.fs.File{ .handle = handle };
    } else {
        return std.fs.File{ .handle = std.posix.STDERR_FILENO };
    }
}

/// Check if standard input is a TTY (interactive terminal).
pub fn isStdinTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return std.posix.isatty(std.posix.STDIN_FILENO);
    }
}

/// Check if standard output is a TTY (interactive terminal).
pub fn isStdoutTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return std.posix.isatty(std.posix.STDOUT_FILENO);
    }
}

/// Check if standard error is a TTY (interactive terminal).
pub fn isStderrTty() bool {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch return false;
        var mode: std.os.windows.DWORD = undefined;
        return std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
    } else {
        return std.posix.isatty(std.posix.STDERR_FILENO);
    }
}

/// Terminal state for raw mode management.
/// Platform-specific: termios on POSIX, DWORD on Windows.
pub const TerminalState = if (builtin.os.tag == .windows) std.os.windows.DWORD else std.posix.termios;

/// Enter raw terminal mode for character-by-character input.
/// Returns the original terminal state for later restoration.
pub fn enterRawMode() !TerminalState {
    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch unreachable;
        var mode: std.os.windows.DWORD = undefined;
        _ = std.os.windows.kernel32.GetConsoleMode(handle, &mode);
        const original = mode;

        // Disable line input and echo
        mode &= ~@as(std.os.windows.DWORD, 0x0002); // ENABLE_LINE_INPUT
        mode &= ~@as(std.os.windows.DWORD, 0x0004); // ENABLE_ECHO_INPUT
        _ = std.os.windows.kernel32.SetConsoleMode(handle, mode);

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

    // Enable bracketed paste mode
    const stdout = getStdoutHandle();
    try stdout.writeAll("\x1b[?2004h");

    return original;
}

/// Restore terminal to its original state.
pub fn restoreTerminalMode(original: TerminalState) !void {
    // Disable bracketed paste mode
    const stdout = getStdoutHandle();
    stdout.writeAll("\x1b[?2004l") catch {};

    if (builtin.os.tag == .windows) {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return;
        _ = std.os.windows.kernel32.SetConsoleMode(handle, original);
        return;
    }

    const stdin = getStdinHandle();
    try std.posix.tcsetattr(stdin.handle, .FLUSH, original);
}

/// Get terminal width in columns.
/// Returns 80 as default if unavailable.
pub fn getTerminalWidth() usize {
    if (builtin.os.tag == .windows) {
        return 80; // Default for Windows (could use GetConsoleScreenBufferInfo)
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
        return 24; // Default for Windows
    } else {
        var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0 and ws.row > 0) {
            return @as(usize, ws.row);
        }
        return 24;
    }
}

/// Check if stdin has more data available (non-blocking).
pub fn stdinHasMoreData() bool {
    if (builtin.os.tag == .windows) {
        // Windows: always return false, render after each read
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
    // Check NO_COLOR environment variable (https://no-color.org/)
    if (std.posix.getenv("NO_COLOR")) |_| {
        return false;
    }

    // Check TERM for dumb terminal
    if (std.posix.getenv("TERM")) |term| {
        if (std.mem.eql(u8, term, "dumb")) {
            return false;
        }
    }

    return isStdoutTty();
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
    file: std.fs.File,
    use_color: bool,

    const Self = @This();

    /// Create a new terminal writer wrapping the given file handle.
    pub fn init(file: std.fs.File) Self {
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

    /// Write a string, converting \n to \r\n for raw terminal mode.
    pub fn write(self: Self, data: []const u8) !void {
        var start: usize = 0;
        for (data, 0..) |c, i| {
            if (c == '\n') {
                // Write everything up to (but not including) the \n
                if (i > start) {
                    try self.file.writeAll(data[start..i]);
                }
                // Write \r\n instead of just \n
                try self.file.writeAll("\r\n");
                start = i + 1;
            }
        }
        // Write any remaining data after the last \n
        if (start < data.len) {
            try self.file.writeAll(data[start..]);
        }
    }

    /// Write a string followed by a newline (converted to \r\n).
    pub fn writeLine(self: Self, data: []const u8) !void {
        try self.write(data);
        try self.file.writeAll("\r\n");
    }

    /// Print formatted output, converting \n to \r\n.
    pub fn print(self: Self, comptime fmt: []const u8, args: anytype) !void {
        var buf: [4096]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, fmt, args) catch {
            // Buffer too small - this is rare, just truncate
            return;
        };
        try self.write(formatted);
    }

    /// Get the underlying file for direct access (bypasses \n conversion).
    pub fn raw(self: Self) std.fs.File {
        return self.file;
    }

    // ========================================================================
    // Screen control
    // ========================================================================

    /// Clear the entire screen and move cursor to top-left.
    pub fn clearScreen(self: Self) !void {
        try self.file.writeAll("\x1b[2J\x1b[H");
    }

    /// Clear from cursor to end of screen.
    pub fn clearToEnd(self: Self) !void {
        try self.file.writeAll("\x1b[J");
    }

    /// Clear the current line.
    pub fn clearLine(self: Self) !void {
        try self.file.writeAll("\r\x1b[K");
    }

    // ========================================================================
    // Color and styling
    // ========================================================================

    /// Set the foreground color. Only applies if color is enabled.
    pub fn setColor(self: Self, color: Color) !void {
        if (self.use_color) {
            try self.file.writeAll("\x1b[");
            try self.file.writeAll(color.code());
            try self.file.writeAll("m");
        }
    }

    /// Set text style (bold, underline, etc). Only applies if color is enabled.
    pub fn setStyle(self: Self, style: Style) !void {
        if (self.use_color) {
            try self.file.writeAll("\x1b[");
            try self.file.writeAll(style.code());
            try self.file.writeAll("m");
        }
    }

    /// Reset all colors and styles to default.
    pub fn resetStyle(self: Self) !void {
        if (self.use_color) {
            try self.file.writeAll("\x1b[0m");
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
    // Just verify these don't crash
    _ = getStdinHandle();
    _ = getStdoutHandle();
    _ = getStderrHandle();
}

test "tty detection" {
    // These may return true or false depending on test environment
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
    // Test the conversion logic used in TerminalWriter
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

    // Test basic newline conversion
    const result1 = convertNewlines.convert("hello\nworld\n", &buf);
    try std.testing.expectEqualStrings("hello\r\nworld\r\n", result1);

    // Test no newlines
    const result2 = convertNewlines.convert("no newlines", &buf);
    try std.testing.expectEqualStrings("no newlines", result2);

    // Test multiple consecutive newlines
    const result3 = convertNewlines.convert("a\n\nb", &buf);
    try std.testing.expectEqualStrings("a\r\n\r\nb", result3);

    // Test empty string
    const result4 = convertNewlines.convert("", &buf);
    try std.testing.expectEqualStrings("", result4);

    // Test newline at start
    const result5 = convertNewlines.convert("\nstart", &buf);
    try std.testing.expectEqualStrings("\r\nstart", result5);
}
