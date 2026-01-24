// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Configuration management
//!
//! Handles REPL configuration including:
//! - Runtime settings
//! - Persistent configuration files
//! - Platform-specific config paths

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");

/// REPL configuration options.
pub const Config = struct {
    /// Keybinding mode
    keymap: Keymap = .emacs,
    /// Output format
    format: Format = .text,
    /// Enable command history
    history_enabled: bool = true,
    /// Show timing information
    timing_enabled: bool = false,
    /// Verbose output mode
    verbose: bool = false,
    /// Enable color output
    colors_enabled: bool = true,
    /// Maximum history entries
    max_history: usize = 5000,

    pub const Keymap = enum {
        emacs,
        vi,

        pub fn fromString(s: []const u8) ?Keymap {
            if (std.mem.eql(u8, s, "emacs")) return .emacs;
            if (std.mem.eql(u8, s, "vi")) return .vi;
            if (std.mem.eql(u8, s, "vim")) return .vi;
            return null;
        }
    };

    pub const Format = enum {
        text,
        json,
        csv,
        table,

        pub fn fromString(s: []const u8) ?Format {
            if (std.mem.eql(u8, s, "text")) return .text;
            if (std.mem.eql(u8, s, "json")) return .json;
            if (std.mem.eql(u8, s, "csv")) return .csv;
            if (std.mem.eql(u8, s, "table")) return .table;
            return null;
        }
    };

    /// Load configuration with default values, checking environment.
    pub fn loadDefault() Config {
        var config = Config{};
        config.colors_enabled = platform.shouldUseColor();
        return config;
    }

    /// Load configuration from a file.
    /// Falls back to defaults if file doesn't exist.
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var config = Config{};
        config.colors_enabled = platform.shouldUseColor();

        const file = std.fs.cwd().openFile(path, .{}) catch {
            return config;
        };
        defer file.close();

        // Parse simple key=value format
        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
                const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
                const value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

                if (std.mem.eql(u8, key, "keymap") or std.mem.eql(u8, key, "repl.keymap")) {
                    if (Keymap.fromString(value)) |km| {
                        config.keymap = km;
                    }
                } else if (std.mem.eql(u8, key, "format") or std.mem.eql(u8, key, "repl.format")) {
                    if (Format.fromString(value)) |fmt| {
                        config.format = fmt;
                    }
                } else if (std.mem.eql(u8, key, "history") or std.mem.eql(u8, key, "repl.history")) {
                    config.history_enabled = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
                } else if (std.mem.eql(u8, key, "timing") or std.mem.eql(u8, key, "repl.timing")) {
                    config.timing_enabled = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
                } else if (std.mem.eql(u8, key, "verbose") or std.mem.eql(u8, key, "repl.verbose")) {
                    config.verbose = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
                } else if (std.mem.eql(u8, key, "colors") or std.mem.eql(u8, key, "repl.colors")) {
                    config.colors_enabled = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
                } else if (std.mem.eql(u8, key, "max_history") or std.mem.eql(u8, key, "repl.max_history")) {
                    config.max_history = std.fmt.parseInt(usize, value, 10) catch config.max_history;
                }
            }
        }

        return config;
    }

    /// Save configuration to a file.
    pub fn saveToFile(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        // Ensure directory exists
        const dir_path = std.fs.path.dirname(path) orelse ".";
        try std.fs.cwd().makePath(dir_path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        try writer.print("# REPL Configuration\n", .{});
        try writer.print("keymap={s}\n", .{@tagName(self.keymap)});
        try writer.print("format={s}\n", .{@tagName(self.format)});
        try writer.print("history={s}\n", .{if (self.history_enabled) "true" else "false"});
        try writer.print("timing={s}\n", .{if (self.timing_enabled) "true" else "false"});
        try writer.print("verbose={s}\n", .{if (self.verbose) "true" else "false"});
        try writer.print("colors={s}\n", .{if (self.colors_enabled) "true" else "false"});
        try writer.print("max_history={d}\n", .{self.max_history});

        try file.writeAll(fbs.getWritten());
        _ = allocator;
    }
};

/// Get the default configuration file path for the application.
pub fn getDefaultConfigPath(allocator: std.mem.Allocator, app_name: []const u8) ![]u8 {
    // Check environment variable first (APP_CONFIG)
    var env_name_buf: [256]u8 = undefined;
    const env_name = std.ascii.upperString(&env_name_buf, app_name);
    var full_env_name: [512]u8 = undefined;
    const full_name = std.fmt.bufPrint(&full_env_name, "{s}_CONFIG", .{env_name}) catch app_name;
    if (std.process.getEnvVarOwned(allocator, full_name)) |path| {
        return path;
    } else |_| {}

    // Use platform-specific conventions
    if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, app_name, "config" });
        } else |_| {}
    } else if (builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            var filename_buf: [256]u8 = undefined;
            const filename = std.fmt.bufPrint(&filename_buf, "{s}.conf", .{app_name}) catch "repl.conf";
            return std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Preferences", filename });
        } else |_| {}
    } else {
        // Linux/Unix - use XDG
        if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
            defer allocator.free(xdg);
            return std.fs.path.join(allocator, &[_][]const u8{ xdg, app_name, "config" });
        } else |_| {
            if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
                defer allocator.free(home);
                return std.fs.path.join(allocator, &[_][]const u8{ home, ".config", app_name, "config" });
            } else |_| {}
        }
    }

    // Fallback
    var fallback_buf: [256]u8 = undefined;
    const fallback = std.fmt.bufPrint(&fallback_buf, ".{s}_config", .{app_name}) catch ".repl_config";
    return allocator.dupe(u8, fallback);
}

test "config default" {
    const config = Config.loadDefault();
    try std.testing.expect(config.keymap == .emacs);
    try std.testing.expect(config.history_enabled);
    try std.testing.expect(!config.timing_enabled);
}

test "keymap from string" {
    try std.testing.expect(Config.Keymap.fromString("emacs") == .emacs);
    try std.testing.expect(Config.Keymap.fromString("vi") == .vi);
    try std.testing.expect(Config.Keymap.fromString("vim") == .vi);
    try std.testing.expect(Config.Keymap.fromString("invalid") == null);
}

test "format from string" {
    try std.testing.expect(Config.Format.fromString("text") == .text);
    try std.testing.expect(Config.Format.fromString("json") == .json);
    try std.testing.expect(Config.Format.fromString("csv") == .csv);
    try std.testing.expect(Config.Format.fromString("table") == .table);
    try std.testing.expect(Config.Format.fromString("invalid") == null);
}
