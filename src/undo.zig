// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Undo stack for edit buffer state snapshots.
//!
//! Each entry captures a copy of the edit buffer and cursor position at the
//! time of a destructive edit. Popping an entry restores the buffer to its
//! state before that edit.

const std = @import("std");

/// A fixed-capacity stack of buffer snapshots used to implement undo.
///
/// Each entry owns an allocated copy of the buffer contents at the time
/// of the snapshot. When the stack exceeds `max_entries`, the oldest
/// entry is evicted and freed.
pub const UndoStack = struct {
    entries: std.ArrayList(UndoEntry),
    allocator: std.mem.Allocator,
    max_entries: usize,

    /// A snapshot of the edit buffer and cursor position.
    pub const UndoEntry = struct {
        /// Allocated copy of the buffer contents. The caller of `pop` must
        /// free this slice via the stack's allocator when done with it.
        buffer: []const u8,
        /// Cursor position at the time the snapshot was taken.
        cursor: usize,
    };

    /// Default maximum number of undo entries retained.
    pub const default_max_entries: usize = 100;

    /// Initialize an undo stack.
    pub fn init(allocator: std.mem.Allocator, max_entries: usize) UndoStack {
        return .{
            .entries = std.ArrayList(UndoEntry).initCapacity(allocator, 0) catch unreachable, // Safe: initCapacity(0) never allocates
            .allocator = allocator,
            .max_entries = max_entries,
        };
    }

    /// Free all entry buffers and the underlying storage.
    pub fn deinit(self: *UndoStack) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.buffer);
        }
        self.entries.deinit(self.allocator);
    }

    /// Snapshot the current buffer and cursor onto the stack.
    ///
    /// If the stack is at capacity, the oldest entry is evicted first.
    pub fn push(self: *UndoStack, buffer: []const u8, cursor: usize) !void {
        // Evict oldest entry if at capacity.
        if (self.entries.items.len >= self.max_entries and self.max_entries > 0) {
            const evicted = self.entries.orderedRemove(0);
            self.allocator.free(evicted.buffer);
        }

        const buf_copy = try self.allocator.dupe(u8, buffer);
        errdefer self.allocator.free(buf_copy);
        try self.entries.append(self.allocator, .{
            .buffer = buf_copy,
            .cursor = cursor,
        });
    }

    /// Like `push`, but takes ownership of an already-allocated buffer
    /// slice instead of duplicating.  The caller must not free `owned_buffer`
    /// after calling this -- the stack owns it.  On error the caller still
    /// owns the buffer.
    pub fn pushOwned(self: *UndoStack, owned_buffer: []const u8, cursor: usize) !void {
        if (self.entries.items.len >= self.max_entries and self.max_entries > 0) {
            const evicted = self.entries.orderedRemove(0);
            self.allocator.free(evicted.buffer);
        }

        try self.entries.append(self.allocator, .{
            .buffer = owned_buffer,
            .cursor = cursor,
        });
    }

    /// Pop the most recent entry. Returns `null` if the stack is empty.
    ///
    /// The caller is responsible for freeing `entry.buffer` via the
    /// stack's allocator when done with the returned data.
    pub fn pop(self: *UndoStack) ?UndoEntry {
        if (self.entries.items.len == 0) return null;
        return self.entries.pop();
    }

    /// Remove and free all entries.
    pub fn clear(self: *UndoStack) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.buffer);
        }
        self.entries.clearRetainingCapacity();
    }

    /// Return the number of entries on the stack.
    pub fn len(self: *const UndoStack) usize {
        return self.entries.items.len;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "push and pop returns correct state" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try stack.push("hello", 5);

    const entry = stack.pop().?;
    defer allocator.free(entry.buffer);

    try std.testing.expectEqualStrings("hello", entry.buffer);
    try std.testing.expectEqual(@as(usize, 5), entry.cursor);
}

test "multiple pushes and pops in sequence" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try stack.push("first", 0);
    try stack.push("second", 3);
    try stack.push("third", 5);

    try std.testing.expectEqual(@as(usize, 3), stack.len());

    // Pop returns in LIFO order.
    const e3 = stack.pop().?;
    defer allocator.free(e3.buffer);
    try std.testing.expectEqualStrings("third", e3.buffer);
    try std.testing.expectEqual(@as(usize, 5), e3.cursor);

    const e2 = stack.pop().?;
    defer allocator.free(e2.buffer);
    try std.testing.expectEqualStrings("second", e2.buffer);
    try std.testing.expectEqual(@as(usize, 3), e2.cursor);

    const e1 = stack.pop().?;
    defer allocator.free(e1.buffer);
    try std.testing.expectEqualStrings("first", e1.buffer);
    try std.testing.expectEqual(@as(usize, 0), e1.cursor);
}

