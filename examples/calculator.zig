// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Calculator REPL Example
//!
//! A practical example demonstrating:
//! - Custom expression evaluation
//! - User context (for storing variables)
//! - Tab completion for functions
//! - Multi-line expressions
//! - History for recalling calculations
//!
//! Run with: zig build run-calc

const std = @import("std");
const repl = @import("repl");

/// Calculator context - stores variables and settings
const CalcContext = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap(f64),
    last_result: f64 = 0,
    angle_mode: AngleMode = .radians,

    const AngleMode = enum { radians, degrees };

    fn init(allocator: std.mem.Allocator) CalcContext {
        var ctx = CalcContext{
            .allocator = allocator,
            .variables = std.StringHashMap(f64).init(allocator),
        };

        // Set up built-in constants
        ctx.variables.put("pi", std.math.pi) catch {};
        ctx.variables.put("e", std.math.e) catch {};
        ctx.variables.put("tau", std.math.tau) catch {};

        return ctx;
    }

    fn deinit(self: *CalcContext) void {
        self.variables.deinit();
    }
};

/// Available functions for tab completion
const FUNCTIONS = [_][]const u8{
    "sin",   "cos",   "tan",
    "asin",  "acos",  "atan",
    "sqrt",  "abs",   "log",
    "log2",  "log10", "exp",
    "pow",   "floor", "ceil",
    "round",
};

const COMMANDS = [_][]const u8{
    "help",
    "vars",
    "clear",
    "degrees",
    "radians",
    "quit",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = CalcContext.init(allocator);
    defer ctx.deinit();

    try repl.Repl.run(.{
        .allocator = allocator,
        .prompt = "calc> ",
        .continuation_prompt = "   .. ",
        .app_name = "calc-example",
        .history_enabled = true,
        .run_fn = handleCommand,
        .complete_fn = handleCompletion,
        .is_complete_fn = isExpressionComplete,
        .welcome_fn = printWelcome,
        .user_context = @ptrCast(&ctx),
    });
}

fn printWelcome(stdout: std.fs.File, use_color: bool) !void {
    const out = repl.TerminalWriter{ .file = stdout, .use_color = use_color };

    try out.writeBold("Calculator REPL\n\n");
    try out.write("Enter mathematical expressions to evaluate.\n\n");

    try out.writeColored(.cyan, "Examples:\n");
    try out.write("  2 + 3 * 4           = 14\n");
    try out.write("  sqrt(16)            = 4\n");
    try out.write("  sin(pi/2)           = 1\n");
    try out.write("  x = 5               (assign variable)\n");
    try out.write("  x * 2               = 10\n\n");

    try out.writeColored(.cyan, "Commands:\n");
    try out.write("  help     - Show all commands and functions\n");
    try out.write("  vars     - Show defined variables\n");
    try out.write("  quit     - Exit\n\n");

    try out.write("Use Tab for function completion. Use _ for last result.\n\n");
}

fn handleCompletion(prefix: []const u8, ctx: *repl.CompletionContext) void {
    // Complete functions
    for (FUNCTIONS) |func| {
        if (std.mem.startsWith(u8, func, prefix)) {
            // Add with opening paren
            var buf: [64]u8 = undefined;
            const with_paren = std.fmt.bufPrint(&buf, "{s}(", .{func}) catch func;
            ctx.addCandidate(with_paren) catch {};
        }
    }

    // Complete commands
    for (COMMANDS) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }
}

fn isExpressionComplete(input: []const u8) bool {
    // Check parentheses balance
    return repl.isBalanced(input);
}

