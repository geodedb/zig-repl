// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Command history management
//!
//! Provides persistent command history with support for:
//! - In-memory history during session
//! - Persistent storage to disk
//! - Duplicate detection
//! - Privacy (skip lines starting with space)
//! - Search functionality

const std = @import("std");
const compat = @import("compat.zig");
const builtin = @import("builtin");
const text_utils = @import("text_utils.zig");

/// Manages command history with optional persistence.
pub const HistoryStore = struct {
    allocator: std.mem.Allocator,
    path: ?[]u8,
    enabled: bool,
    entries: std.ArrayList([]u8),
    max_entries: usize = 5000,
    /// When true, appending a line removes any earlier duplicate from history
    /// so that the new entry appears only once, at the end. When false (the
    /// default), only consecutive duplicates are suppressed.
    deduplicate_global: bool = false,
    file_mutex: compat.Mutex = compat.Mutex.init,
    dir_ensured: bool = false,
    /// PF-004: Persistent file handle kept open for the lifetime of the store
    /// to avoid open/close overhead on every append. Lazily opened on first
    /// append; closed in deinit() and reset in clear().
    append_handle: ?std.Io.File = null,

    /// Initialize a new history store.
    ///
    /// Parameters:
    /// - allocator: Memory allocator for history entries
    /// - path: Optional path to history file for persistence
    /// - enabled: Whether history tracking is enabled
    pub fn init(allocator: std.mem.Allocator, path: ?[]const u8, enabled: bool) !HistoryStore {
        var store = HistoryStore{
            .allocator = allocator,
            .path = null,
            .enabled = enabled,
            .entries = try std.ArrayList([]u8).initCapacity(allocator, 0),
        };

        if (path) |p| {
            store.path = try allocator.dupe(u8, p);
        }

        return store;
    }

    /// Clean up history store resources.
    pub fn deinit(self: *HistoryStore) void {
        // Close persistent append handle if open
        if (self.append_handle) |handle| {
            handle.close(compat.defaultIo());
            self.append_handle = null;
        }

        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.deinit(self.allocator);

        if (self.path) |p| {
            self.allocator.free(p);
        }
    }

    /// Load history from disk.
    /// Safe to call even if file doesn't exist.
    pub fn load(self: *HistoryStore) !void {
        if (!self.enabled or self.path == null) return;

        self.file_mutex.lock();
        defer self.file_mutex.unlock();

        var file = std.Io.Dir.cwd().openFile(compat.defaultIo(), self.path.?, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close(compat.defaultIo());

        // Read entire file
        const hio = compat.defaultIo();
        const file_size = try file.length(hio);
        const max_history_file_size: u64 = 64 * 1024 * 1024; // 64 MB
        if (file_size > max_history_file_size) return error.FileTooLarge;
        const content = try self.allocator.alloc(u8, @intCast(file_size));
        defer self.allocator.free(content);
        _ = try file.readPositionalAll(hio, content, 0);

        // Pre-allocate based on estimated line count to avoid geometric reallocs.
        // Average history line is ~40 bytes; cap at max_entries to avoid over-allocation.
        const estimated_lines: usize = @intCast(@min(file_size / 40, self.max_entries));
        try self.entries.ensureTotalCapacity(self.allocator, estimated_lines);

        // Two-pass approach: count non-empty lines first, then skip early
        // lines that would exceed max_entries. This avoids allocating strings
        // that are immediately freed when the file has more lines than the limit.
        var total_lines: usize = 0;
        {
            var count_it = std.mem.tokenizeScalar(u8, content, '\n');
            while (count_it.next()) |line| {
                if (line.len > 0) total_lines += 1;
            }
        }

        const skip = if (total_lines > self.max_entries) total_lines - self.max_entries else 0;

        var it = std.mem.tokenizeScalar(u8, content, '\n');
        var skipped: usize = 0;
        while (it.next()) |line| {
            if (line.len > 0) {
                if (skipped < skip) {
                    skipped += 1;
                    continue;
                }
                const entry = try self.allocator.dupe(u8, line);
                try self.entries.append(self.allocator, entry);
            }
        }
    }

    /// Append a line to history.
    ///
    /// Behavior:
    /// - Skips empty lines
    /// - Skips lines starting with space (privacy feature)
    /// - Skips consecutive duplicates
    /// - Persists to file if path is set
    pub fn append(self: *HistoryStore, line: []const u8) !void {
        if (!self.enabled) return;

        // Skip leading-space lines (privacy feature)
        if (line.len > 0 and line[0] == ' ') return;

        // Skip empty lines
        if (line.len == 0) return;

        // Check for duplicate (consecutive)
        if (self.entries.items.len > 0) {
            const last = self.entries.items[self.entries.items.len - 1];
            if (std.mem.eql(u8, last, line)) return;
        }

        // Global deduplication: remove any earlier exact match so the
        // entry appears only once at the end of history.  Uses a single
        // compacting pass — O(n) regardless of duplicate count (PF-022).
        if (self.deduplicate_global) {
            var write_idx: usize = 0;
            for (self.entries.items) |entry| {
                if (std.mem.eql(u8, entry, line)) {
                    self.allocator.free(entry);
                } else {
                    self.entries.items[write_idx] = entry;
                    write_idx += 1;
                }
            }
            self.entries.shrinkRetainingCapacity(write_idx);
        }

        // Add to memory
        const entry = try self.allocator.dupe(u8, line);
        try self.entries.append(self.allocator, entry);

        // Enforce max entries
        if (self.entries.items.len > self.max_entries) {
            const old = self.entries.orderedRemove(0);
            self.allocator.free(old);
        }

        // Persist to file using the persistent append handle
        if (self.path) |path| {
            self.file_mutex.lock();
            defer self.file_mutex.unlock();

            // Lazily open the file handle on first append
            if (self.append_handle == null) {
                // Ensure directory exists (once per session)
                if (!self.dir_ensured) {
                    if (std.fs.path.dirname(path)) |dir| {
                        std.Io.Dir.cwd().createDirPath(compat.defaultIo(), dir) catch {};
                    }
                    self.dir_ensured = true;
                }

                const file = std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = false, .permissions = @enumFromInt(0o600) }) catch |err| {
                    // If we can't save history, just continue without persisting
                    if (err == error.FileNotFound) return;
                    return err;
                };

                // createFile only applies `.permissions` when it *creates* the
                // file; a pre-existing file keeps its old (possibly 0o644)
                // mode. Re-tighten it explicitly (POSIX; no-op on Windows).
                if (comptime compat.has_executable_bit) {
                    compat.chmod(file, 0o600) catch {};
                }

                self.append_handle = file;
            }

            const file = self.append_handle.?;
            const aio = compat.defaultIo();
            // Append at end of file
            const end_pos = try file.length(aio);
            const line_with_nl = try self.allocator.alloc(u8, line.len + 1);
            defer self.allocator.free(line_with_nl);
            @memcpy(line_with_nl[0..line.len], line);
            line_with_nl[line.len] = '\n';
            _ = try file.writePositionalAll(aio, line_with_nl, end_pos);
        }
    }

    /// Clear all history (both in-memory and on disk).
    pub fn clear(self: *HistoryStore) !void {
        // Clear memory
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.clearRetainingCapacity();

        // Close the persistent append handle before truncating the file;
        // it will be lazily reopened on the next append.
        if (self.append_handle) |handle| {
            handle.close(compat.defaultIo());
            self.append_handle = null;
        }

        // Clear file
        if (self.path) |path| {
            self.file_mutex.lock();
            defer self.file_mutex.unlock();

            // Ensure directory exists
            if (std.fs.path.dirname(path)) |dir| {
                std.Io.Dir.cwd().createDirPath(compat.defaultIo(), dir) catch {};
            }

            const file = std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = true, .permissions = @enumFromInt(0o600) }) catch {
                return;
            };

            // createFile only applies `.permissions` on creation; re-tighten a
            // pre-existing file's mode explicitly (POSIX; no-op on Windows).
            if (comptime compat.has_executable_bit) {
                compat.chmod(file, 0o600) catch {};
            }

            file.close(compat.defaultIo());
        }
    }

    /// Search history for entries containing the pattern.
    /// Returns the most recent match, or null if not found.
    pub fn search(self: *HistoryStore, pattern: []const u8) ?[]const u8 {
        var i = self.entries.items.len;
        while (i > 0) : (i -= 1) {
            const entry = self.entries.items[i - 1];
            if (std.mem.indexOf(u8, entry, pattern)) |_| {
                return entry;
            }
        }
        return null;
    }

    /// Search history backwards from a given index.
    /// Returns the index and entry of the match, or null if not found.
    pub fn searchBackward(self: *HistoryStore, pattern: []const u8, start_index: ?usize) ?struct { index: usize, entry: []const u8 } {
        const start = start_index orelse self.entries.items.len;
        var i = start;
        while (i > 0) : (i -= 1) {
            const entry = self.entries.items[i - 1];
            if (std.mem.indexOf(u8, entry, pattern)) |_| {
                return .{ .index = i - 1, .entry = entry };
            }
        }
        return null;
    }

    /// Get a history entry by index.
    pub fn get(self: *HistoryStore, index: usize) ?[]const u8 {
        if (index >= self.entries.items.len) return null;
        return self.entries.items[index];
    }

    /// Get the number of history entries.
    pub fn count(self: *const HistoryStore) usize {
        return self.entries.items.len;
    }
};

