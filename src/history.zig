// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Command history management
//!
//! Provides persistent command history with support for:
//! - In-memory history during session
//! - Persistent storage to disk
//! - Duplicate detection
//! - Privacy (skip lines starting with space)
//! - Search functionality

const std = @import("std");
const builtin = @import("builtin");

/// Manages command history with optional persistence.
pub const HistoryStore = struct {
    allocator: std.mem.Allocator,
    path: ?[]u8,
    enabled: bool,
    entries: std.ArrayList([]u8),
    max_entries: usize = 5000,
    file_mutex: std.Thread.Mutex = .{},

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

        const file = std.fs.cwd().openFile(self.path.?, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        // Read entire file
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, @intCast(file_size));
        defer self.allocator.free(content);
        _ = try file.read(content);

        // Split into lines
        var it = std.mem.tokenizeScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (line.len > 0) {
                const entry = try self.allocator.dupe(u8, line);
                try self.entries.append(self.allocator, entry);

                // Enforce max entries
                if (self.entries.items.len > self.max_entries) {
                    const old = self.entries.orderedRemove(0);
                    self.allocator.free(old);
                }
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

        // Add to memory
        const entry = try self.allocator.dupe(u8, line);
        try self.entries.append(self.allocator, entry);

        // Enforce max entries
        if (self.entries.items.len > self.max_entries) {
            const old = self.entries.orderedRemove(0);
            self.allocator.free(old);
        }

        // Persist to file
        if (self.path) |path| {
            self.file_mutex.lock();
            defer self.file_mutex.unlock();

            // Ensure directory exists
            if (std.fs.path.dirname(path)) |dir| {
                std.fs.cwd().makePath(dir) catch {};
            }

            const file = std.fs.cwd().createFile(path, .{ .truncate = false }) catch |err| {
                // If we can't save history, just continue without persisting
                if (err == error.FileNotFound) return;
                return err;
            };
            defer file.close();

            try file.seekFromEnd(0);
            try file.writeAll(line);
            try file.writeAll("\n");
        }
    }

    /// Clear all history (both in-memory and on disk).
    pub fn clear(self: *HistoryStore) !void {
        // Clear memory
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.clearRetainingCapacity();

        // Clear file
        if (self.path) |path| {
            self.file_mutex.lock();
            defer self.file_mutex.unlock();

            // Ensure directory exists
            if (std.fs.path.dirname(path)) |dir| {
                std.fs.cwd().makePath(dir) catch {};
            }

            const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch {
                return;
            };
            file.close();
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
/// 1. APP_HISTORY environment variable (if app_name provided)
/// 2. ~/.{app_name}_history (primary)
/// 3. Platform-specific locations (fallback)
///
/// Parameters:
/// - allocator: Memory allocator for the path string
/// - app_name: Application name for history file naming
pub fn getDefaultHistoryPath(allocator: std.mem.Allocator, app_name: []const u8) ![]u8 {
    // Check environment variable first (APP_HISTORY)
    var env_name_buf: [256]u8 = undefined;
    const env_name = std.ascii.upperString(&env_name_buf, app_name);
    var full_env_name: [512]u8 = undefined;
    const full_name = std.fmt.bufPrint(&full_env_name, "{s}_HISTORY", .{env_name}) catch app_name;
    if (std.process.getEnvVarOwned(allocator, full_name)) |path| {
        return path;
    } else |_| {}

    // Primary: Try ~/.{app}_history as the default preference
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        var filename_buf: [256]u8 = undefined;
        const filename = std.fmt.bufPrint(&filename_buf, ".{s}_history", .{app_name}) catch ".repl_history";
        return std.fs.path.join(allocator, &[_][]const u8{ home, filename });
    } else |_| {}

    // Secondary: Use platform-specific conventions as fallback
    if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, app_name, "history" });
        } else |_| {}
    } else if (builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            return std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Application Support", app_name, "history" });
        } else |_| {}
    } else {
        // Linux/Unix - use XDG as secondary fallback
        if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg| {
            defer allocator.free(xdg);
            return std.fs.path.join(allocator, &[_][]const u8{ xdg, app_name, "history" });
        } else |_| {
            if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
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
    defer std.fs.cwd().deleteFile(path) catch {};

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
    defer std.fs.cwd().deleteFile(path) catch {};

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
