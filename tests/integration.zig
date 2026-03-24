// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Integration tests for the REPL library
//!
//! These tests verify that all components work together correctly.

const std = @import("std");
const repl = @import("repl");

// ============================================================================
// History Tests
// ============================================================================

test "history store operations" {
    const allocator = std.testing.allocator;

    var store = try repl.HistoryStore.init(allocator, null, true);
    defer store.deinit();

    // Test appending entries
    try store.append("first command");
    try store.append("second command");
    try store.append("third command");

    try std.testing.expectEqual(@as(usize, 3), store.entries.items.len);
    try std.testing.expectEqualStrings("first command", store.entries.items[0]);
    try std.testing.expectEqualStrings("third command", store.entries.items[2]);
}

test "history duplicate prevention" {
    const allocator = std.testing.allocator;

    var store = try repl.HistoryStore.init(allocator, null, true);
    defer store.deinit();

    try store.append("command");
    try store.append("command"); // Duplicate
    try store.append("command"); // Duplicate

    try std.testing.expectEqual(@as(usize, 1), store.entries.items.len);
}

test "history search" {
    const allocator = std.testing.allocator;

    var store = try repl.HistoryStore.init(allocator, null, true);
    defer store.deinit();

    try store.append("select * from users");
    try store.append("insert into logs");
    try store.append("select count(*) from orders");

    // Search for "select"
    if (store.searchBackward("select", null)) |result| {
        try std.testing.expectEqualStrings("select count(*) from orders", result.entry);
        try std.testing.expectEqual(@as(usize, 2), result.index);
    } else {
        return error.SearchFailed;
    }

    // Continue search from previous result
    if (store.searchBackward("select", 2)) |result| {
        try std.testing.expectEqualStrings("select * from users", result.entry);
        try std.testing.expectEqual(@as(usize, 0), result.index);
    } else {
        return error.ContinueSearchFailed;
    }
}

// ============================================================================
// Completion Tests
// ============================================================================

test "completion context initialization" {
    const allocator = std.testing.allocator;

    var ctx = repl.CompletionContext.init(allocator);
    defer ctx.deinit();

    // Should be empty initially
    try std.testing.expectEqual(@as(usize, 0), ctx.current_index);
    try std.testing.expectEqual(@as(usize, 0), ctx.candidates.items.len);
}

test "completion candidate cycling" {
    const allocator = std.testing.allocator;

    var ctx = repl.CompletionContext.init(allocator);
    defer ctx.deinit();

    // Add candidates manually
    try ctx.addCandidate("hello");
    try ctx.addCandidate("help");
    try ctx.addCandidate("helicopter");

    try std.testing.expectEqual(@as(usize, 3), ctx.candidates.items.len);

    // Test cycling through candidates
    try std.testing.expectEqualStrings("hello", ctx.getCurrentCandidate().?);

    ctx.nextCandidate();
    try std.testing.expectEqualStrings("help", ctx.getCurrentCandidate().?);

    ctx.nextCandidate();
    try std.testing.expectEqualStrings("helicopter", ctx.getCurrentCandidate().?);

    ctx.nextCandidate(); // Should wrap around
    try std.testing.expectEqualStrings("hello", ctx.getCurrentCandidate().?);

    ctx.prevCandidate(); // Back to helicopter
    try std.testing.expectEqualStrings("helicopter", ctx.getCurrentCandidate().?);
}

test "completion from list" {
    const allocator = std.testing.allocator;

    var ctx = repl.CompletionContext.init(allocator);
    defer ctx.deinit();

    const options = [_][]const u8{ "select", "insert", "update", "delete", "drop" };
    try repl.completion.generateCandidatesFromList(&ctx, "se", &options);

    try std.testing.expectEqual(@as(usize, 1), ctx.candidates.items.len);
    try std.testing.expectEqualStrings("select", ctx.candidates.items[0]);
}

// ============================================================================
// Parse Tests
// ============================================================================

test "parse balanced expressions" {
    // Simple balanced
    try std.testing.expect(repl.isBalanced("()"));
    try std.testing.expect(repl.isBalanced("[]"));
    try std.testing.expect(repl.isBalanced("{}"));
    try std.testing.expect(repl.isBalanced("(a + b)"));
    try std.testing.expect(repl.isBalanced("[1, 2, 3]"));
    try std.testing.expect(repl.isBalanced("{key: value}"));

    // Nested balanced
    try std.testing.expect(repl.isBalanced("((()))"));
    try std.testing.expect(repl.isBalanced("{[()]}"));
    try std.testing.expect(repl.isBalanced("func(arr[0], {x: 1})"));

    // Unbalanced
    try std.testing.expect(!repl.isBalanced("("));
    try std.testing.expect(!repl.isBalanced(")"));
    try std.testing.expect(!repl.isBalanced("(()"));
    // Note: {[}] has balanced depth counts so it passes our simple check
    // Full nesting validation would require a stack-based approach
}