/// Get the default history file path for the application.
///
/// Checks in order:
/// 1. APP_HISTORY environment variable (if app_name provided, validated for safety)
/// 2. ~/.{app_name}_history (primary)
/// 3. Platform-specific locations (fallback)
///
/// Parameters:
/// - allocator: Memory allocator for the path string
/// - app_name: Application name for history file naming
pub fn getDefaultHistoryPath(allocator: std.mem.Allocator, app_name: []const u8) ![]u8 {
    // Check environment variable first (APP_HISTORY)
    if (text_utils.resolveEnvOverridePath(allocator, app_name, "HISTORY")) |path| {
        return path;
    }

    // Primary: Try ~/.{app}_history as the default preference
    if (compat.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        var filename_buf: [256]u8 = undefined;
        const filename = std.fmt.bufPrint(&filename_buf, ".{s}_history", .{app_name}) catch ".repl_history";
        return std.fs.path.join(allocator, &[_][]const u8{ home, filename });
    } else |_| {}

    // Secondary: Use platform-specific conventions as fallback
    if (builtin.os.tag == .windows) {
        if (compat.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, app_name, "history" });
        } else |_| {}
    } else if (builtin.os.tag == .macos) {
        if (compat.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            return std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Application Support", app_name, "history" });
        } else |_| {}
    } else {
        // Linux/Unix - use XDG as secondary fallback
        if (compat.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg| {
            defer allocator.free(xdg);
            return std.fs.path.join(allocator, &[_][]const u8{ xdg, app_name, "history" });
        } else |_| {
            if (compat.getEnvVarOwned(allocator, "HOME")) |home| {
                defer allocator.free(home);
                return std.fs.path.join(allocator, &[_][]const u8{ home, ".local", "share", app_name, "history" });
            } else |_| {}
        }
    }

    // Final fallback
    var fallback_buf: [256]u8 = undefined;
    const fallback = std.fmt.bufPrint(&fallback_buf, ".{s}_history", .{app_name}) catch ".repl_history";
    return allocator.dupe(u8, fallback);
}

