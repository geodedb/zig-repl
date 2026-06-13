// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Configuration management
//!
//! Handles application-level REPL configuration including:
//! - Persistent settings saved to and loaded from a config file
//! - Platform-specific config file path resolution
//! - Runtime preference defaults (keymap, format, history, colors)
//!
//! ## Config vs Repl.Options
//!
//! `Config` and `Repl.Options` (defined in `core.zig`) serve different purposes
//! and are separate by design:
//!
//! - **`Config`** is for application-level persistence. It supports `loadFromFile()`
//!   and `saveToFile()` for reading/writing a key=value config file. It contains
//!   preferences like `max_history`, `colors_enabled`, and `timing_enabled` that
//!   are relevant to the host application rather than the REPL core.
//!
//! - **`Repl.Options`** is for REPL initialization. It is passed to `Repl.run()` and
//!   contains the allocator, callbacks (`run_fn`, `complete_fn`, `welcome_fn`), and
//!   session settings (`prompt`, `keymap`, `history_path`).
//!
//! `Config` is **not** auto-loaded by `Repl.run()`. Applications that want config
//! file support should:
//!
//! 1. Load a `Config` via `Config.loadFromFile()` or `Config.loadDefault()`
//! 2. Map relevant fields to `Repl.Options` (e.g., `config.keymap` -> `options.keymap`,
//!    `config.max_history` -> `options.max_history`)
//! 3. Pass the `Options` to `Repl.run()`

const std = @import("std");
const compat = @import("compat.zig");
const builtin = @import("builtin");
const text_utils = @import("text_utils.zig");
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

        /// Convert a string ("emacs", "vi", or "vim") to the corresponding Keymap value, or null if unrecognized.
        pub fn fromString(s: []const u8) ?Keymap {
            if (std.mem.eql(u8, s, "emacs")) return .emacs;
            if (std.mem.eql(u8, s, "vi")) return .vi;
            if (std.mem.eql(u8, s, "vim")) return .vi;
            return null;
        }
    };

    /// Output format selection.
    ///
    /// Available for consumers to select output formatting in their applications.
    /// Not used internally by the REPL core, but part of the public configuration API.
    pub const Format = enum {
        text,
        json,
        csv,
        table,

        /// Convert a string to the corresponding Format value, or null if unrecognized.
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
    ///
    /// This is a consumer-facing API: the REPL core does not call it internally.
    /// Applications should call this to load persisted settings, then map the
    /// relevant fields to `Repl.Options` before calling `Repl.run()`.
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var config = Config{};
        config.colors_enabled = platform.shouldUseColor();

        const cio = compat.defaultIo();
        var file = std.Io.Dir.cwd().openFile(cio, path, .{}) catch {
            return config;
        };
        defer file.close(cio);

        // Parse simple key=value format
        const content = try std.Io.Dir.cwd().readFileAlloc(cio, path, allocator, @enumFromInt(1024 * 1024));
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
    ///
    /// This is a consumer-facing API: the REPL core does not call it internally.
    /// Applications can use this to persist user preferences between sessions.
    ///
    /// The `allocator` parameter is currently unused but reserved for future use
    /// (e.g., format conversion, dynamic value serialization). It is kept in the
    /// signature to avoid a breaking API change when that functionality is added.
    pub fn saveToFile(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        // Ensure directory exists
        const cio = compat.defaultIo();
        const dir_path = std.fs.path.dirname(path) orelse ".";
        try std.Io.Dir.cwd().createDirPath(cio, dir_path);

        // Serialize the config into a fixed buffer first.
        var buf: [4096]u8 = undefined;
        var fbs: compat.FixedBufferStream = .init(&buf);
        const writer = fbs.writer();

        try writer.print("# REPL Configuration\n", .{});
        try writer.print("keymap={s}\n", .{@tagName(self.keymap)});
        try writer.print("format={s}\n", .{@tagName(self.format)});
        try writer.print("history={s}\n", .{if (self.history_enabled) "true" else "false"});
        try writer.print("timing={s}\n", .{if (self.timing_enabled) "true" else "false"});
        try writer.print("verbose={s}\n", .{if (self.verbose) "true" else "false"});
        try writer.print("colors={s}\n", .{if (self.colors_enabled) "true" else "false"});
        try writer.print("max_history={d}\n", .{self.max_history});

        // Atomic write: write the full payload to a sibling temp file created
        // with restrictive (0o600) permissions, then rename it over the real
        // path. This guarantees the on-disk config is never world-readable and
        // is never left half-written if the process dies mid-write (Q7).
        const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
        defer allocator.free(tmp_path);

        // If a previous run left a stale temp file behind, remove it so the
        // exclusive-free createFile below starts from a clean slate.
        errdefer std.Io.Dir.cwd().deleteFile(cio, tmp_path) catch {};

        {
            var tmp_file = try std.Io.Dir.cwd().createFile(cio, tmp_path, .{
                .truncate = true,
                .permissions = @enumFromInt(0o600),
            });
            defer tmp_file.close(cio);

            // createFile only applies `.permissions` when it creates the file;
            // re-tighten in case a stale temp file pre-existed (POSIX; no-op
            // on Windows).
            if (comptime std.Io.File.Permissions.has_executable_bit) {
                compat.chmod(tmp_file, 0o600) catch {};
            }

            try tmp_file.writeStreamingAll(cio, fbs.getWritten());
        }

        // Atomically replace the destination. rename() is atomic on POSIX and
        // overwrites an existing target, so readers never observe a partial
        // file and the 0o600 mode is carried over to the final path.
        try std.Io.Dir.cwd().rename(tmp_path, std.Io.Dir.cwd(), path, cio);
    }
};