fn handleCommand(
    user_context: ?*anyopaque,
    _: std.mem.Allocator,
    input: []const u8,
    _: *repl.HistoryStore,
) anyerror!bool {
    const out = repl.terminalWriter();
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    if (trimmed.len == 0) return true;

    const ctx: *CalcContext = if (user_context) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        return true;

    // Handle commands
    if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
        try out.writeSuccess("Goodbye!");
        return false;
    }

    if (std.mem.eql(u8, trimmed, "help")) {
        try showHelp(out);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "vars")) {
        try showVariables(out, ctx);
        return true;
    }

    if (std.mem.eql(u8, trimmed, "clear")) {
        try out.clearScreen();
        return true;
    }

    if (std.mem.eql(u8, trimmed, "degrees")) {
        ctx.angle_mode = .degrees;
        try out.writeSuccess("Angle mode: degrees");
        return true;
    }

    if (std.mem.eql(u8, trimmed, "radians")) {
        ctx.angle_mode = .radians;
        try out.writeSuccess("Angle mode: radians");
        return true;
    }

    // Check for variable assignment: x = expr
    if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
        const var_name = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
        const expr = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

        // Validate variable name (alphanumeric, starts with letter)
        if (var_name.len > 0 and std.ascii.isAlphabetic(var_name[0])) {
            if (evaluateExpression(expr, ctx)) |result| {
                ctx.variables.put(var_name, result) catch {};
                ctx.last_result = result;

                try out.setColor(.bright_black);
                try out.write(var_name);
                try out.write(" = ");
                try out.resetStyle();
                try out.setColor(.green);
                try out.print("{d}\n", .{result});
                try out.resetStyle();
                return true;
            } else |err| {
                try out.writeError(@errorName(err));
                return true;
            }
        }
    }

    // Evaluate as expression
    if (evaluateExpression(trimmed, ctx)) |result| {
        ctx.last_result = result;
        ctx.variables.put("_", result) catch {}; // Store in _ for reference

        try out.write("= ");
        try out.setColor(.green);
        try out.setStyle(.bold);
        try out.print("{d}\n", .{result});
        try out.resetStyle();
    } else |err| {
        try out.writeError(@errorName(err));
    }

    return true;
}

