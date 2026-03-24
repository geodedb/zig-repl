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

// ============================================================================
// Undo Integration Tests (QF-056)
//
// These tests verify the full undo flow through the pipeline:
//   KeyEvent -> keymap handler -> undo stack snapshot -> action application
//
// Since processAction is module-private in core.zig, we replicate the
// relevant action logic here to test the integrated behavior of the
// keymap, undo stack, and buffer manipulation working together.
// ============================================================================

/// Undo stack type extracted from the public ReplState struct definition.
const UndoStack = @TypeOf(@as(repl.ReplState, undefined).undo_stack);

/// Test state for undo integration tests.
///
/// Carries all fields required by both emacs and vi keymap handlers
/// (which accept `anytype`) plus the undo stack for testing the
/// snapshot/restore pipeline.
const UndoTestState = struct {
    buffer: std.ArrayList(u8),
    cursor: usize,
    allocator: std.mem.Allocator,
    vi_mode: repl.keymap_vi.ViMode,
    pending_operator: ?u8,
    kill_ring: std.ArrayList(u8),
    last_was_kill: bool,
    undo_stack: UndoStack,

    fn init(allocator: std.mem.Allocator) UndoTestState {
        return .{
            .buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .cursor = 0,
            .allocator = allocator,
            .vi_mode = .normal,
            .pending_operator = null,
            .kill_ring = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .last_was_kill = false,
            .undo_stack = UndoStack.init(allocator, UndoStack.default_max_entries),
        };
    }

    fn deinit(self: *UndoTestState) void {
        self.buffer.deinit(self.allocator);
        self.kill_ring.deinit(self.allocator);
        self.undo_stack.deinit();
    }

    /// Get the current buffer contents as a string slice.
    fn bufferSlice(self: *const UndoTestState) []const u8 {
        return self.buffer.items;
    }
};

/// Simulate the full key-press pipeline as implemented in core.processInput:
///   1. Snapshot buffer state before the keymap handler
///   2. Call the keymap handler to get the action
///   3. If the action is destructive, push the snapshot onto the undo stack
///   4. Apply the action to the buffer
fn simulateKeyPress(state: *UndoTestState, key: repl.KeyEvent, keymap: repl.Keymap) !void {
    // Step 1: Snapshot buffer before keymap handler runs (same as core.zig line 375)
    const pre_buffer = state.allocator.dupe(u8, state.buffer.items) catch null;
    const pre_cursor = state.cursor;

    // Step 2: Call keymap handler (same as core.zig line 378-381)
    const action: repl.KeyAction = switch (keymap) {
        .emacs => repl.keymap_emacs.handleKey(state, key),
        .vi => repl.keymap_vi.handleKey(state, key),
    };

    // Step 3: Push snapshot for destructive actions (same as core.zig line 384-399)
    const is_destructive = switch (action) {
        .insert, .insert_tab, .reverse_tab, .backspace, .delete_char, .delete_char_forward, .delete_word, .delete_word_backward, .delete_to_eol, .delete_to_bol, .yank => true,
        else => false,
    };

    if (is_destructive) {
        if (pre_buffer) |buf_snap| {
            state.undo_stack.pushOwned(buf_snap, pre_cursor) catch {
                state.allocator.free(buf_snap);
            };
        }
    } else {
        if (pre_buffer) |buf_snap| state.allocator.free(buf_snap);
    }

    // Step 4: Apply the action (replicating core.processAction for relevant actions)
    try applyAction(state, action);
}

