// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Shared text utility functions.
//!
//! Used by core.zig, keymap_vi.zig, completion.zig, history.zig, and
//! config.zig to avoid duplicating common logic.

const std = @import("std");
const builtin = @import("builtin");

/// Find the start of the word at or before `pos`.
///
/// Skips whitespace backwards, then skips non-whitespace backwards.
/// Returns the index of the first character of the word.
pub fn findWordStart(text: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var i = pos;
    while (i > 0 and std.ascii.isWhitespace(text[i - 1])) : (i -= 1) {}
    while (i > 0 and !std.ascii.isWhitespace(text[i - 1])) : (i -= 1) {}
    return i;
}

/// Find the end of the word at or after `pos`.
///
/// Skips non-whitespace forward, then skips whitespace forward.
/// Returns the index past the trailing whitespace (start of next word or end of text).
pub fn findWordEnd(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return text.len;
    var i = pos;
    while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    return i;
}

test "findWordStart at beginning" {
    try std.testing.expectEqual(@as(usize, 0), findWordStart("hello", 0));
    try std.testing.expectEqual(@as(usize, 0), findWordStart("hello world", 0));
}

test "findWordEnd at end" {
    const text = "hello";
    try std.testing.expectEqual(@as(usize, 5), findWordEnd(text, 5));
    try std.testing.expectEqual(@as(usize, 5), findWordEnd(text, 0));
}

test "findWordStart skips spaces" {
    try std.testing.expectEqual(@as(usize, 6), findWordStart("hello world", 11));
    try std.testing.expectEqual(@as(usize, 0), findWordStart("hello world", 5));
    try std.testing.expectEqual(@as(usize, 2), findWordStart("  hello", 7));
}

test "findWordEnd skips to next word" {
    const text = "hello world test";
    try std.testing.expectEqual(@as(usize, 6), findWordEnd(text, 0));
    try std.testing.expectEqual(@as(usize, 12), findWordEnd(text, 6));
}

test "findWordStart and findWordEnd with single word" {
    const text = "hello";
    try std.testing.expectEqual(@as(usize, 0), findWordStart(text, 3));
    try std.testing.expectEqual(@as(usize, 5), findWordEnd(text, 3));
}

test "findWordEnd past end of text" {
    const text = "hello";
    try std.testing.expectEqual(@as(usize, 5), findWordEnd(text, 10));
}

test "findWordStart with multiple spaces" {
    const text = "hello   world";
    try std.testing.expectEqual(@as(usize, 8), findWordStart(text, 13));
    try std.testing.expectEqual(@as(usize, 0), findWordStart(text, 5));
}

test "findWordEnd with empty text" {
    try std.testing.expectEqual(@as(usize, 0), findWordEnd("", 0));
}

test "findWordStart with empty text" {
    try std.testing.expectEqual(@as(usize, 0), findWordStart("", 0));
}

// =============================================================================
// Path validation
// =============================================================================

/// Validate that a path from an environment variable is safe to use.
///
/// Rejects paths that:
/// - Are not absolute (must start with `/` on POSIX, drive letter on Windows)
/// - Contain `..` path components (path traversal)
///
/// Returns true if the path is safe to use, false otherwise.
pub fn isPathSafe(path: []const u8) bool {
    if (path.len == 0) return false;

    // On POSIX, require absolute path (starts with /)
    // On Windows, require drive letter (e.g., C:\) or UNC path (\\)
    if (builtin.os.tag == .windows) {
        const has_drive = path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path[2] == '\\' or path[2] == '/');
        const has_unc = path.len >= 2 and path[0] == '\\' and path[1] == '\\';
        if (!has_drive and !has_unc) return false;
    } else {
        if (path[0] != '/') return false;
    }

    // Reject paths containing ".." components
    const sep: u8 = if (builtin.os.tag == .windows) '\\' else '/';
    var it = std.mem.splitScalar(u8, path, sep);
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, "..")) return false;
        // Also check for mixed separators on Windows
        if (builtin.os.tag == .windows) {
            var sub_it = std.mem.splitScalar(u8, component, '/');
            while (sub_it.next()) |sub_comp| {
                if (std.mem.eql(u8, sub_comp, "..")) return false;
            }
        }
    }

    return true;
}