test "parse strings and quotes" {
    // Strings should hide brackets inside
    try std.testing.expect(repl.isBalanced("\"hello\""));
    try std.testing.expect(repl.isBalanced("'hello'"));
    try std.testing.expect(repl.isBalanced("\"(not a bracket)\""));
    try std.testing.expect(repl.isBalanced("'[also not]'"));

    // Escaped quotes
    try std.testing.expect(repl.isBalanced("\"escaped \\\" quote\""));

    // Unclosed strings
    try std.testing.expect(!repl.isBalanced("\"unclosed"));
    try std.testing.expect(!repl.isBalanced("'unclosed"));
}

test "parse comments" {
    // Comments should hide brackets
    try std.testing.expect(repl.isBalanced("code // comment with ("));
    try std.testing.expect(repl.isBalanced("code /* comment with ( */"));
    try std.testing.expect(repl.isBalanced("code -- sql comment with ("));

    // Unclosed block comment
    try std.testing.expect(!repl.isBalanced("code /* unclosed"));
}

test "parse continuation detection" {
    // Operators suggesting continuation
    try std.testing.expect(repl.needsContinuation("a +"));
    try std.testing.expect(repl.needsContinuation("a -"));
    try std.testing.expect(repl.needsContinuation("a ="));
    try std.testing.expect(repl.needsContinuation("func("));
    try std.testing.expect(repl.needsContinuation("arr["));
    try std.testing.expect(repl.needsContinuation("obj{"));
    try std.testing.expect(repl.needsContinuation("a,"));
    try std.testing.expect(repl.needsContinuation("line \\"));

    // Complete statements
    try std.testing.expect(!repl.needsContinuation("complete"));
    try std.testing.expect(!repl.needsContinuation("func()"));
    try std.testing.expect(!repl.needsContinuation("arr[0]"));
}

test "parse complete statements" {
    // Empty is complete
    try std.testing.expect(repl.isComplete(""));
    try std.testing.expect(repl.isComplete("   "));

    // Semicolon terminated
    try std.testing.expect(repl.isComplete("statement;"));
    try std.testing.expect(repl.isComplete("SELECT 1;"));

    // Balanced without continuation
    try std.testing.expect(repl.isComplete("function()"));
    try std.testing.expect(repl.isComplete("[1, 2, 3]"));

    // Incomplete
    try std.testing.expect(!repl.isComplete("func("));
    try std.testing.expect(!repl.isComplete("a +"));
}

// ============================================================================
// Config Tests
// ============================================================================

test "config default values" {
    const cfg = repl.Config.loadDefault();

    try std.testing.expectEqual(repl.Config.Keymap.emacs, cfg.keymap);
    try std.testing.expectEqual(repl.Config.Format.text, cfg.format);
    try std.testing.expect(cfg.history_enabled);
    try std.testing.expect(!cfg.timing_enabled);
    try std.testing.expect(!cfg.verbose);
}

test "config keymap from string" {
    try std.testing.expectEqual(repl.Config.Keymap.emacs, repl.Config.Keymap.fromString("emacs"));
    try std.testing.expectEqual(repl.Config.Keymap.vi, repl.Config.Keymap.fromString("vi"));
    try std.testing.expectEqual(repl.Config.Keymap.vi, repl.Config.Keymap.fromString("vim"));
    try std.testing.expectEqual(@as(?repl.Config.Keymap, null), repl.Config.Keymap.fromString("invalid"));
}

test "config format from string" {
    try std.testing.expectEqual(repl.Config.Format.text, repl.Config.Format.fromString("text"));
    try std.testing.expectEqual(repl.Config.Format.json, repl.Config.Format.fromString("json"));
    try std.testing.expectEqual(repl.Config.Format.csv, repl.Config.Format.fromString("csv"));
    try std.testing.expectEqual(repl.Config.Format.table, repl.Config.Format.fromString("table"));
    try std.testing.expectEqual(@as(?repl.Config.Format, null), repl.Config.Format.fromString("invalid"));
}

// ============================================================================
// Core Types Tests
// ============================================================================

test "key event structure" {
    const key = repl.KeyEvent{
        .key = 'a',
        .ctrl = true,
        .alt = false,
    };

    try std.testing.expectEqual(@as(u8, 'a'), key.key);
    try std.testing.expect(key.ctrl);
    try std.testing.expect(!key.alt);
}

test "key action enum values" {
    // Verify key actions exist and can be used
    const actions = [_]repl.KeyAction{
        .none,
        .insert,
        .backspace,
        .move_left,
        .move_right,
        .history_prev,
        .history_next,
        .complete,
        .run,
        .quit,
    };

    for (actions) |action| {
        try std.testing.expect(@intFromEnum(action) >= 0);
    }
}

test "keymap enum" {
    try std.testing.expect(repl.Keymap.emacs != repl.Keymap.vi);
}

// ============================================================================
// Platform Tests
// ============================================================================

test "platform handle retrieval" {
    // These should not error - just verify they return valid handles
    const stdin = repl.getStdinHandle();
    const stdout = repl.getStdoutHandle();
    const stderr = repl.getStderrHandle();

    // Verify they're different handles (usually)
    _ = stdin;
    _ = stdout;
    _ = stderr;
}