/// Get the default configuration file path for the application.
///
/// This is a consumer-facing API: the REPL core does not call it internally.
/// Applications can use this with `Config.loadFromFile()` / `Config.saveToFile()`
/// to resolve platform-appropriate config file locations.
///
/// Resolution order:
/// 1. `$<APP_NAME>_CONFIG` environment variable (validated for safety)
/// 2. Platform-specific directory (XDG on Linux, ~/Library/Preferences on macOS, %APPDATA% on Windows)
/// 3. Fallback to `.<app_name>_config` in the current directory
pub fn getDefaultConfigPath(allocator: std.mem.Allocator, app_name: []const u8) ![]u8 {
    // Check environment variable first (APP_CONFIG)
    if (text_utils.resolveEnvOverridePath(allocator, app_name, "CONFIG")) |path| {
        return path;
    }

    // Use platform-specific conventions
    if (builtin.os.tag == .windows) {
        if (compat.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, app_name, "config" });
        } else |_| {}
    } else if (builtin.os.tag == .macos) {
        if (compat.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            var filename_buf: [256]u8 = undefined;
            const filename = std.fmt.bufPrint(&filename_buf, "{s}.conf", .{app_name}) catch "repl.conf";
            return std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Preferences", filename });
        } else |_| {}
    } else {
        // Linux/Unix - use XDG
        if (compat.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
            defer allocator.free(xdg);
            return std.fs.path.join(allocator, &[_][]const u8{ xdg, app_name, "config" });
        } else |_| {
            if (compat.getEnvVarOwned(allocator, "HOME")) |home| {
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

test "loadFromFile with valid config" {
    const allocator = std.testing.allocator;
    const path = "/tmp/test_repl_config_valid.conf";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Write a known config file
    {
        const file = try std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = true });
        defer file.close(compat.defaultIo());
        try file.writeStreamingAll(compat.defaultIo(),
            \\# Test config
            \\keymap=vi
            \\format=json
            \\history=false
            \\timing=true
            \\verbose=true
            \\colors=false
            \\max_history=1000
            \\
        );
    }

    const config = try Config.loadFromFile(allocator, path);
    try std.testing.expect(config.keymap == .vi);
    try std.testing.expect(config.format == .json);
    try std.testing.expect(!config.history_enabled);
    try std.testing.expect(config.timing_enabled);
    try std.testing.expect(config.verbose);
    try std.testing.expect(!config.colors_enabled);
    try std.testing.expect(config.max_history == 1000);
}

test "loadFromFile with missing file" {
    const allocator = std.testing.allocator;

    const config = try Config.loadFromFile(allocator, "/tmp/nonexistent_repl_config_98237.conf");
    // Should return defaults
    try std.testing.expect(config.keymap == .emacs);
    try std.testing.expect(config.history_enabled);
    try std.testing.expect(!config.timing_enabled);
    try std.testing.expect(!config.verbose);
    try std.testing.expect(config.max_history == 5000);
}

test "loadFromFile with malformed content" {
    const allocator = std.testing.allocator;
    const path = "/tmp/test_repl_config_malformed.conf";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Write lines without '=', empty lines, unknown keys
    {
        const file = try std.Io.Dir.cwd().createFile(compat.defaultIo(), path, .{ .truncate = true });
        defer file.close(compat.defaultIo());
        try file.writeStreamingAll(compat.defaultIo(),
            \\this line has no equals
            \\
            \\unknown_key=some_value
            \\# comment line
            \\keymap=vi
            \\format=invalid_format
            \\max_history=not_a_number
            \\
        );
    }

    const config = try Config.loadFromFile(allocator, path);
    // Only valid key=value pairs should be applied
    try std.testing.expect(config.keymap == .vi);
    // Invalid format should be ignored, keeping default
    try std.testing.expect(config.format == .text);
    // Invalid max_history should be ignored, keeping default
    try std.testing.expect(config.max_history == 5000);
}

test "saveToFile creates valid config" {
    const allocator = std.testing.allocator;
    const path = "/tmp/test_repl_config_save.conf";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    var config = Config{};
    config.keymap = .vi;
    config.format = .csv;
    config.timing_enabled = true;
    config.max_history = 2000;

    try config.saveToFile(allocator, path);

    // Read back the raw file content and verify expected key=value pairs
    var file = std.Io.Dir.cwd().openFile(compat.defaultIo(), path, .{}) catch return;
    defer file.close(compat.defaultIo());
    const content = try compat.readToEndAlloc(file, allocator, 1024 * 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "keymap=vi") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "format=csv") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "timing=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "max_history=2000") != null);
}

