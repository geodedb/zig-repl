// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Shared text utility functions.
//!
//! Used by core.zig, keymap_vi.zig, completion.zig, history.zig, and
//! config.zig to avoid duplicating common logic.

const std = @import("std");
const compat = @import("compat.zig");
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
    // Bounds check: app_name must fit in the upper-case buffer
    if (app_name.len > env_name_buf.len) return null;
    const env_name = std.ascii.upperString(&env_name_buf, app_name);
    var full_env_name: [512]u8 = undefined;
    // Bounds check: combined "APPNAME_SUFFIX" must fit in full_env_name buffer
    if (env_name.len + 1 + env_suffix.len > full_env_name.len) return null;
    const full_name = std.fmt.bufPrint(&full_env_name, "{s}_{s}", .{ env_name, env_suffix }) catch return null;
    if (compat.getEnvVarOwned(allocator, full_name)) |path| {
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

test "resolveEnvOverridePath returns null for oversized app_name" {
    const allocator = std.testing.allocator;
    // 300-byte app_name exceeds the 256-byte env_name_buf
    const oversized = "a" ** 300;
    const result = resolveEnvOverridePath(allocator, oversized, "HISTORY");
    try std.testing.expect(result == null);
}

test "resolveEnvOverridePath returns null when combined name exceeds buffer" {
    const allocator = std.testing.allocator;
    // 250-byte app_name fits in env_name_buf (256), but combined with a
    // 263-byte suffix "250 + 1 + 263 = 514" exceeds full_env_name (512)
    const large_name = "b" ** 250;
    const large_suffix = "S" ** 263;
    const result = resolveEnvOverridePath(allocator, large_name, large_suffix);
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
///
/// UTF-8-aware (GAP-0074 / APPSEC-02): in addition to C0 (except \t, \n) and
/// DEL, this drops:
///   - raw 8-bit C1 control bytes 0x80-0x9F that are not part of a valid
///     UTF-8 sequence (8-bit CSI/OSC/DCS/ST introducers on legacy terminals),
///   - UTF-8-encoded C1 codepoints U+0080-U+009F (0xC2 0x80..0xC2 0x9F),
///   - any other invalid UTF-8 byte.
/// Valid multi-byte UTF-8 sequences pass through unchanged.
///
/// INVARIANT: output length <= entry.len (the filter only drops bytes, never
/// expands). The appendAssumeCapacity calls below rely on this -- do not add
/// an expanding transform without switching to bounds-checked append and a
/// larger reservation.
pub fn appendHistoryFiltered(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, entry: []const u8) !void {
    // Pre-allocate to avoid log2(n) reallocs during per-byte append
    try buffer.ensureTotalCapacity(allocator, buffer.items.len + entry.len);
    var i: usize = 0;
    while (i < entry.len) {
        const c = entry[i];
        if (c < 0x80) {
            if (!isUnsafeControlChar(c)) {
                buffer.appendAssumeCapacity(c);
            }
            i += 1;
            continue;
        }
        // Non-ASCII: decode one UTF-8 sequence. Invalid lead bytes (which
        // include raw C1 0x80-0x9F and stray continuation bytes) are dropped.
        const seq_len = std.unicode.utf8ByteSequenceLength(c) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > entry.len) {
            // Truncated sequence at end of input: drop the lead byte.
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(entry[i..][0..seq_len]) catch {
            // Invalid sequence: drop the lead byte and rescan from the next.
            i += 1;
            continue;
        };
        if (cp >= 0x80 and cp <= 0x9F) {
            // UTF-8-encoded C1 control codepoint: drop the whole sequence.
            i += seq_len;
            continue;
        }
        buffer.appendSliceAssumeCapacity(entry[i..][0..seq_len]);
        i += seq_len;
    }
}

/// Canonical 7-bit bracketed-paste markers (ESC [ 200~ / ESC [ 201~).
pub const paste_start_marker = "\x1b[200~";
pub const paste_end_marker = "\x1b[201~";

/// Classification of the next byte sequence for terminal display.
pub const DisplaySpan = struct {
    /// Number of input bytes this span covers (always >= 1).
    len: usize,
    /// True if the bytes are a valid, non-control UTF-8 sequence safe to
    /// write to the terminal verbatim. False for invalid UTF-8 bytes and
    /// C1 control codepoints (U+0080-U+009F) -- render a placeholder instead.
    safe: bool,
};

/// Classify the byte sequence starting at `bytes[0]` for display purposes
/// (GAP-0074 / APPSEC-02). Callers must only invoke this for lead bytes
/// >= 0x80 (ASCII is handled inline by the render loop). Never returns
/// len == 0.
pub fn displaySpan(bytes: []const u8) DisplaySpan {
    const seq_len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch {
        return .{ .len = 1, .safe = false };
    };
    if (seq_len > bytes.len) return .{ .len = 1, .safe = false };
    const cp = std.unicode.utf8Decode(bytes[0..seq_len]) catch {
        return .{ .len = 1, .safe = false };
    };
    if (cp >= 0x80 and cp <= 0x9F) return .{ .len = seq_len, .safe = false };
    return .{ .len = seq_len, .safe = true };
}

/// If `data[pos..]` begins a bracketed-paste marker -- 7-bit `ESC [` or 8-bit
/// CSI (0x9B) introducer, optional leading zeros, then `200~` or `201~` --
/// return the marker's byte length; otherwise null.
fn pasteMarkerLen(data: []const u8, pos: usize) ?usize {
    var i = pos;
    // Introducer: ESC [ (2 bytes) or 8-bit CSI 0x9B (1 byte).
    if (i + 1 < data.len and data[i] == 0x1b and data[i + 1] == '[') {
        i += 2;
    } else if (i < data.len and data[i] == 0x9b) {
        i += 1;
    } else {
        return null;
    }
    // Optional leading zeros before the parameter (e.g. ESC[0200~ or
    // ESC[00201~). The parameter itself starts with '2', so skipping zeros
    // can never consume it.
    while (i < data.len and data[i] == '0') : (i += 1) {}
    // Parameter must be exactly 200 or 201, terminated by '~'.
    if (i + 3 >= data.len) return null;
    if (data[i] != '2' or data[i + 1] != '0') return null;
    if (data[i + 2] != '0' and data[i + 2] != '1') return null;
    if (data[i + 3] != '~') return null;
    return (i + 4) - pos;
}

/// Sanitize paste content by stripping embedded bracketed-paste markers.
/// This prevents pastejacking attacks where malicious content embeds fake
/// bracketed paste start/end markers to break out of paste mode. Recognizes
/// both the canonical 7-bit `ESC[200~`/`ESC[201~` forms and the 8-bit CSI
/// (0x9B) and zero-padded parameter variants (GAP-0075 / APPSEC-03).
pub fn sanitizePasteContent(data: []u8) []u8 {
    var read_pos: usize = 0;
    var write_pos: usize = 0;

    while (read_pos < data.len) {
        if (pasteMarkerLen(data, read_pos)) |marker_len| {
            // Skip the embedded sequence
            read_pos += marker_len;
            continue;
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

test "appendHistoryFiltered strips raw C1 control bytes (8-bit CSI/OSC)" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // Raw (non-UTF-8) C1 bytes: 0x9B (CSI), 0x9D (OSC), 0x9C (ST), 0x90 (DCS).
    // e.g. "\x9d0;pwned\x9c" is an 8-bit OSC title-set sequence.
    try appendHistoryFiltered(&buffer, allocator, "a\x9d0;pwned\x9cb\x9b31mc\x90d");
    try std.testing.expectEqualStrings("a0;pwnedb31mcd", buffer.items);
}

test "appendHistoryFiltered strips UTF-8-encoded C1 codepoints" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // U+009B encoded as UTF-8 (0xC2 0x9B) decodes to C1 CSI on UTF-8 terminals.
    try appendHistoryFiltered(&buffer, allocator, "a\xc2\x9b31mb");
    try std.testing.expectEqualStrings("a31mb", buffer.items);
}

test "appendHistoryFiltered preserves valid multi-byte UTF-8" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer buffer.deinit(allocator);

    // é (U+00E9, 0xC3 0xA9), 日 (U+65E5, 3 bytes), emoji (4 bytes) must survive.
    try appendHistoryFiltered(&buffer, allocator, "caf\xc3\xa9 \xe6\x97\xa5 \xf0\x9f\x98\x80");
    try std.testing.expectEqualStrings("caf\xc3\xa9 \xe6\x97\xa5 \xf0\x9f\x98\x80", buffer.items);
}

test "appendHistoryFiltered output never exceeds input length (invariant)" {
    const allocator = std.testing.allocator;
    // Property guard for the appendAssumeCapacity reservation (APPSEC-04):
    // the filter must only ever DROP bytes, never expand.
    const inputs = [_][]const u8{
        "plain", "\x9b\x9c\x9d", "\xc2\x9b", "\xff\xfe", "a\x1bb", "\xc3\xa9", "",
    };
    for (inputs) |input| {
        var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer buffer.deinit(allocator);
        try appendHistoryFiltered(&buffer, allocator, input);
        try std.testing.expect(buffer.items.len <= input.len);
    }
}

test "displaySpan classifies UTF-8 sequences and C1 bytes" {
    // Valid 2-byte UTF-8 (é): safe, len 2.
    {
        const span = displaySpan("\xc3\xa9x");
        try std.testing.expectEqual(@as(usize, 2), span.len);
        try std.testing.expect(span.safe);
    }
    // UTF-8-encoded C1 (U+009B): unsafe, len 2 (skip whole sequence).
    {
        const span = displaySpan("\xc2\x9bx");
        try std.testing.expectEqual(@as(usize, 2), span.len);
        try std.testing.expect(!span.safe);
    }
    // Raw C1 byte (0x9B, invalid UTF-8 lead): unsafe, len 1.
    {
        const span = displaySpan("\x9bx");
        try std.testing.expectEqual(@as(usize, 1), span.len);
        try std.testing.expect(!span.safe);
    }
    // Truncated sequence at end: unsafe, len 1.
    {
        const span = displaySpan("\xc3");
        try std.testing.expectEqual(@as(usize, 1), span.len);
        try std.testing.expect(!span.safe);
    }
}

test "sanitizePasteContent strips 8-bit CSI paste markers" {
    const allocator = std.testing.allocator;
    const input = "safe\x9b201~rm -rf ~\x9b200~after";
    const buf = try allocator.dupe(u8, input);
    defer allocator.free(buf);
    const result = sanitizePasteContent(buf);
    try std.testing.expectEqualStrings("saferm -rf ~after", result);
}

test "sanitizePasteContent strips zero-padded paste markers" {
    const allocator = std.testing.allocator;
    const input = "a\x1b[0200~b\x1b[00201~c";
    const buf = try allocator.dupe(u8, input);
    defer allocator.free(buf);
    const result = sanitizePasteContent(buf);
    try std.testing.expectEqualStrings("abc", result);
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
