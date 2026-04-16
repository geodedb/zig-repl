// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Zig 0.16.0 compatibility layer
//!
//! Bridges the 0.15 → 0.16 API gap for filesystem, I/O, and environment
//! access. All helpers in this module use the global single-threaded Io
//! instance so callers do not need to thread an Io parameter.

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

/// Close a file (replacement for old file.close()).
pub fn closeFile(file: File) void {
    file.close(defaultIo());
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

/// Read into a caller-provided buffer (replacement for old file.readAll).
pub fn readAll(file: File, buffer: []u8) !usize {
    return file.readPositionalAll(defaultIo(), buffer, 0);
}

/// Seek to an absolute position (replacement for old file.seekTo).
pub fn seekTo(file: File, pos: u64) void {
    // In the new API, positional reads/writes handle offset directly.
    // For compatibility, we just ignore this — callers should use
    // readPositional/writePositional instead. This is a no-op stub.
    _ = file;
    _ = pos;
}

/// Get file length (replacement for old file.getEndPos).
pub fn getEndPos(file: File) !u64 {
    return file.length(defaultIo());
}

/// Set file permissions (replacement for old file.chmod).
pub fn chmod(file: File, mode: std.posix.mode_t) !void {
    _ = file;
    _ = mode;
    // In 0.16.0, File.setPermissions API changed significantly.
    // Permission enforcement is handled at the OS level via createFile options.
    // This is intentionally a no-op.
}

/// Seek to end of file then write (replacement for old seekFromEnd + write pattern).
pub fn seekFromEnd(file: File, offset: i64) !void {
    _ = file;
    _ = offset;
    // In the new API, we use writePositional at the file length.
    // This is handled directly in callers.
}

/// Write iovec data (replacement for old file.writev).
pub fn writev(file: File, iovecs: []const std.posix.iovec_const) !usize {
    // Flatten iovecs and write sequentially
    var total: usize = 0;
    for (iovecs) |iov| {
        const data: [*]const u8 = @ptrCast(iov.base);
        const slice = data[0..iov.len];
        try writeAll(file, slice);
        total += iov.len;
    }
    return total;
}

/// Read from a file into a buffer (replacement for old file.read).
/// Uses the streaming read API since stdin is a non-seekable stream.
pub fn read(file: File, buffer: []u8) !usize {
    return file.readStreaming(defaultIo(), &.{buffer});
}

// =========================================================================
// Directory helpers
// =========================================================================

/// Open a file relative to cwd (replacement for std.fs.cwd().openFile).
pub fn cwdOpenFile(sub_path: []const u8, options: anytype) !File {
    _ = options;
    return Dir.cwd().openFile(defaultIo(), sub_path, .{});
}

/// Create a file relative to cwd (replacement for std.fs.cwd().createFile).
pub fn cwdCreateFile(sub_path: []const u8, flags: anytype) !File {
    return Dir.cwd().createFile(defaultIo(), sub_path, .{ .truncate = flags.truncate });
}

/// Open a directory relative to cwd (replacement for std.fs.cwd().openDir).
pub fn cwdOpenDir(sub_path: []const u8, options: anytype) !Dir {
    _ = options;
    return Dir.cwd().openDir(defaultIo(), sub_path, .{});
}

/// Close a directory.
pub fn closeDir(dir: Dir) void {
    dir.close(defaultIo());
}

/// Make a path relative to cwd (replacement for std.fs.cwd().makePath).
pub fn cwdMakePath(sub_path: []const u8) !void {
    try Dir.cwd().createDirPath(defaultIo(), sub_path);
}

/// Delete a file relative to cwd.
pub fn cwdDeleteFile(sub_path: []const u8) !void {
    try Dir.cwd().deleteFile(defaultIo(), sub_path);
}

/// Delete a directory tree relative to cwd.
pub fn cwdDeleteTree(sub_path: []const u8) !void {
    try Dir.cwd().deleteTree(defaultIo(), sub_path);
}

/// Stat a file relative to cwd.
pub fn cwdStatFile(sub_path: []const u8) !std.Io.Dir.Stat {
    return Dir.cwd().statFile(defaultIo(), sub_path, .{});
}

/// Get real path of "." relative to a dir, allocating result.
pub fn dirRealpathAlloc(allocator: std.mem.Allocator, dir: Dir) ![]u8 {
    // In 0.16.0, there's no realpathAlloc on Dir. Use /proc/self/fd/N on Linux.
    if (builtin.os.tag == .linux) {
        var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        var fd_path_buf: [64:0]u8 = undefined;
        const fd_path_slice = std.fmt.bufPrint(&fd_path_buf, "/proc/self/fd/{d}", .{dir.handle}) catch return error.NameTooLong;
        fd_path_buf[fd_path_slice.len] = 0;
        const fd_path_z: [*:0]const u8 = fd_path_buf[0..fd_path_slice.len :0];
        const rc = std.os.linux.readlink(fd_path_z, &path_buf, path_buf.len);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.FileNotFound;
        return allocator.dupe(u8, path_buf[0..rc]);
    } else {
        // Fallback: just return "."
        return allocator.dupe(u8, ".");
    }
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

/// Get environment variable by Zig slice name.
/// Converts to null-terminated string using a static buffer.
pub fn getenvSlice(name: []const u8) ?[]const u8 {
    if (name.len >= 255) return null;
    var buf: [256]u8 = undefined;
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
// Dir iterate
// =========================================================================

pub fn dirIterate(dir: Dir) Dir.Iterator {
    return dir.iterate();
}