test "saveToFile and loadFromFile round-trip" {
    const allocator = std.testing.allocator;
    const path = "/tmp/test_repl_config_roundtrip.conf";
    defer std.Io.Dir.cwd().deleteFile(compat.defaultIo(), path) catch {};

    // Save a non-default config
    var original = Config{};
    original.keymap = .vi;
    original.format = .table;
    original.history_enabled = false;
    original.timing_enabled = true;
    original.verbose = true;
    original.colors_enabled = false;
    original.max_history = 999;

    try original.saveToFile(allocator, path);

    // Load it back
    const loaded = try Config.loadFromFile(allocator, path);

    try std.testing.expect(loaded.keymap == .vi);
    try std.testing.expect(loaded.format == .table);
    try std.testing.expect(!loaded.history_enabled);
    try std.testing.expect(loaded.timing_enabled);
    try std.testing.expect(loaded.verbose);
    try std.testing.expect(!loaded.colors_enabled);
    try std.testing.expect(loaded.max_history == 999);
}

test "saveToFile creates config with 0o600 permissions" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    if (comptime !std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = compat.defaultIo();
    const path = "/tmp/test_repl_config_perms.conf";
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    var config = Config{};
    config.keymap = .vi;
    try config.saveToFile(allocator, path);

    // The final config file must be created with restrictive permissions
    // (run under the default umask), not world-readable.
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}

test "saveToFile is atomic and leaves no lingering temp file" {
    const allocator = std.testing.allocator;
    const io = compat.defaultIo();
    const path = "/tmp/test_repl_config_atomic.conf";
    const tmp_path = "/tmp/test_repl_config_atomic.conf.tmp";
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, tmp_path) catch {};

    var config = Config{};
    config.keymap = .vi;
    config.max_history = 1234;
    try config.saveToFile(allocator, path);

    // The temp file used during the atomic write must not linger.
    const tmp_exists = blk: {
        var f = std.Io.Dir.cwd().openFile(io, tmp_path, .{}) catch break :blk false;
        f.close(io);
        break :blk true;
    };
    try std.testing.expect(!tmp_exists);

    // The real config must round-trip.
    const loaded = try Config.loadFromFile(allocator, path);
    try std.testing.expect(loaded.keymap == .vi);
    try std.testing.expect(loaded.max_history == 1234);
}

test "getDefaultConfigPath returns valid path" {
    const allocator = std.testing.allocator;

    const path = try getDefaultConfigPath(allocator, "test_app");
    defer allocator.free(path);

    try std.testing.expect(path.len > 0);
}

// isPathSafe tests are in text_utils.zig (canonical location)
