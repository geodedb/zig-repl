// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Zig 0.15 → 0.16 migration shim (TEMPORARY)
//!
//! Bridges the 0.15 → 0.16 API gap for filesystem, I/O, and environment
//! access. All helpers in this module use the global single-threaded Io
//! instance so callers do not need to thread an Io parameter.
//!
//! WARNING: This module is a temporary migration shim and is expected to be
//! retired once the codebase migrates fully onto the native 0.16 `std.Io`
//! APIs. New callers SHOULD prefer the native `std.Io.File` / `std.Io.Dir`
//! APIs directly and AVOID adding new dependencies on these helpers. See
//! GAP_ANALYSIS.md (compat shim deprecation) for the tracking record.

const std = @import("std");
const builtin = @import("builtin");

pub const File = std.Io.File;
pub const Dir = std.Io.Dir;

/// Return the default Io backed by the global single-threaded instance.
pub fn defaultIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

// =========================================================================
// File helpers — drop-in replacements for the old std.fs.File methods
// =========================================================================

/// Write all bytes to a file (replacement for old file.writeAll).
pub fn writeAll(file: File, data: []const u8) !void {
    return file.writeStreamingAll(defaultIo(), data);
}

/// Read all available bytes from a file into an allocator-owned buffer
/// (replacement for old file.readToEndAlloc).
pub fn readToEndAlloc(file: File, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    const len_u64 = try file.length(defaultIo());
    const len: usize = @intCast(@min(len_u64, max_bytes));
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    const n = try file.readPositionalAll(defaultIo(), buf, 0);
    return buf[0..n];
}

/// Set file permissions (replacement for old file.chmod).
///
/// On POSIX this performs a real `fchmod`-equivalent via
/// `std.Io.File.setPermissions`, so callers can re-tighten the mode of an
/// already-open file (e.g. a pre-existing config/history file that was
/// created with looser permissions). On Windows there is no POSIX mode, so
/// this is a documented no-op.
pub fn chmod(file: File, mode: std.posix.mode_t) !void {
    if (builtin.os.tag == .windows) {
        // Windows has no POSIX permission bits; nothing to do.
        return;
    }
    try file.setPermissions(defaultIo(), std.Io.File.Permissions.fromMode(mode));
}

/// Read from a file into a buffer (replacement for old file.read).
/// Uses the streaming read API since stdin is a non-seekable stream.
pub fn read(file: File, buffer: []u8) !usize {
    return file.readStreaming(defaultIo(), &.{buffer});
}

// =========================================================================
// Directory helpers
// =========================================================================

/// Create a file relative to cwd (replacement for std.fs.cwd().createFile).
///
/// Forwards the relevant 0.16 `CreateFileOptions` fields so the returned
/// `File` honors the caller's intent (e.g. `.read = true` keeps the handle
/// readable). `flags` is a struct literal that may set any of `read`,
/// `truncate`, `exclusive`, or `permissions`; omitted fields fall back to the
/// 0.16 defaults.
pub fn cwdCreateFile(sub_path: []const u8, flags: anytype) !File {
    const T = @TypeOf(flags);
    return Dir.cwd().createFile(defaultIo(), sub_path, .{
        .read = if (@hasField(T, "read")) flags.read else false,
        .truncate = if (@hasField(T, "truncate")) flags.truncate else true,
        .exclusive = if (@hasField(T, "exclusive")) flags.exclusive else false,
        .permissions = if (@hasField(T, "permissions")) flags.permissions else .default_file,
    });
}

// =========================================================================
// Environment helpers
// =========================================================================

/// Get environment variable (replacement for std.posix.getenv).
/// On POSIX, uses libc getenv. On Windows, uses the wide-string API.
pub fn getenv(name: [*:0]const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        return null; // Use getenvW on Windows instead
    } else {
        const result = std.c.getenv(name) orelse return null;
        return std.mem.sliceTo(result, 0);
    }
}

/// Maximum environment-variable name length (excludes the NUL terminator).
const max_env_name_len = 255;

