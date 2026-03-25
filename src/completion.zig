// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Tab completion functionality
//!
//! Provides extensible tab completion with support for:
//! - Keyword completion
//! - File path completion
//! - Custom completion providers
//! - Cycling through candidates

const std = @import("std");
const builtin = @import("builtin");
const text_utils = @import("text_utils.zig");

/// Maximum number of file path candidates returned by directory iteration.
/// Prevents unbounded iteration in large directories (e.g., /usr/bin with thousands of entries).
pub const MAX_FILE_CANDIDATES = 256;

/// Context for tracking completion state during tab cycling.
pub const CompletionContext = struct {
    allocator: std.mem.Allocator,
    candidates: std.ArrayList([]const u8),
    current_index: usize = 0,
    /// The original prefix before completion started
    original_prefix: []const u8 = "",
    /// Position where the word being completed starts
    word_start: usize = 0,
    /// Whether completion is active (cycling through candidates)
    active: bool = false,

    /// Initialize a CompletionContext with the given allocator, ready to collect candidates.
    pub fn init(allocator: std.mem.Allocator) CompletionContext {
        return .{
            .allocator = allocator,
            .candidates = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
        };
    }

    /// Free all allocated candidates and the stored prefix.
    pub fn deinit(self: *CompletionContext) void {
        for (self.candidates.items) |candidate| {
            self.allocator.free(candidate);
        }
        self.candidates.deinit(self.allocator);
        if (self.original_prefix.len > 0) {
            self.allocator.free(self.original_prefix);
        }
    }

    /// Reset completion state (called when buffer content changes).
    pub fn reset(self: *CompletionContext) void {
        for (self.candidates.items) |candidate| {
            self.allocator.free(candidate);
        }
        self.candidates.clearRetainingCapacity();
        self.current_index = 0;
        if (self.original_prefix.len > 0) {
            self.allocator.free(self.original_prefix);
            self.original_prefix = "";
        }
        self.word_start = 0;
        self.active = false;
    }

    /// Add a candidate to the completion list.
    pub fn addCandidate(self: *CompletionContext, candidate: []const u8) !void {
        const dup = try self.allocator.dupe(u8, candidate);
        try self.candidates.append(self.allocator, dup);
    }

    /// Get the current completion candidate.
    pub fn getCurrentCandidate(self: *const CompletionContext) ?[]const u8 {
        if (self.candidates.items.len == 0) return null;
        return self.candidates.items[self.current_index];
    }

    /// Advance to the next candidate (for cycling).
    pub fn nextCandidate(self: *CompletionContext) void {
        if (self.candidates.items.len > 0) {
            self.current_index = (self.current_index + 1) % self.candidates.items.len;
        }
    }

    /// Go back to the previous candidate.
    pub fn prevCandidate(self: *CompletionContext) void {
        if (self.candidates.items.len > 0) {
            if (self.current_index == 0) {
                self.current_index = self.candidates.items.len - 1;
            } else {
                self.current_index -= 1;
            }
        }
    }
};

/// Completion provider interface.
/// Implementations provide candidates for specific contexts.
///
/// This is a consumer-facing API: the REPL core does not call it internally.
/// Library users create and register providers to supply domain-specific
/// completions (e.g., SQL keywords, shell commands).
pub const CompletionProvider = struct {
    /// Generate completion candidates for the given context.
    /// Returns true if this provider handled the completion.
    generateFn: *const fn (
        provider: *const CompletionProvider,
        ctx: *CompletionContext,
        buffer: []const u8,
        cursor: usize,
        word_start: usize,
        prefix: []const u8,
    ) anyerror!bool,

    /// User-defined context data
    context: ?*anyopaque = null,

    /// Delegate to the underlying generateFn callback to produce completion candidates for the given prefix.
    pub fn generate(
        self: *const CompletionProvider,
        ctx: *CompletionContext,
        buffer: []const u8,
        cursor: usize,
        word_start: usize,
        prefix: []const u8,
    ) !bool {
        return self.generateFn(self, ctx, buffer, cursor, word_start, prefix);
    }
};