test "isPathSafe rejects empty path" {
    try std.testing.expect(!isPathSafe(""));
}

test "isPathSafe rejects relative paths" {
    try std.testing.expect(!isPathSafe("relative/path"));
    try std.testing.expect(!isPathSafe("./relative/path"));
    try std.testing.expect(!isPathSafe("file.txt"));
}

test "isPathSafe rejects path traversal" {
    try std.testing.expect(!isPathSafe("/home/user/../etc/passwd"));
    try std.testing.expect(!isPathSafe("/home/user/.."));
    try std.testing.expect(!isPathSafe("/../etc/passwd"));
    try std.testing.expect(!isPathSafe("/tmp/safe/../../etc/shadow"));
}

test "isPathSafe accepts valid absolute paths" {
    try std.testing.expect(isPathSafe("/home/user/.app_history"));
    try std.testing.expect(isPathSafe("/tmp/test"));
    try std.testing.expect(isPathSafe("/var/data/app/history"));
    try std.testing.expect(isPathSafe("/"));
}

test "isPathSafe allows dots that are not traversal" {
    try std.testing.expect(isPathSafe("/home/user/.config/app"));
    try std.testing.expect(isPathSafe("/home/user/file.txt"));
    try std.testing.expect(isPathSafe("/home/user/.hidden"));
    try std.testing.expect(isPathSafe("/home/user/...not_traversal"));
}

// =============================================================================
// Environment variable path resolution
// =============================================================================

/// Check for an environment variable override path for the given app and suffix.
/// Builds the env var name as UPPERCASE(app_name) + "_" + env_suffix (e.g., "MYAPP_HISTORY"),
/// then checks getEnvVarOwned and validates the result with isPathSafe.
/// Returns the path if the env var is set and passes safety validation, null otherwise.
/// Caller owns the returned memory.
pub fn resolveEnvOverridePath(
    allocator: std.mem.Allocator,
    app_name: []const u8,
    env_suffix: []const u8,
) ?[]u8 {
    var env_name_buf: [256]u8 = undefined;
    const env_name = std.ascii.upperString(&env_name_buf, app_name);
    var full_env_name: [512]u8 = undefined;
    const full_name = std.fmt.bufPrint(&full_env_name, "{s}_{s}", .{ env_name, env_suffix }) catch return null;
    if (std.process.getEnvVarOwned(allocator, full_name)) |path| {
        if (isPathSafe(path)) {
            return path;
        }
        // Path failed validation; free and fall through
        allocator.free(path);
    } else |_| {}
    return null;
}

test "resolveEnvOverridePath returns null when env var is not set" {
    const allocator = std.testing.allocator;
    // Use a name unlikely to collide with real env vars
    const result = resolveEnvOverridePath(allocator, "zig_repl_test_nonexistent_xyzzy", "HISTORY");
    try std.testing.expect(result == null);
}

// =============================================================================
// Control character filtering and paste sanitization
// =============================================================================

/// Check if a byte is a dangerous control character that should be filtered.
/// Allows \t (0x09) and \n (0x0A) through; filters 0x00-0x08, 0x0B-0x0C,
/// 0x0E-0x1F, and 0x7F (DEL).
pub fn isUnsafeControlChar(c: u8) bool {
    if (c == '\t' or c == '\n') return false;
    if (c <= 0x1F) return true;
    if (c == 0x7F) return true;
    return false;
}

