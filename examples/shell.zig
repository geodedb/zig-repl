// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Simple Shell Example
//!
//! A more complete example showing how to build a simple shell with:
//! - Command execution (echo, pwd, cd, etc.)
//! - Environment variable expansion
//! - File path completion
//! - Command history
//! - Colored prompt with working directory
//!
//! Run with: zig build run-shell
//!
//! Note: This is a demonstration, not a full POSIX shell.
//! It shows how the REPL library can be used for shell-like applications.

const std = @import("std");
const builtin = @import("builtin");
const repl = @import("repl");

/// Shell context
const ShellContext = struct {
    allocator: std.mem.Allocator,
    cwd: []u8,
    env: std.process.Environ.Map,
    last_exit_code: u8 = 0,

    fn init(allocator: std.mem.Allocator) !ShellContext {
        // In 0.16.0, use raw linux readlink syscall or fallback
        const cwd = blk: {
            if (builtin.os.tag == .linux) {
                var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const rc = std.os.linux.readlink("/proc/self/cwd", &path_buf, path_buf.len);
                if (std.os.linux.errno(rc) != .SUCCESS) break :blk try allocator.dupe(u8, ".");
                break :blk try allocator.dupe(u8, path_buf[0..rc]);
            } else {
                break :blk try allocator.dupe(u8, ".");
            }
        };

        return ShellContext{
            .allocator = allocator,
            .cwd = cwd,
            .env = std.process.Environ.Map.init(allocator),
        };
    }

    fn deinit(self: *ShellContext) void {
        self.allocator.free(self.cwd);
        self.env.deinit();
    }

    fn setCwd(self: *ShellContext, new_cwd: []const u8) !void {
        self.allocator.free(self.cwd);
        self.cwd = try self.allocator.dupe(u8, new_cwd);
    }
};

/// Built-in commands for completion
const BUILTINS = [_][]const u8{
    "cd",
    "pwd",
    "echo",
    "exit",
    "help",
    "export",
    "env",
    "clear",
    "history",
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var ctx = try ShellContext.init(allocator);
    defer ctx.deinit();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = buildPrompt(&ctx),
        .app_name = "shell-example",
        .history_enabled = true,
        .run_fn = handleCommand,
        .complete_fn = handleCompletion,
        .welcome_fn = printWelcome,
        .user_context = @ptrCast(&ctx),
    });
}

fn buildPrompt(_: *ShellContext) []const u8 {
    // In a real implementation, you might build a dynamic prompt
    // For simplicity, we use a static prompt here
    return "shell$ ";
}

fn printWelcome(stdout: std.Io.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Simple Shell Example\n\n");
    try out.write("A demonstration of using the REPL library for shell-like applications.\n\n");

    try out.writeColored(.cyan, "Built-in Commands:\n");
    try out.write("  cd <dir>      - Change directory\n");
    try out.write("  pwd           - Print working directory\n");
    try out.write("  echo <text>   - Print text (supports $VAR expansion)\n");
    try out.write("  export K=V    - Set environment variable\n");
    try out.write("  env           - Show environment variables\n");
    try out.write("  clear         - Clear screen\n");
    try out.write("  history       - Show command history\n");
    try out.write("  help          - Show this help\n");
    try out.write("  exit          - Exit shell\n\n");

    try out.write("Use Tab for command and file path completion.\n\n");
}

fn handleCompletion(prefix: []const u8, ctx: *repl.CompletionContext) void {
    // If prefix looks like a path, complete file paths
    if (prefix.len > 0 and (prefix[0] == '/' or prefix[0] == '.' or prefix[0] == '~')) {
        repl.completion.generateFilePathCandidates(ctx, prefix) catch {};
        return;
    }

    // Check if there's a space (completing an argument, not a command)
    // This is a simplification - real shells have more complex logic
    if (ctx.word_start > 0) {
        // Completing a path argument
        repl.completion.generateFilePathCandidates(ctx, prefix) catch {};
        return;
    }

    // Complete built-in commands
    for (BUILTINS) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }
}