/// Create a completion provider for a static list of keywords.
///
/// This is a consumer-facing API: the REPL core does not call it internally.
/// Library users call this helper to build a `CompletionProvider` backed by a
/// fixed keyword list (e.g., SQL reserved words, REPL meta-commands).
///
/// The `keywords` pointer must outlive the returned provider.
pub fn keywordProvider(keywords: *const []const []const u8) CompletionProvider {
    const Impl = struct {
        fn generate(
            provider: *const CompletionProvider,
            ctx: *CompletionContext,
            buffer: []const u8,
            cursor: usize,
            word_start: usize,
            prefix: []const u8,
        ) !bool {
            _ = buffer;
            _ = cursor;
            _ = word_start;
            const kw_ptr: *const []const []const u8 = @ptrCast(@alignCast(provider.context.?));
            const kw_list = kw_ptr.*;

            // Convert prefix to uppercase for case-insensitive matching
            var upper_prefix: [256]u8 = undefined;
            const upper_len = @min(prefix.len, upper_prefix.len);
            for (prefix[0..upper_len], 0..) |c, i| {
                upper_prefix[i] = std.ascii.toUpper(c);
            }
            const upper_slice = upper_prefix[0..upper_len];

            for (kw_list) |keyword| {
                if (std.mem.startsWith(u8, keyword, upper_slice)) {
                    try ctx.addCandidate(keyword);
                }
            }

            return ctx.candidates.items.len > 0;
        }
    };

    return CompletionProvider{
        .generateFn = Impl.generate,
        .context = @ptrCast(@constCast(keywords)),
    };
}

/// Get the user's home directory in a cross-platform manner.
/// On POSIX, reads $HOME. On Windows, reads $USERPROFILE (decoded to UTF-8).
fn getHomeDir() ?[]const u8 {
    if (builtin.os.tag == .windows) {
        const key = std.unicode.utf8ToUtf16LeStringLiteral("USERPROFILE");
        const value_w: [:0]const u16 = std.process.getenvW(key) orelse return null;
        // Convert UTF-16LE to UTF-8 into a static buffer large enough for
        // any realistic Windows profile path.
        const n = std.unicode.utf16LeToUtf8(&home_dir_buf, value_w) catch return null;
        return home_dir_buf[0..n];
    } else {
        return std.posix.getenv("HOME");
    }
}

/// Static buffer for the Windows home directory path (UTF-8 decoded).
threadlocal var home_dir_buf: [512]u8 = undefined;