test "pop on empty stack returns null" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try std.testing.expect(stack.pop() == null);
}

test "overflow eviction drops oldest entry" {
    const allocator = std.testing.allocator;
    const max = 3;
    var stack = UndoStack.init(allocator, max);
    defer stack.deinit();

    try stack.push("a", 0);
    try stack.push("b", 1);
    try stack.push("c", 2);
    try std.testing.expectEqual(@as(usize, 3), stack.len());

    // Pushing a fourth entry should evict "a".
    try stack.push("d", 3);
    try std.testing.expectEqual(@as(usize, 3), stack.len());

    const e3 = stack.pop().?;
    defer allocator.free(e3.buffer);
    try std.testing.expectEqualStrings("d", e3.buffer);

    const e2 = stack.pop().?;
    defer allocator.free(e2.buffer);
    try std.testing.expectEqualStrings("c", e2.buffer);

    const e1 = stack.pop().?;
    defer allocator.free(e1.buffer);
    try std.testing.expectEqualStrings("b", e1.buffer);

    // "a" was evicted; stack is now empty.
    try std.testing.expect(stack.pop() == null);
}

test "deinit frees all memory" {
    // Using testing.allocator which detects leaks.
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);

    try stack.push("leak check 1", 0);
    try stack.push("leak check 2", 5);
    try stack.push("leak check 3", 10);

    // deinit must free all three buffer copies and the ArrayList storage.
    stack.deinit();
}

test "clear frees all entries and resets length" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try stack.push("one", 0);
    try stack.push("two", 1);
    try stack.push("three", 2);
    try std.testing.expectEqual(@as(usize, 3), stack.len());

    stack.clear();

    try std.testing.expectEqual(@as(usize, 0), stack.len());
    try std.testing.expect(stack.pop() == null);
}

test "push empty buffer" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try stack.push("", 0);
    try std.testing.expectEqual(@as(usize, 1), stack.len());

    const entry = stack.pop().?;
    defer allocator.free(entry.buffer);
    try std.testing.expectEqualStrings("", entry.buffer);
    try std.testing.expectEqual(@as(usize, 0), entry.cursor);
}

test "push after pop works correctly" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    try stack.push("first", 0);
    const e1 = stack.pop().?;
    defer allocator.free(e1.buffer);

    try stack.push("second", 3);
    const e2 = stack.pop().?;
    defer allocator.free(e2.buffer);

    try std.testing.expectEqualStrings("second", e2.buffer);
    try std.testing.expectEqual(@as(usize, 3), e2.cursor);
}

test "pushOwned takes ownership of buffer" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, UndoStack.default_max_entries);
    defer stack.deinit();

    // Allocate a buffer that pushOwned will take ownership of.
    const owned = try allocator.dupe(u8, "owned data");
    try stack.pushOwned(owned, 7);

    try std.testing.expectEqual(@as(usize, 1), stack.len());

    const entry = stack.pop().?;
    defer allocator.free(entry.buffer);
    try std.testing.expectEqualStrings("owned data", entry.buffer);
    try std.testing.expectEqual(@as(usize, 7), entry.cursor);
}

test "pushOwned evicts oldest when at capacity" {
    const allocator = std.testing.allocator;
    var stack = UndoStack.init(allocator, 2);
    defer stack.deinit();

    try stack.push("first", 0);
    const owned = try allocator.dupe(u8, "second");
    try stack.pushOwned(owned, 1);
    const owned2 = try allocator.dupe(u8, "third");
    try stack.pushOwned(owned2, 2);

    // "first" was evicted.
    try std.testing.expectEqual(@as(usize, 2), stack.len());

    const e2 = stack.pop().?;
    defer allocator.free(e2.buffer);
    try std.testing.expectEqualStrings("third", e2.buffer);

    const e1 = stack.pop().?;
    defer allocator.free(e1.buffer);
    try std.testing.expectEqualStrings("second", e1.buffer);
}