test "history leading-space suppression" {
    const allocator = std.testing.allocator;

    // Create temp file
    const path = "/tmp/test_repl_history.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    var hist = try HistoryStore.init(allocator, path, true);
    defer hist.deinit();

    // Append with leading space - should be ignored
    try hist.append(" SELECT 1;");
    try std.testing.expect(hist.entries.items.len == 0);

    // Append without leading space - should be saved
    try hist.append("SELECT 1;");
    try std.testing.expect(hist.entries.items.len == 1);
    try std.testing.expectEqualStrings("SELECT 1;", hist.entries.items[0]);
}

test "history duplicate suppression" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();

    try hist.append("command1");
    try hist.append("command1"); // Duplicate - should be ignored
    try hist.append("command2");
    try hist.append("command1"); // Not consecutive duplicate - should be added

    try std.testing.expect(hist.entries.items.len == 3);
}

test "history search" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();

    try hist.append("first command");
    try hist.append("second command");
    try hist.append("third entry");

    // Search for pattern
    const result = hist.search("command");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("second command", result.?);

    // Search for non-existent pattern
    const no_result = hist.search("nonexistent");
    try std.testing.expect(no_result == null);
}

test "history persistence" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_persist.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Create and populate history
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();

        try hist.append("line1");
        try hist.append("line2");
        try hist.append("line3");
    }

    // Load and verify
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.load();

        try std.testing.expect(hist.entries.items.len == 3);
        try std.testing.expectEqualStrings("line1", hist.entries.items[0]);
        try std.testing.expectEqualStrings("line2", hist.entries.items[1]);
        try std.testing.expectEqualStrings("line3", hist.entries.items[2]);
    }
}

test "history load trims excess entries from front in bulk" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_trim.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Write a history file with 10 lines
    {
        const file = try std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = true });
        defer file.close(compat.defaultIo());
        for (0..10) |i| {
            var buf: [32]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "entry{d}\n", .{i}) catch unreachable;
            try file.writeStreamingAll(compat.defaultIo(), line);
        }
    }

    // Load with max_entries = 3 -- should keep only the last 3
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        hist.max_entries = 3;
        try hist.load();

        try std.testing.expect(hist.entries.items.len == 3);
        try std.testing.expectEqualStrings("entry7", hist.entries.items[0]);
        try std.testing.expectEqualStrings("entry8", hist.entries.items[1]);
        try std.testing.expectEqualStrings("entry9", hist.entries.items[2]);
    }
}