/// Generate file path completion candidates.
pub fn generateFilePathCandidates(ctx: *CompletionContext, prefix: []const u8) !void {
    var path_buf: [2048]u8 = undefined;
    var exp_buf: [512]u8 = undefined;
    var search_dir: []const u8 = ".";
    var file_prefix: []const u8 = prefix;
    var expanded_prefix: []const u8 = "";

    // Handle tilde expansion
    if (prefix.len > 0 and prefix[0] == '~') {
        const home = getHomeDir() orelse return;
        if (prefix.len == 1) {
            search_dir = home;
            file_prefix = "";
            expanded_prefix = "~/";
        } else if (prefix[1] == '/') {
            const rest = prefix[2..];
            if (std.mem.lastIndexOf(u8, rest, "/")) |last_slash| {
                const subpath = rest[0 .. last_slash + 1];
                const resolved = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, subpath }) catch return;
                search_dir = resolved;
                file_prefix = rest[last_slash + 1 ..];
                expanded_prefix = std.fmt.bufPrint(&exp_buf, "~/{s}", .{subpath}) catch return;
            } else {
                search_dir = home;
                file_prefix = rest;
                expanded_prefix = "~/";
            }
        } else {
            return; // ~user syntax not supported
        }
    } else if (prefix.len > 0 and prefix[0] == '/') {
        // Absolute path
        if (std.mem.lastIndexOf(u8, prefix, "/")) |last_slash| {
            if (last_slash == 0) {
                search_dir = "/";
                file_prefix = prefix[1..];
                expanded_prefix = "/";
            } else {
                search_dir = prefix[0..last_slash];
                file_prefix = prefix[last_slash + 1 ..];
                expanded_prefix = std.fmt.bufPrint(&exp_buf, "{s}/", .{prefix[0..last_slash]}) catch return;
            }
        }
    } else if (std.mem.indexOf(u8, prefix, "/")) |_| {
        // Relative path with subdirectory
        const last_slash = std.mem.lastIndexOf(u8, prefix, "/") orelse 0;
        search_dir = prefix[0..last_slash];
        file_prefix = prefix[last_slash + 1 ..];
        expanded_prefix = std.fmt.bufPrint(&exp_buf, "{s}/", .{prefix[0..last_slash]}) catch return;
    }

    // Open directory
    var dir = std.fs.cwd().openDir(search_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    // Iterate directory entries
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        // Skip hidden files unless prefix starts with .
        if (entry.name[0] == '.' and (file_prefix.len == 0 or file_prefix[0] != '.')) {
            continue;
        }

        // Check if entry name starts with prefix
        if (!std.mem.startsWith(u8, entry.name, file_prefix)) {
            continue;
        }

        // Build complete path
        var candidate_buf: [512]u8 = undefined;
        const suffix: []const u8 = if (entry.kind == .directory) "/" else "";
        const candidate = std.fmt.bufPrint(&candidate_buf, "{s}{s}{s}", .{ expanded_prefix, entry.name, suffix }) catch continue;

        try ctx.addCandidate(candidate);

        if (ctx.candidates.items.len >= MAX_FILE_CANDIDATES) break;
    }

    // Sort candidates for consistent ordering
    if (ctx.candidates.items.len > 1) {
        std.mem.sort([]const u8, ctx.candidates.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
    }
}

/// Find the start of the current word (for completion).
/// Delegates to the canonical implementation in text_utils.zig.
pub const findWordStart = text_utils.findWordStart;

/// Generate candidates from a predefined list that match the prefix.
pub fn generateCandidatesFromList(ctx: *CompletionContext, prefix: []const u8, options: []const []const u8) !void {
    for (options) |option| {
        if (std.mem.startsWith(u8, option, prefix)) {
            try ctx.addCandidate(option);
        }
    }
}

test "completion context lifecycle" {
    const allocator = std.testing.allocator;

    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    try ctx.addCandidate("candidate1");
    try ctx.addCandidate("candidate2");
    try ctx.addCandidate("candidate3");

    try std.testing.expect(ctx.candidates.items.len == 3);
    try std.testing.expectEqualStrings("candidate1", ctx.getCurrentCandidate().?);

    ctx.nextCandidate();
    try std.testing.expectEqualStrings("candidate2", ctx.getCurrentCandidate().?);

    ctx.nextCandidate();
    try std.testing.expectEqualStrings("candidate3", ctx.getCurrentCandidate().?);

    ctx.nextCandidate();
    try std.testing.expectEqualStrings("candidate1", ctx.getCurrentCandidate().?); // Wraps around

    ctx.prevCandidate();
    try std.testing.expectEqualStrings("candidate3", ctx.getCurrentCandidate().?);
}

test "completion reset" {
    const allocator = std.testing.allocator;

    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    try ctx.addCandidate("candidate1");
    try std.testing.expect(ctx.candidates.items.len == 1);

    ctx.reset();
    try std.testing.expect(ctx.candidates.items.len == 0);
    try std.testing.expect(!ctx.active);
}

test "word start detection" {
    try std.testing.expect(findWordStart("hello world", 11) == 6);
    try std.testing.expect(findWordStart("hello world", 5) == 0);
    try std.testing.expect(findWordStart("hello", 3) == 0);
    try std.testing.expect(findWordStart("  hello", 7) == 2);
}