/// Append a history entry to the buffer, filtering out unsafe control characters.
/// This prevents terminal injection from crafted history file entries (SF-009).
pub fn appendHistoryFiltered(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, entry: []const u8) !void {
    // Pre-allocate to avoid log2(n) reallocs during per-byte append
    try buffer.ensureTotalCapacity(allocator, buffer.items.len + entry.len);
    for (entry) |c| {
        if (!isUnsafeControlChar(c)) {
            buffer.appendAssumeCapacity(c);
        }
    }
}

/// Sanitize paste content by stripping embedded ESC[200~ and ESC[201~ sequences.
/// This prevents pastejacking attacks where malicious content embeds fake
/// bracketed paste end markers to break out of paste mode.
pub fn sanitizePasteContent(data: []u8) []u8 {
    const paste_start = "\x1b[200~";
    const paste_end = "\x1b[201~";
    var read_pos: usize = 0;
    var write_pos: usize = 0;

    while (read_pos < data.len) {
        // Check if current position starts an embedded paste sequence
        if (read_pos + 6 <= data.len) {
            const slice = data[read_pos .. read_pos + 6];
            if (std.mem.eql(u8, slice, paste_start) or std.mem.eql(u8, slice, paste_end)) {
                // Skip the embedded sequence
                read_pos += 6;
                continue;
            }
        }
        data[write_pos] = data[read_pos];
        write_pos += 1;
        read_pos += 1;
    }

    return data[0..write_pos];
}

test "isUnsafeControlChar filters control characters" {
    // Allowed characters
    try std.testing.expect(!isUnsafeControlChar('\t')); // 0x09 tab
    try std.testing.expect(!isUnsafeControlChar('\n')); // 0x0A newline
    try std.testing.expect(!isUnsafeControlChar(' ')); // 0x20 space
    try std.testing.expect(!isUnsafeControlChar('A')); // printable
    try std.testing.expect(!isUnsafeControlChar('~')); // 0x7E printable

    // Filtered characters
    try std.testing.expect(isUnsafeControlChar(0x00)); // NUL
    try std.testing.expect(isUnsafeControlChar(0x01)); // SOH
    try std.testing.expect(isUnsafeControlChar(0x07)); // BEL
    try std.testing.expect(isUnsafeControlChar(0x08)); // BS
    try std.testing.expect(isUnsafeControlChar(0x0B)); // VT
    try std.testing.expect(isUnsafeControlChar(0x0C)); // FF
    try std.testing.expect(isUnsafeControlChar(0x0E)); // SO
    try std.testing.expect(isUnsafeControlChar(0x1B)); // ESC
    try std.testing.expect(isUnsafeControlChar(0x1F)); // US
    try std.testing.expect(isUnsafeControlChar(0x7F)); // DEL
}

test "appendHistoryFiltered strips control characters" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // Input with embedded control chars: BEL, ESC, DEL mixed with normal text
    try appendHistoryFiltered(&buffer, allocator, "hello\x07\x1b[31mworld\x7f");
    // \x07 (BEL), \x1b (ESC) filtered; '[', '3', '1', 'm' printable; \x7F (DEL) filtered
    try std.testing.expectEqualStrings("hello[31mworld", buffer.items);
}

test "sanitizePasteContent strips embedded paste sequences" {
    // Test stripping embedded ESC[201~ (paste end marker)
    var data1 = "hello\x1b[201~world".*;
    const result1 = sanitizePasteContent(&data1);
    try std.testing.expectEqualStrings("helloworld", result1);

    // Test stripping embedded ESC[200~ (paste start marker)
    var data2 = "abc\x1b[200~def".*;
    const result2 = sanitizePasteContent(&data2);
    try std.testing.expectEqualStrings("abcdef", result2);

    // Test clean data passes through unchanged
    var data3 = "clean text".*;
    const result3 = sanitizePasteContent(&data3);
    try std.testing.expectEqualStrings("clean text", result3);

    // Test multiple embedded sequences
    var data4 = "a\x1b[201~b\x1b[200~c".*;
    const result4 = sanitizePasteContent(&data4);
    try std.testing.expectEqualStrings("abc", result4);
}