test "history file permissions are 0o600" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_perms.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Append creates the file with restricted permissions
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.append("secret_command");
    }

    // Verify file permissions
    const stat = try std.Io.Dir.cwd().statFile(compat.defaultIo(), path, .{});
    // In 0.16.0, permissions is an enum; convert to mode_t for comparison
    const perm_bits = stat.permissions.toMode() & 0o777;
    try std.testing.expect(perm_bits == 0o600);
}

test "history append re-tightens pre-existing 0o644 file to 0o600" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    if (comptime !compat.has_executable_bit) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = compat.defaultIo();

    const path = "/tmp/test_repl_history_preexist_append.tmp";
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    // Pre-create the history file with a loose (0o644) mode.
    {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = true,
            .permissions = @enumFromInt(0o644),
        });
        file.close(io);
    }

    // Confirm it started looser than the target.
    {
        const stat0 = try std.Io.Dir.cwd().statFile(io, path, .{});
        try std.testing.expectEqual(@as(std.posix.mode_t, 0o644), stat0.permissions.toMode() & 0o777);
    }

    // Appending should re-tighten the pre-existing file.
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.append("secret_command");
    }

    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}

test "history clear re-tightens pre-existing 0o644 file to 0o600" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    if (comptime !compat.has_executable_bit) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = compat.defaultIo();

    const path = "/tmp/test_repl_history_preexist_clear.tmp";
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    // Pre-create the history file with a loose (0o644) mode.
    {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = true,
            .permissions = @enumFromInt(0o644),
        });
        file.close(io);
    }

    // Clearing should truncate AND re-tighten the pre-existing file.
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.clear();
    }

    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}

test "history clear file permissions are 0o600" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_clear_perms.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Create then clear
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.append("line1");
        try hist.clear();
    }

    // Verify file permissions after clear
    const stat = try std.Io.Dir.cwd().statFile(compat.defaultIo(), path, .{});
    const perm_bits = stat.permissions.toMode() & 0o777;
    try std.testing.expect(perm_bits == 0o600);
}

test "history load rejects file exceeding 64 MB" {
    // We cannot create a real 64 MB file in a unit test efficiently,
    // but we can test the boundary by creating a file slightly over
    // the limit using a sparse file (seek past end).
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_too_large.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Create a sparse file that appears to be > 64 MB
    {
        const file = try std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = true });
        defer file.close(compat.defaultIo());
        const over_limit: u64 = 64 * 1024 * 1024 + 1;
        _ = try file.writePositionalAll(compat.defaultIo(), "x", over_limit - 1);
    }

    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();

        const result = hist.load();
        try std.testing.expectError(error.FileTooLarge, result);
    }
}

test "history dir_ensured avoids redundant makePath" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_dir_ensured.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    var hist = try HistoryStore.init(allocator, path, true);
    defer hist.deinit();

    // Before any append, dir_ensured should be false
    try std.testing.expect(!hist.dir_ensured);

    try hist.append("first");
    // After first append, dir_ensured should be true
    try std.testing.expect(hist.dir_ensured);

    // Subsequent appends should still work with dir_ensured = true
    try hist.append("second");
    try std.testing.expect(hist.dir_ensured);
    try std.testing.expect(hist.entries.items.len == 2);
}

test "history global deduplication removes earlier duplicates" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    hist.deduplicate_global = true;

    try hist.append("alpha");
    try hist.append("beta");
    try hist.append("gamma");
    try hist.append("alpha"); // should remove the earlier "alpha"

    try std.testing.expectEqual(@as(usize, 3), hist.entries.items.len);
    try std.testing.expectEqualStrings("beta", hist.entries.items[0]);
    try std.testing.expectEqualStrings("gamma", hist.entries.items[1]);
    try std.testing.expectEqualStrings("alpha", hist.entries.items[2]);
}

test "history global deduplication off preserves non-consecutive duplicates" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    // deduplicate_global defaults to false

    try hist.append("alpha");
    try hist.append("beta");
    try hist.append("alpha"); // non-consecutive, kept when global dedup is off

    try std.testing.expectEqual(@as(usize, 3), hist.entries.items.len);
    try std.testing.expectEqualStrings("alpha", hist.entries.items[0]);
    try std.testing.expectEqualStrings("beta", hist.entries.items[1]);
    try std.testing.expectEqualStrings("alpha", hist.entries.items[2]);
}