test "generate candidates from list" {
    const allocator = std.testing.allocator;

    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    const options = [_][]const u8{ "apple", "apricot", "banana", "avocado" };
    try generateCandidatesFromList(&ctx, "ap", &options);

    try std.testing.expect(ctx.candidates.items.len == 2);
}

test "MAX_FILE_CANDIDATES constant is accessible" {
    // Verify the constant exists and has the expected value
    try std.testing.expect(MAX_FILE_CANDIDATES == 256);
}

test "file path candidates limited to MAX_FILE_CANDIDATES" {
    const allocator = std.testing.allocator;

    // Create a temporary directory with more files than the limit
    const tmp_dir_path = "/tmp/test_repl_completion_limit";

    // Clean up from any previous run
    std.fs.cwd().deleteTree(tmp_dir_path) catch {};

    // Create the directory
    std.fs.cwd().makePath(tmp_dir_path) catch return;
    defer std.fs.cwd().deleteTree(tmp_dir_path) catch {};

    // Create MAX_FILE_CANDIDATES + 50 files (all starting with the same prefix)
    const num_files = MAX_FILE_CANDIDATES + 50;
    for (0..num_files) |i| {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "{s}/file_{d:0>4}.txt", .{ tmp_dir_path, i }) catch continue;
        const file = std.fs.cwd().createFile(name, .{}) catch continue;
        file.close();
    }

    // Generate file path candidates for the temp directory
    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    var prefix_buf: [256]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/file_", .{tmp_dir_path}) catch return;

    try generateFilePathCandidates(&ctx, prefix);

    // The number of candidates should be capped at MAX_FILE_CANDIDATES
    try std.testing.expect(ctx.candidates.items.len <= MAX_FILE_CANDIDATES);
    // And since we created more files than the limit, it should be exactly the limit
    try std.testing.expect(ctx.candidates.items.len == MAX_FILE_CANDIDATES);
}

test "keywordProvider generates matching candidates" {
    const allocator = std.testing.allocator;

    const keywords: []const []const u8 = &.{ "SELECT", "SET", "SHOW", "INSERT", "UPDATE" };
    const provider = keywordProvider(&keywords);

    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    // Call generate after keywordProvider has returned -- this would
    // read from a dangling stack pointer if the old by-value parameter
    // was still used (SF-030).
    const handled = try provider.generate(&ctx, "", 0, 0, "SE");
    try std.testing.expect(handled);
    try std.testing.expect(ctx.candidates.items.len == 2);
    // Candidates should be SELECT and SET (both start with "SE")
    var found_select = false;
    var found_set = false;
    for (ctx.candidates.items) |c| {
        if (std.mem.eql(u8, c, "SELECT")) found_select = true;
        if (std.mem.eql(u8, c, "SET")) found_set = true;
    }
    try std.testing.expect(found_select);
    try std.testing.expect(found_set);
}

test "keywordProvider returns false when no keywords match" {
    const allocator = std.testing.allocator;

    const keywords: []const []const u8 = &.{ "SELECT", "INSERT" };
    const provider = keywordProvider(&keywords);

    var ctx = CompletionContext.init(allocator);
    defer ctx.deinit();

    const handled = try provider.generate(&ctx, "", 0, 0, "ZZ");
    try std.testing.expect(!handled);
    try std.testing.expect(ctx.candidates.items.len == 0);
}

test "getHomeDir returns a non-null value on POSIX when HOME is set" {
    // On the CI/test host, HOME should always be set.
    if (builtin.os.tag != .windows) {
        const home = getHomeDir();
        try std.testing.expect(home != null);
        try std.testing.expect(home.?.len > 0);
        // The home directory should be an absolute path.
        try std.testing.expect(home.?[0] == '/');
    }
}

test "getHomeDir returns same value as std.posix.getenv HOME on POSIX" {
    if (builtin.os.tag != .windows) {
        const from_helper = getHomeDir();
        const from_posix = std.posix.getenv("HOME");
        if (from_posix) |expected| {
            try std.testing.expect(from_helper != null);
            try std.testing.expectEqualStrings(expected, from_helper.?);
        }
    }
}