fn handleCommand(
    user_context: ?*anyopaque,
    allocator: std.mem.Allocator,
    input: []const u8,
    history: *repl.HistoryStore,
) anyerror!bool {
    const out = repl.terminalWriter();
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    if (trimmed.len == 0) return true;

    const ctx: *ShellContext = if (user_context) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        return true;

    // Parse command and arguments
    var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
    const cmd = parts.next() orelse return true;
    const args = parts.rest();

    // Built-in: exit
    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit")) {
        try out.writeSuccess("Goodbye!");
        return false;
    }

    // Built-in: help
    if (std.mem.eql(u8, cmd, "help")) {
        try showHelp(out);
        return true;
    }

    // Built-in: pwd
    if (std.mem.eql(u8, cmd, "pwd")) {
        try out.writeLine(ctx.cwd);
        return true;
    }

    // Built-in: cd
    if (std.mem.eql(u8, cmd, "cd")) {
        try changeDirectory(out, ctx, args, allocator);
        return true;
    }

    // Built-in: echo
    if (std.mem.eql(u8, cmd, "echo")) {
        try echoCommand(out, args, ctx);
        return true;
    }

    // Built-in: export
    if (std.mem.eql(u8, cmd, "export")) {
        try exportCommand(out, args, ctx);
        return true;
    }

    // Built-in: env
    if (std.mem.eql(u8, cmd, "env")) {
        try showEnv(out, ctx);
        return true;
    }

    // Built-in: clear
    if (std.mem.eql(u8, cmd, "clear")) {
        try out.clearScreen();
        return true;
    }

    // Built-in: history
    if (std.mem.eql(u8, cmd, "history")) {
        try showHistory(out, history);
        return true;
    }

    // Unknown command
    try out.setColor(.red);
    try out.write("shell: command not found: ");
    try out.writeLine(cmd);
    try out.resetStyle();
    ctx.last_exit_code = 127;

    return true;
}

/// Cross-platform getenv helper. On POSIX uses libc getenv; on Windows
/// converts the variable name at comptime and decodes the UTF-16 value into
/// a module-level static buffer.
fn crossGetenv(comptime name: []const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        const key_w = std.unicode.utf8ToUtf16LeStringLiteral(name);
        const value_w: [:0]const u16 = std.process.getenvW(key_w) orelse return null;
        const n = std.unicode.utf16LeToUtf8(&shell_env_buf, value_w) catch return null;
        return shell_env_buf[0..n];
    } else {
        const result = std.c.getenv(name[0..name.len :0]) orelse return null;
        return std.mem.sliceTo(result, 0);
    }
}

var shell_env_buf: [1024]u8 = undefined;

fn changeDirectory(out: repl.TerminalWriter, ctx: *ShellContext, args: []const u8, allocator: std.mem.Allocator) !void {
    var target: []const u8 = undefined;

    if (args.len == 0) {
        // cd with no args goes to home directory
        const home_var = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
        target = crossGetenv(home_var) orelse {
            try out.writeError("HOME not set");
            return;
        };
    } else if (args[0] == '~') {
        // Expand tilde
        const home_var = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
        const home = crossGetenv(home_var) orelse {
            try out.writeError("HOME not set");
            return;
        };
        if (args.len == 1) {
            target = home;
        } else {
            var buf: [1024]u8 = undefined;
            target = std.fmt.bufPrint(&buf, "{s}{s}", .{ home, args[1..] }) catch {
                try out.writeError("Path too long");
                return;
            };
        }
    } else {
        target = args;
    }

    // Resolve the path
    const sio = std.Io.Threaded.global_single_threaded.io();
    var dir = std.Io.Dir.cwd().openDir(sio, target, .{}) catch |err| {
        try out.writeError(@errorName(err));
        ctx.last_exit_code = 1;
        return;
    };
    defer dir.close(sio);

    // Get real path via /proc/self/fd on Linux, or just use target
    const real_path = blk: {
        if (builtin.os.tag == .linux) {
            var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            var fd_path_buf: [64:0]u8 = undefined;
            const fd_path_slice = std.fmt.bufPrint(&fd_path_buf, "/proc/self/fd/{d}", .{dir.handle}) catch break :blk allocator.dupe(u8, target) catch |err| {
                try out.writeError(@errorName(err));
                ctx.last_exit_code = 1;
                return;
            };
            fd_path_buf[fd_path_slice.len] = 0;
            const fd_path_z: [*:0]const u8 = fd_path_buf[0..fd_path_slice.len :0];
            const rc = std.os.linux.readlink(fd_path_z, &path_buf, path_buf.len);
            if (std.os.linux.errno(rc) != .SUCCESS) break :blk allocator.dupe(u8, target) catch |err| {
                try out.writeError(@errorName(err));
                ctx.last_exit_code = 1;
                return;
            };
            break :blk allocator.dupe(u8, path_buf[0..rc]) catch |err| {
                try out.writeError(@errorName(err));
                ctx.last_exit_code = 1;
                return;
            };
        } else {
            break :blk allocator.dupe(u8, target) catch |err| {
                try out.writeError(@errorName(err));
                ctx.last_exit_code = 1;
                return;
            };
        }
    };
    defer allocator.free(real_path);

    try ctx.setCwd(real_path);
    ctx.last_exit_code = 0;
}

