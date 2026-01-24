// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Input parsing utilities
//!
//! Provides utilities for detecting:
//! - Balanced brackets/quotes
//! - Statement completion
//! - Continuation requirements

const std = @import("std");

/// Check if the input is a complete statement.
///
/// This is a generic check that considers:
/// - Semicolon termination (common for many languages)
/// - Balanced brackets and quotes
/// - Trailing operators suggesting continuation
///
/// For language-specific completion detection, use the
/// StatementChecker interface.
pub fn isComplete(input: []const u8) bool {
    // Empty input is complete (no-op)
    if (input.len == 0) return true;

    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) return true;

    // Check for semicolon terminator (common convention)
    if (std.mem.indexOf(u8, trimmed, ";")) |_| {
        return true;
    }

    // Check if balanced and no continuation needed
    return isBalanced(input) and !needsContinuation(input);
}

/// Check if all brackets and quotes are balanced.
pub fn isBalanced(input: []const u8) bool {
    var paren_depth: i32 = 0;
    var bracket_depth: i32 = 0;
    var brace_depth: i32 = 0;
    var in_string = false;
    var in_single_string = false;
    var in_line_comment = false;
    var in_block_comment = false;
    var escape_next = false;

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];

        // Handle escape sequences in strings
        if (escape_next) {
            escape_next = false;
            continue;
        }

        // Handle comments
        if (!in_string and !in_single_string) {
            if (!in_block_comment and i + 1 < input.len) {
                // Line comment: // or #
                if ((input[i] == '/' and input[i + 1] == '/') or input[i] == '#') {
                    in_line_comment = true;
                    continue;
                }
                // Block comment: /*
                if (input[i] == '/' and input[i + 1] == '*') {
                    in_block_comment = true;
                    i += 1;
                    continue;
                }
                // SQL-style comment: --
                if (input[i] == '-' and input[i + 1] == '-') {
                    in_line_comment = true;
                    i += 1;
                    continue;
                }
            }

            if (in_block_comment and i + 1 < input.len) {
                if (input[i] == '*' and input[i + 1] == '/') {
                    in_block_comment = false;
                    i += 1;
                    continue;
                }
            }

            if (in_line_comment and c == '\n') {
                in_line_comment = false;
                continue;
            }
        }

        if (in_line_comment or in_block_comment) {
            continue;
        }

        // Handle double-quoted strings
        if (c == '"' and !in_single_string) {
            if (!in_string) {
                in_string = true;
            } else {
                in_string = false;
            }
            continue;
        }

        // Handle single-quoted strings
        if (c == '\'' and !in_string) {
            if (!in_single_string) {
                in_single_string = true;
            } else {
                in_single_string = false;
            }
            continue;
        }

        if (in_string or in_single_string) {
            if (c == '\\') {
                escape_next = true;
            }
            continue;
        }

        // Count brackets
        switch (c) {
            '(' => paren_depth += 1,
            ')' => {
                paren_depth -= 1;
                if (paren_depth < 0) return false;
            },
            '[' => bracket_depth += 1,
            ']' => {
                bracket_depth -= 1;
                if (bracket_depth < 0) return false;
            },
            '{' => brace_depth += 1,
            '}' => {
                brace_depth -= 1;
                if (brace_depth < 0) return false;
            },
            else => {},
        }
    }

    return paren_depth == 0 and
        bracket_depth == 0 and
        brace_depth == 0 and
        !in_string and
        !in_single_string and
        !in_block_comment;
}

/// Check if the input ends with something suggesting continuation is needed.
pub fn needsContinuation(input: []const u8) bool {
    if (input.len == 0) return false;

    // Check if last non-whitespace character suggests continuation
    var i = input.len;
    while (i > 0) : (i -= 1) {
        const c = input[i - 1];
        if (!std.ascii.isWhitespace(c)) {
            return switch (c) {
                ',', '+', '-', '*', '/', '=', '<', '>', '(', '[', '{', '|', '&', '\\' => true,
                else => false,
            };
        }
    }

    return false;
}

/// Interface for language-specific statement completion checking.
pub const StatementChecker = struct {
    /// Check if the input is complete in the language's syntax.
    checkFn: *const fn (checker: *const StatementChecker, input: []const u8) bool,
    context: ?*anyopaque = null,

    pub fn isComplete(self: *const StatementChecker, input: []const u8) bool {
        return self.checkFn(self, input);
    }
};