/// Simple expression evaluator
/// This is a basic implementation - a real calculator would have proper parsing
fn evaluateExpression(expr: []const u8, ctx: *CalcContext) !f64 {
    const trimmed = std.mem.trim(u8, expr, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyExpression;

    // Check for variable reference
    if (ctx.variables.get(trimmed)) |value| {
        return value;
    }

    // Try to parse as a simple number
    if (std.fmt.parseFloat(f64, trimmed)) |value| {
        return value;
    } else |_| {}

    // Check for function calls: func(arg)
    if (std.mem.indexOf(u8, trimmed, "(")) |paren_start| {
        if (std.mem.lastIndexOf(u8, trimmed, ")")) |paren_end| {
            if (paren_end > paren_start) {
                const func_name = trimmed[0..paren_start];
                const arg_str = trimmed[paren_start + 1 .. paren_end];

                // Handle pow(x, y) specially
                if (std.mem.eql(u8, func_name, "pow")) {
                    if (std.mem.indexOf(u8, arg_str, ",")) |comma_pos| {
                        const base_str = std.mem.trim(u8, arg_str[0..comma_pos], " \t");
                        const exp_str = std.mem.trim(u8, arg_str[comma_pos + 1 ..], " \t");
                        const base = try evaluateExpression(base_str, ctx);
                        const exponent = try evaluateExpression(exp_str, ctx);
                        return std.math.pow(f64, base, exponent);
                    }
                }

                const arg = try evaluateExpression(arg_str, ctx);
                return applyFunction(func_name, arg, ctx);
            }
        }
    }

    // Check for binary operators (very basic, left-to-right evaluation)
    // In a real implementation, you'd want proper operator precedence
    const operators = [_]u8{ '+', '-', '*', '/' };
    for (operators) |op| {
        // Find rightmost operator (for left-to-right evaluation)
        var i: usize = trimmed.len;
        var paren_depth: i32 = 0;

        while (i > 0) {
            i -= 1;
            const c = trimmed[i];
            if (c == ')') paren_depth += 1;
            if (c == '(') paren_depth -= 1;

            if (paren_depth == 0 and c == op and i > 0) {
                const left = std.mem.trim(u8, trimmed[0..i], " \t");
                const right = std.mem.trim(u8, trimmed[i + 1 ..], " \t");

                if (left.len > 0 and right.len > 0) {
                    const left_val = try evaluateExpression(left, ctx);
                    const right_val = try evaluateExpression(right, ctx);

                    return switch (op) {
                        '+' => left_val + right_val,
                        '-' => left_val - right_val,
                        '*' => left_val * right_val,
                        '/' => if (right_val != 0) left_val / right_val else error.DivisionByZero,
                        else => error.InvalidOperator,
                    };
                }
            }
        }
    }

    // Handle negative numbers
    if (trimmed[0] == '-') {
        const rest = try evaluateExpression(trimmed[1..], ctx);
        return -rest;
    }

    return error.InvalidExpression;
}

fn applyFunction(name: []const u8, arg: f64, ctx: *CalcContext) !f64 {
    // Convert to radians if in degrees mode for trig functions
    const trig_arg = if (ctx.angle_mode == .degrees and
        (std.mem.eql(u8, name, "sin") or std.mem.eql(u8, name, "cos") or std.mem.eql(u8, name, "tan")))
        arg * std.math.pi / 180.0
    else
        arg;

    if (std.mem.eql(u8, name, "sin")) return @sin(trig_arg);
    if (std.mem.eql(u8, name, "cos")) return @cos(trig_arg);
    if (std.mem.eql(u8, name, "tan")) return @tan(trig_arg);
    if (std.mem.eql(u8, name, "asin")) {
        const result = std.math.asin(arg);
        return if (ctx.angle_mode == .degrees) result * 180.0 / std.math.pi else result;
    }
    if (std.mem.eql(u8, name, "acos")) {
        const result = std.math.acos(arg);
        return if (ctx.angle_mode == .degrees) result * 180.0 / std.math.pi else result;
    }
    if (std.mem.eql(u8, name, "atan")) {
        const result = std.math.atan(arg);
        return if (ctx.angle_mode == .degrees) result * 180.0 / std.math.pi else result;
    }
    if (std.mem.eql(u8, name, "sqrt")) return @sqrt(arg);
    if (std.mem.eql(u8, name, "abs")) return @abs(arg);
    if (std.mem.eql(u8, name, "log")) return @log(arg);
    if (std.mem.eql(u8, name, "log2")) return std.math.log2(arg);
    if (std.mem.eql(u8, name, "log10")) return std.math.log10(arg);
    if (std.mem.eql(u8, name, "exp")) return @exp(arg);
    if (std.mem.eql(u8, name, "floor")) return @floor(arg);
    if (std.mem.eql(u8, name, "ceil")) return @ceil(arg);
    if (std.mem.eql(u8, name, "round")) return @round(arg);

    return error.UnknownFunction;
}

fn showHelp(out: repl.TerminalWriter) !void {
    try out.writeBold("\nCalculator Help\n\n");

    try out.writeColored(.cyan, "Operators:\n");
    try out.write("  +  -  *  /  (basic arithmetic)\n\n");

    try out.writeColored(.cyan, "Functions:\n");
    try out.write("  sin, cos, tan      - Trigonometric functions\n");
    try out.write("  asin, acos, atan   - Inverse trigonometric\n");
    try out.write("  sqrt, abs          - Square root, absolute value\n");
    try out.write("  log, log2, log10   - Logarithms\n");
    try out.write("  exp                - Exponential (e^x)\n");
    try out.write("  pow(x, y)          - Power (x^y)\n");
    try out.write("  floor, ceil, round - Rounding functions\n\n");

    try out.writeColored(.cyan, "Constants:\n");
    try out.write("  pi   - 3.14159...\n");
    try out.write("  e    - 2.71828...\n");
    try out.write("  tau  - 6.28318... (2*pi)\n");
    try out.write("  _    - Last result\n\n");

    try out.writeColored(.cyan, "Commands:\n");
    try out.write("  vars      - Show all variables\n");
    try out.write("  degrees   - Switch to degrees mode\n");
    try out.write("  radians   - Switch to radians mode\n");
    try out.write("  clear     - Clear screen\n");
    try out.write("  quit      - Exit\n\n");

    try out.writeColored(.cyan, "Variable Assignment:\n");
    try out.write("  x = 5     - Assign value to variable\n");
    try out.write("  x * 2     - Use variable in expression\n\n");
}

fn showVariables(out: repl.TerminalWriter, ctx: *CalcContext) !void {
    try out.writeBold("\nDefined Variables\n\n");

    var iter = ctx.variables.iterator();
    while (iter.next()) |entry| {
        try out.setColor(.cyan);
        try out.write("  ");
        try out.write(entry.key_ptr.*);
        try out.resetStyle();
        try out.write(" = ");
        try out.print("{d}\n", .{entry.value_ptr.*});
    }

    try out.write("\n");
    try out.print("Angle mode: {s}\n\n", .{@tagName(ctx.angle_mode)});
}