/// Get environment variable by Zig slice name.
/// Converts to null-terminated string using a static buffer.
pub fn getenvSlice(name: []const u8) ?[]const u8 {
    if (name.len >= max_env_name_len) return null;
    var buf: [max_env_name_len + 1]u8 = undefined;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const name_z: [*:0]const u8 = buf[0..name.len :0];
    return getenv(name_z);
}

/// Get an owned copy of an environment variable value (replacement for
/// std.process.getEnvVarOwned). Returns error.EnvironmentVariableNotFound
/// when the variable is not set.
pub fn getEnvVarOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const value = getenvSlice(name) orelse return error.EnvironmentVariableNotFound;
    return allocator.dupe(u8, value);
}

// =========================================================================
// TTY detection
// =========================================================================

/// Check if a file descriptor is a TTY (replacement for std.posix.isatty).
pub fn isatty(fd: std.posix.fd_t) bool {
    if (builtin.os.tag == .windows) {
        return false; // Handled separately via GetConsoleMode
    } else {
        return std.c.isatty(fd) != 0;
    }
}

// =========================================================================
// Mutex
// =========================================================================

/// A simple spinlock mutex that doesn't require Io for locking.
/// Replacement for the removed std.Thread.Mutex.
pub const Mutex = struct {
    state: std.atomic.Value(u8) = .init(0),

    pub const init: Mutex = .{ .state = .init(0) };

    pub fn lock(self: *Mutex) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.state.store(0, .release);
    }
};

// =========================================================================
// fixedBufferStream replacement
// =========================================================================

/// A simple in-memory stream that writes into a fixed buffer.
/// Replacement for the removed std.io.fixedBufferStream.
pub const FixedBufferStream = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn init(buf: []u8) FixedBufferStream {
        return .{ .buf = buf };
    }

    pub fn writer(self: *FixedBufferStream) Writer {
        return .{ .fbs = self };
    }

    pub fn getWritten(self: *const FixedBufferStream) []const u8 {
        return self.buf[0..self.pos];
    }

    pub const Writer = struct {
        fbs: *FixedBufferStream,

        pub fn writeAll(self: Writer, data: []const u8) error{NoSpaceLeft}!void {
            if (self.fbs.pos + data.len > self.fbs.buf.len) {
                return error.NoSpaceLeft;
            }
            @memcpy(self.fbs.buf[self.fbs.pos..][0..data.len], data);
            self.fbs.pos += data.len;
        }

        pub fn print(self: Writer, comptime fmt: []const u8, args: anytype) error{NoSpaceLeft}!void {
            const remaining = self.fbs.buf[self.fbs.pos..];
            const result = std.fmt.bufPrint(remaining, fmt, args) catch return error.NoSpaceLeft;
            self.fbs.pos += result.len;
        }
    };
};

// =========================================================================
// fs.path compat
// =========================================================================

pub const path = std.Io.Dir.path;

/// Check whether the filesystem supports executable permission bits.
pub const has_executable_bit = std.Io.File.Permissions.has_executable_bit;

// =========================================================================
// Tests
// =========================================================================

test "chmod re-tightens an existing file's mode (POSIX)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    if (comptime !has_executable_bit) return error.SkipZigTest;

    const io = defaultIo();
    const test_path = "/tmp/test_compat_chmod.tmp";
    defer Dir.cwd().deleteFile(io, test_path) catch {};

    // Create a file with a loose (0o644) mode.
    {
        const file = try Dir.cwd().createFile(io, test_path, .{
            .truncate = true,
            .permissions = @enumFromInt(0o644),
        });
        defer file.close(io);
    }

    // Sanity-check it started looser than the target.
    {
        const stat0 = try Dir.cwd().statFile(io, test_path, .{});
        try std.testing.expectEqual(@as(std.posix.mode_t, 0o644), stat0.permissions.toMode() & 0o777);
    }

    // Re-tighten via compat.chmod on the open handle.
    {
        const file = try Dir.cwd().openFile(io, test_path, .{ .mode = .read_write });
        defer file.close(io);
        try chmod(file, 0o600);
    }

    const stat = try Dir.cwd().statFile(io, test_path, .{});
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}