/// Create a statement checker for semicolon-terminated languages.
pub fn semicolonTerminatedChecker() StatementChecker {
    return StatementChecker{
        .checkFn = struct {
            fn check(_: *const StatementChecker, input: []const u8) bool {
                const trimmed = std.mem.trim(u8, input, " \t\n\r");
                if (trimmed.len == 0) return true;
                return std.mem.endsWith(u8, trimmed, ";") and isBalanced(input);
            }
        }.check,
    };
}

/// Create a statement checker that considers input complete when balanced
/// (for languages like Python where newlines are significant).
pub fn balancedChecker() StatementChecker {
    return StatementChecker{
        .checkFn = struct {
            fn check(_: *const StatementChecker, input: []const u8) bool {
                return isBalanced(input) and !needsContinuation(input);
            }
        }.check,
    };
}

/// Trim trailing whitespace and return the trimmed slice.
pub fn trimTrailing(input: []const u8) []const u8 {
    var end = input.len;
    while (end > 0 and std.ascii.isWhitespace(input[end - 1])) {
        end -= 1;
    }
    return input[0..end];
}

/// Check if input ends with a backslash continuation.
pub fn hasBackslashContinuation(input: []const u8) bool {
    const trimmed = trimTrailing(input);
    return trimmed.len > 0 and trimmed[trimmed.len - 1] == '\\';
}

test "isBalanced basic" {
    try std.testing.expect(isBalanced(""));
    try std.testing.expect(isBalanced("hello"));
    try std.testing.expect(isBalanced("(a + b)"));
    try std.testing.expect(isBalanced("func(a, b)"));
    try std.testing.expect(isBalanced("[1, 2, 3]"));
    try std.testing.expect(isBalanced("{a: 1}"));
    try std.testing.expect(isBalanced("((()))"));
}

test "isBalanced unbalanced" {
    try std.testing.expect(!isBalanced("("));
    try std.testing.expect(!isBalanced(")"));
    try std.testing.expect(!isBalanced("(a + b"));
    try std.testing.expect(!isBalanced("[1, 2"));
    try std.testing.expect(!isBalanced("{a:"));
    try std.testing.expect(!isBalanced("(])"));
}

test "isBalanced strings" {
    try std.testing.expect(isBalanced("\"hello\""));
    try std.testing.expect(isBalanced("'hello'"));
    try std.testing.expect(isBalanced("\"hello (world)\""));
    try std.testing.expect(!isBalanced("\"unclosed"));
    try std.testing.expect(!isBalanced("'unclosed"));
    try std.testing.expect(isBalanced("\"escaped \\\" quote\""));
}

test "isBalanced comments" {
    try std.testing.expect(isBalanced("a // comment"));
    try std.testing.expect(isBalanced("a /* comment */"));
    try std.testing.expect(isBalanced("a -- sql comment"));
    try std.testing.expect(!isBalanced("a /* unclosed"));
    try std.testing.expect(isBalanced("// comment with ("));
    // Comment hides the ( but ) is still unbalanced
    try std.testing.expect(!isBalanced("/* ( */ )"));
    // This one is balanced: comment hides ( and no parens outside
    try std.testing.expect(isBalanced("/* ( */"));
    try std.testing.expect(isBalanced("(/* comment */)"));
}

test "needsContinuation" {
    try std.testing.expect(needsContinuation("a +"));
    try std.testing.expect(needsContinuation("func("));
    try std.testing.expect(needsContinuation("a,"));
    try std.testing.expect(needsContinuation("a \\"));
    try std.testing.expect(!needsContinuation("a"));
    try std.testing.expect(!needsContinuation("a;"));
    try std.testing.expect(!needsContinuation("a)"));
}

test "isComplete" {
    try std.testing.expect(isComplete(""));
    try std.testing.expect(isComplete("SELECT 1;"));
    try std.testing.expect(isComplete("hello world"));
    try std.testing.expect(!isComplete("SELECT ("));
    try std.testing.expect(!isComplete("a +"));
}

test "hasBackslashContinuation" {
    try std.testing.expect(hasBackslashContinuation("line \\"));
    try std.testing.expect(hasBackslashContinuation("line\\"));
    try std.testing.expect(!hasBackslashContinuation("line"));
    try std.testing.expect(!hasBackslashContinuation("line\\n"));
}