test "history global deduplication handles multiple duplicates" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    hist.deduplicate_global = true;

    try hist.append("x");
    try hist.append("y");
    try hist.append("x");
    try hist.append("z");
    try hist.append("x"); // two earlier "x" entries should be removed

    try std.testing.expectEqual(@as(usize, 3), hist.entries.items.len);
    try std.testing.expectEqualStrings("y", hist.entries.items[0]);
    try std.testing.expectEqualStrings("z", hist.entries.items[1]);
    try std.testing.expectEqualStrings("x", hist.entries.items[2]);
}

test "history persistent handle: multiple appends persist correctly" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_persistent_handle.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Append several entries using the persistent handle
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();

        try hist.append("line1");
        try hist.append("line2");
        try hist.append("line3");

        // The handle should be open after the first append
        try std.testing.expect(hist.append_handle != null);
    }

    // Verify all entries persisted correctly by loading from disk
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.load();

        try std.testing.expectEqual(@as(usize, 3), hist.entries.items.len);
        try std.testing.expectEqualStrings("line1", hist.entries.items[0]);
        try std.testing.expectEqualStrings("line2", hist.entries.items[1]);
        try std.testing.expectEqualStrings("line3", hist.entries.items[2]);
    }
}

test "history persistent handle: clear then append persists correctly" {
    const allocator = std.testing.allocator;

    const path = "/tmp/test_repl_history_persistent_clear.tmp";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();

        try hist.append("before_clear");
        try std.testing.expect(hist.append_handle != null);

        // Clear closes the handle and truncates the file
        try hist.clear();
        try std.testing.expect(hist.append_handle == null);

        // Append after clear should reopen the handle
        try hist.append("after_clear");
        try std.testing.expect(hist.append_handle != null);
    }

    // Verify only the post-clear entry persisted
    {
        var hist = try HistoryStore.init(allocator, path, true);
        defer hist.deinit();
        try hist.load();

        try std.testing.expectEqual(@as(usize, 1), hist.entries.items.len);
        try std.testing.expectEqualStrings("after_clear", hist.entries.items[0]);
    }
}

test "history persistent handle: no handle opened without path" {
    const allocator = std.testing.allocator;

    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();

    try hist.append("memory_only");
    try std.testing.expect(hist.append_handle == null);
    try std.testing.expectEqual(@as(usize, 1), hist.entries.items.len);
}

// QF-100 (#156): boundary coverage for the public HistoryStore API.

test "QF-100: get returns null for out-of-range index" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("one");
    try std.testing.expect(hist.get(0) != null);
    try std.testing.expect(hist.get(1) == null);
    try std.testing.expect(hist.get(9999) == null);
    try std.testing.expectEqual(@as(usize, 1), hist.count());
}

test "QF-100: searchBackward empty pattern matches most recent entry" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("alpha");
    try hist.append("beta");
    // indexOf(_, "") returns 0, so an empty pattern matches any entry; the
    // backward scan returns the most recent (highest index).
    const result = hist.searchBackward("", null);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("beta", result.?.entry);
    try std.testing.expectEqual(@as(usize, 1), result.?.index);
}

test "QF-100: searchBackward start_index boundaries" {
    const allocator = std.testing.allocator;
    var hist = try HistoryStore.init(allocator, null, true);
    defer hist.deinit();
    try hist.append("match one"); // index 0
    try hist.append("other"); // index 1
    try hist.append("match two"); // index 2

    // Default start: most recent match.
    const recent = hist.searchBackward("match", null);
    try std.testing.expect(recent != null);
    try std.testing.expectEqualStrings("match two", recent.?.entry);

    // start_index is the exclusive upper bound of the backward scan, so
    // start_index == 1 scans only index 0.
    const from_one = hist.searchBackward("match", 1);
    try std.testing.expect(from_one != null);
    try std.testing.expectEqualStrings("match one", from_one.?.entry);
    try std.testing.expectEqual(@as(usize, 0), from_one.?.index);

    // start_index == 0 scans nothing.
    try std.testing.expect(hist.searchBackward("match", 0) == null);

    // No match anywhere.
    try std.testing.expect(hist.searchBackward("absent", null) == null);

    // Empty store.
    var empty = try HistoryStore.init(allocator, null, true);
    defer empty.deinit();
    try std.testing.expect(empty.searchBackward("x", null) == null);
    try std.testing.expectEqual(@as(usize, 0), empty.count());
}

// isPathSafe tests are in text_utils.zig (canonical location)