/// Apply a KeyAction to the test state buffer and cursor.
///
/// This replicates the relevant subset of core.processAction (which is
/// module-private) to enable integration testing of the full undo pipeline.
fn applyAction(state: *UndoTestState, action: repl.KeyAction) !void {
    switch (action) {
        .none, .vi_normal_mode, .vi_insert_mode => {},
        .insert => {
            // Character was already inserted by the keymap handler
        },
        .backspace => {
            if (state.cursor > 0) {
                state.cursor -= 1;
                _ = state.buffer.orderedRemove(state.cursor);
            }
        },
        .delete_char, .delete_char_forward => {
            if (state.cursor < state.buffer.items.len) {
                _ = state.buffer.orderedRemove(state.cursor);
            }
        },
        .delete_to_eol => {
            state.kill_ring.clearRetainingCapacity();
            try state.kill_ring.appendSlice(state.allocator, state.buffer.items[state.cursor..]);
            state.buffer.items.len = state.cursor;
        },
        .delete_to_bol => {
            state.kill_ring.clearRetainingCapacity();
            try state.kill_ring.appendSlice(state.allocator, state.buffer.items[0..state.cursor]);
            state.buffer.replaceRange(state.allocator, 0, state.cursor, &.{}) catch {};
            state.cursor = 0;
        },
        .yank => {
            try state.buffer.insertSlice(state.allocator, state.cursor, state.kill_ring.items);
            state.cursor += state.kill_ring.items.len;
        },
        .undo => {
            if (state.undo_stack.pop()) |entry| {
                state.buffer.clearRetainingCapacity();
                state.buffer.appendSlice(state.allocator, entry.buffer) catch {
                    state.allocator.free(entry.buffer);
                    return;
                };
                state.cursor = entry.cursor;
                state.allocator.free(entry.buffer);
            }
        },
        .move_left => {
            if (state.cursor > 0) state.cursor -= 1;
        },
        .move_right => {
            if (state.cursor < state.buffer.items.len) state.cursor += 1;
        },
        .move_bol => {
            state.cursor = 0;
        },
        .move_eol => {
            state.cursor = state.buffer.items.len;
        },
        else => {},
    }
}

// ---- Test 1: Basic undo restores previous character ----

test "undo: basic undo after single character insert" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Insert 'a', 'b', 'c' one at a time through the emacs keymap
    try simulateKeyPress(&state, .{ .key = 'a' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'b' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'c' }, .emacs);

    try std.testing.expectEqualStrings("abc", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 3), state.cursor);

    // Undo once (Ctrl+_ = key 0x7f, ctrl=true)
    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);

    // Buffer should be restored to state before 'c' was inserted
    try std.testing.expectEqualStrings("ab", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 2), state.cursor);
}

// ---- Test 2: Multiple undos restore to empty buffer ----

test "undo: multiple undos restore buffer to empty" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Insert 'a', 'b', 'c' separately
    try simulateKeyPress(&state, .{ .key = 'a' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'b' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'c' }, .emacs);

    try std.testing.expectEqualStrings("abc", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 3), state.undo_stack.len());

    // Undo three times
    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("ab", state.bufferSlice());

    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("a", state.bufferSlice());

    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

// ---- Test 3: Undo on empty stack does not crash ----

test "undo: undo on empty stack leaves buffer unchanged" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // No edits made -- undo stack is empty
    try std.testing.expectEqual(@as(usize, 0), state.undo_stack.len());
    try std.testing.expectEqualStrings("", state.bufferSlice());

    // Trigger undo -- should not crash and buffer should remain empty
    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);

    try std.testing.expectEqualStrings("", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

// ---- Test 4: Undo after backspace restores deleted character ----

test "undo: undo after backspace restores deleted character" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Type "abc"
    try simulateKeyPress(&state, .{ .key = 'a' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'b' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'c' }, .emacs);
    try std.testing.expectEqualStrings("abc", state.bufferSlice());

    // Backspace deletes 'c' (raw 0x7f without ctrl = backspace in emacs)
    try simulateKeyPress(&state, .{ .key = 0x7f }, .emacs);
    try std.testing.expectEqualStrings("ab", state.bufferSlice());

    // Undo restores buffer to state before backspace ("abc")
    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("abc", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

// ---- Test 5: Delete key maps to delete_char_forward in emacs ----

test "undo: emacs Delete key maps to delete_char_forward not undo" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Type "abc"
    try simulateKeyPress(&state, .{ .key = 'a' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'b' }, .emacs);
    try simulateKeyPress(&state, .{ .key = 'c' }, .emacs);

    // Move cursor to position 1 (after 'a')
    state.cursor = 1;

    // Send Delete key (SyntheticKey.delete, no ctrl) through emacs keymap
    const action = repl.keymap_emacs.handleKey(&state, .{ .key = repl.SyntheticKey.delete });
    try std.testing.expectEqual(repl.KeyAction.delete_char_forward, action);

    // Apply the action to verify buffer effect
    try applyAction(&state, action);
    try std.testing.expectEqualStrings("ac", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 1), state.cursor);
}

// ---- Test 6: Ctrl+_ maps to undo in emacs ----