fn echoCommand(out: repl.TerminalWriter, args: []const u8, ctx: *ShellContext) !void {
    // Simple variable expansion
    var i: usize = 0;
    while (i < args.len) {
        if (args[i] == '$' and i + 1 < args.len) {
            // Find variable name
            var j = i + 1;
            while (j < args.len and (std.ascii.isAlphanumeric(args[j]) or args[j] == '_')) {
                j += 1;
            }

            const var_name = args[i + 1 .. j];
            if (var_name.len > 0) {
                // Check our local env first, then system env
                if (ctx.env.get(var_name)) |value| {
                    try out.write(value);
                } else {
                    // Look up system env using libc getenv
                    if (var_name.len < 255) {
                        var env_buf: [256]u8 = undefined;
                        @memcpy(env_buf[0..var_name.len], var_name);
                        env_buf[var_name.len] = 0;
                        const name_z: [*:0]const u8 = env_buf[0..var_name.len :0];
                        if (builtin.os.tag != .windows) {
                            if (std.c.getenv(name_z)) |result| {
                                try out.write(std.mem.sliceTo(result, 0));
                            }
                        }
                    }
                }
            }
            i = j;
        } else {
            try out.write(&[_]u8{args[i]});
            i += 1;
        }
    }
    try out.write("\n");
}

fn exportCommand(out: repl.TerminalWriter, args: []const u8, ctx: *ShellContext) !void {
    if (args.len == 0) {
        // Show all exports
        var iter = ctx.env.iterator();
        while (iter.next()) |entry| {
            try out.print("export {s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        return;
    }

    // Parse KEY=VALUE
    if (std.mem.indexOf(u8, args, "=")) |eq_pos| {
        const key = args[0..eq_pos];
        const value = args[eq_pos + 1 ..];
        try ctx.env.put(key, value);
    } else {
        try out.writeWarning("Usage: export KEY=VALUE");
    }
}

fn showEnv(out: repl.TerminalWriter, ctx: *ShellContext) !void {
    try out.writeBold("Shell Environment Variables:\n");

    var iter = ctx.env.iterator();
    var count: usize = 0;
    while (iter.next()) |entry| {
        try out.setColor(.cyan);
        try out.write(entry.key_ptr.*);
        try out.resetStyle();
        try out.write("=");
        try out.writeLine(entry.value_ptr.*);
        count += 1;
    }

    if (count == 0) {
        try out.writeInfo("(no shell variables set)");
    }

    try out.write("\nUse 'export KEY=VALUE' to set variables.\n");
}

fn showHistory(out: repl.TerminalWriter, history: *repl.HistoryStore) !void {
    const count = history.count();

    if (count == 0) {
        try out.writeInfo("No history.");
        return;
    }

    const start = if (count > 20) count - 20 else 0;

    for (history.entries.items[start..], start..) |entry, i| {
        try out.setColor(.bright_black);
        try out.print("{d:>4}  ", .{i + 1});
        try out.resetStyle();
        try out.writeLine(entry);
    }
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nSimple Shell - Built-in Commands\n\n");

    try out.writeColored(.cyan, "Navigation:\n");
    try out.write("  cd [dir]       Change directory (~ for home)\n");
    try out.write("  pwd            Print working directory\n\n");

    try out.writeColored(.cyan, "I/O:\n");
    try out.write("  echo [text]    Print text (supports $VAR expansion)\n");
    try out.write("  clear          Clear the screen\n\n");

    try out.writeColored(.cyan, "Environment:\n");
    try out.write("  export K=V     Set shell variable\n");
    try out.write("  export         Show all shell variables\n");
    try out.write("  env            Same as export (show variables)\n\n");

    try out.writeColored(.cyan, "History:\n");
    try out.write("  history        Show command history\n");
    try out.write("  Ctrl+P/Up      Previous command\n");
    try out.write("  Ctrl+N/Down    Next command\n");
    try out.write("  Ctrl+R         Search history\n\n");

    try out.writeColored(.cyan, "Other:\n");
    try out.write("  help           Show this help\n");
    try out.write("  exit           Exit the shell\n\n");

    try out.write("Tab completion works for commands and file paths.\n\n");
}