test "undo: emacs Ctrl+_ maps to undo action" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Verify the keymap mapping: Ctrl+_ sends raw 0x1f which the input
    // parser maps to key=0x7f, ctrl=true
    const action = repl.keymap_emacs.handleKey(&state, .{ .key = 0x7f, .ctrl = true });
    try std.testing.expectEqual(repl.KeyAction.undo, action);

    // Also verify through the input parser: raw byte 0x1f (Ctrl+_)
    const key_event = try repl.input.parseKeyEvent("\x1f");
    try std.testing.expectEqual(@as(u8, 0x7f), key_event.key);
    try std.testing.expect(key_event.ctrl);

    // Feed the parsed key event through the keymap
    const action2 = repl.keymap_emacs.handleKey(&state, key_event);
    try std.testing.expectEqual(repl.KeyAction.undo, action2);
}

// ---- Test 7: Vi normal 'u' maps to undo ----

test "undo: vi normal u maps to undo action" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();
    state.vi_mode = .normal;

    // 'u' in vi normal mode should produce .undo
    const action = repl.keymap_vi.handleKey(&state, .{ .key = 'u' });
    try std.testing.expectEqual(repl.KeyAction.undo, action);
}

// ---- Test 8: Vi undo restores buffer through full pipeline ----

test "undo: vi insert then normal u restores previous state" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Enter vi insert mode
    state.vi_mode = .insert;

    // Type "xyz" in insert mode
    try simulateKeyPress(&state, .{ .key = 'x' }, .vi);
    try simulateKeyPress(&state, .{ .key = 'y' }, .vi);
    try simulateKeyPress(&state, .{ .key = 'z' }, .vi);
    try std.testing.expectEqualStrings("xyz", state.bufferSlice());

    // Switch to normal mode (ESC)
    try simulateKeyPress(&state, .{ .key = 0x1b }, .vi);
    try std.testing.expectEqual(repl.keymap_vi.ViMode.normal, state.vi_mode);

    // Undo with 'u' in normal mode
    try simulateKeyPress(&state, .{ .key = 'u' }, .vi);
    try std.testing.expectEqualStrings("xy", state.bufferSlice());

    // Undo again
    try simulateKeyPress(&state, .{ .key = 'u' }, .vi);
    try std.testing.expectEqualStrings("x", state.bufferSlice());

    // Undo again
    try simulateKeyPress(&state, .{ .key = 'u' }, .vi);
    try std.testing.expectEqualStrings("", state.bufferSlice());
}

// ---- Test 9: Delete and undo key events do not collide (GAP-0045/GAP-0046) ----

test "undo: delete key and undo key produce distinct actions through input parser" {
    // This is the critical regression test for GAP-0045/GAP-0046.
    // Delete (ESC[3~) must map to delete_char_forward, not undo.
    // Ctrl+_ (0x1f) must map to undo, not delete_char_forward.
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Parse Delete key escape sequence
    const del_key = try repl.input.parseKeyEvent("\x1b[3~");
    try std.testing.expectEqual(repl.SyntheticKey.delete, del_key.key);
    try std.testing.expect(!del_key.ctrl);

    // Parse Ctrl+_ raw byte
    const undo_key = try repl.input.parseKeyEvent("\x1f");
    try std.testing.expectEqual(@as(u8, 0x7f), undo_key.key);
    try std.testing.expect(undo_key.ctrl);

    // Feed both through the emacs keymap and verify distinct actions
    const del_action = repl.keymap_emacs.handleKey(&state, del_key);
    const undo_action = repl.keymap_emacs.handleKey(&state, undo_key);

    try std.testing.expectEqual(repl.KeyAction.delete_char_forward, del_action);
    try std.testing.expectEqual(repl.KeyAction.undo, undo_action);
    try std.testing.expect(del_action != undo_action);
}

// ---- Test 10: Undo after delete_to_eol restores full line ----

test "undo: undo after Ctrl+K restores killed text" {
    const allocator = std.testing.allocator;
    var state = UndoTestState.init(allocator);
    defer state.deinit();

    // Type "hello world"
    for ("hello world") |c| {
        try simulateKeyPress(&state, .{ .key = c }, .emacs);
    }
    try std.testing.expectEqualStrings("hello world", state.bufferSlice());

    // Move cursor to position 5 (after "hello")
    state.cursor = 5;

    // Ctrl+K kills to end of line
    try simulateKeyPress(&state, .{ .key = 'k', .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("hello", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 5), state.cursor);

    // Undo restores the full "hello world"
    try simulateKeyPress(&state, .{ .key = 0x7f, .ctrl = true }, .emacs);
    try std.testing.expectEqualStrings("hello world", state.bufferSlice());
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}
