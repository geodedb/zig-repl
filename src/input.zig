// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Terminal input parsing.
//!
//! Translates raw terminal byte sequences (ANSI escape codes, control
//! characters, printable keys) into structured `KeyEvent` values.

const std = @import("std");

/// Key event from terminal input
pub const KeyEvent = struct {
    key: u8,
    ctrl: bool = false,
    alt: bool = false,
};

/// Parse a raw terminal byte sequence into a KeyEvent.
pub fn parseKeyEvent(data: []const u8) !KeyEvent {
    if (data.len == 0) return error.NoInput;

    if (data[0] == 0x1b) {
        if (data.len > 1) {
            if (data[1] == '[') {
                if (data.len > 2) {
                    // Extended sequences: ESC [ n ~
                    if (data.len > 3 and data[3] == '~') {
                        return switch (data[2]) {
                            '2' => KeyEvent{ .key = 0x02 }, // Insert
                            '3' => KeyEvent{ .key = 0x7f, .ctrl = true }, // Delete
                            '5' => KeyEvent{ .key = 0x05 }, // Page Up
                            '6' => KeyEvent{ .key = 0x06 }, // Page Down
                            else => KeyEvent{ .key = data[2] },
                        };
                    }

                    // Modifier sequences: ESC [ 1 ; n X
                    if (data.len > 5 and data[2] == '1' and data[3] == ';') {
                        const modifier = data[4];
                        const key_char = data[5];

                        const is_ctrl = (modifier == '5' or modifier == '7');
                        const is_alt = (modifier == '3' or modifier == '7');

                        return switch (key_char) {
                            'A' => KeyEvent{ .key = 'p', .ctrl = true, .alt = is_alt },
                            'B' => KeyEvent{ .key = 'n', .ctrl = true, .alt = is_alt },
                            'C' => if (is_ctrl) KeyEvent{ .key = 'f', .alt = true } else KeyEvent{ .key = 'f', .ctrl = true },
                            'D' => if (is_ctrl) KeyEvent{ .key = 'b', .alt = true } else KeyEvent{ .key = 'b', .ctrl = true },
                            'H' => KeyEvent{ .key = 'a', .ctrl = true, .alt = is_ctrl },
                            'F' => KeyEvent{ .key = 'e', .ctrl = true, .alt = is_ctrl },
                            else => KeyEvent{ .key = key_char },
                        };
                    }

                    // Standard arrow keys
                    return switch (data[2]) {
                        'A' => KeyEvent{ .key = 'p', .ctrl = true }, // Up
                        'B' => KeyEvent{ .key = 'n', .ctrl = true }, // Down
                        'C' => KeyEvent{ .key = 'f', .ctrl = true }, // Right
                        'D' => KeyEvent{ .key = 'b', .ctrl = true }, // Left
                        'H' => KeyEvent{ .key = 'a', .ctrl = true }, // Home
                        'F' => KeyEvent{ .key = 'e', .ctrl = true }, // End
                        'Z' => KeyEvent{ .key = 'i', .ctrl = true, .alt = true }, // Shift+Tab
                        else => KeyEvent{ .key = data[2] },
                    };
                }
            } else if (data[1] == 'O') {
                if (data.len > 2) {
                    return switch (data[2]) {
                        'H' => KeyEvent{ .key = 'a', .ctrl = true }, // Home
                        'F' => KeyEvent{ .key = 'e', .ctrl = true }, // End
                        'A' => KeyEvent{ .key = 'p', .ctrl = true }, // Up
                        'B' => KeyEvent{ .key = 'n', .ctrl = true }, // Down
                        'C' => KeyEvent{ .key = 'f', .ctrl = true }, // Right
                        'D' => KeyEvent{ .key = 'b', .ctrl = true }, // Left
                        else => KeyEvent{ .key = data[2] },
                    };
                }
            } else if ((data[1] & 0x7f) >= 'a' and (data[1] & 0x7f) <= 'z') {
                return KeyEvent{ .key = @intCast(data[1] & 0x7f), .alt = true };
            } else if (data[1] >= 'A' and data[1] <= 'Z') {
                return KeyEvent{ .key = @intCast(data[1] - 'A' + 'a'), .alt = true };
            }
        }
        return KeyEvent{ .key = 0x1b };
    }

    // Control characters
    if (data[0] < 0x20) {
        return KeyEvent{ .key = @intCast(data[0] + 'a' - 1), .ctrl = true };
    }

    return KeyEvent{ .key = data[0] };
}

/// Get the number of bytes consumed by the key event starting at data[0].
pub fn getKeyEventLength(data: []const u8) usize {
    if (data.len == 0) return 0;

    if (data[0] == 0x1b) {
        if (data.len > 1 and data[1] == '[') {
            if (data.len > 3 and data[3] == '~') return 4;
            if (data.len > 5 and data[2] == '1' and data[3] == ';') return 6;
            if (data.len > 2) return 3;
            return 2;
        } else if (data.len > 1 and data[1] == 'O') {
            if (data.len > 2) return 3;
            return 2;
        } else if (data.len > 1) {
            return 2;
        }
        return 1;
    }

    return 1;
}

test "key event parsing" {
    const regular = try parseKeyEvent("a");
    try std.testing.expect(regular.key == 'a');
    try std.testing.expect(!regular.ctrl);
    try std.testing.expect(!regular.alt);

    const up = try parseKeyEvent("\x1b[A");
    try std.testing.expect(up.key == 'p');
    try std.testing.expect(up.ctrl);
}

// =============================================================================
// Regular character tests
// =============================================================================

test "parseKeyEvent regular character 'a'" {
    const ev = try parseKeyEvent("a");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent regular character 'z'" {
    const ev = try parseKeyEvent("z");
    try std.testing.expectEqual(@as(u8, 'z'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent regular character space" {
    const ev = try parseKeyEvent(" ");
    try std.testing.expectEqual(@as(u8, ' '), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent regular character tilde" {
    const ev = try parseKeyEvent("~");
    try std.testing.expectEqual(@as(u8, '~'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Control character tests
// =============================================================================

test "parseKeyEvent Ctrl+A (0x01)" {
    const ev = try parseKeyEvent("\x01");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent Ctrl+C (0x03)" {
    const ev = try parseKeyEvent("\x03");
    try std.testing.expectEqual(@as(u8, 'c'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent Ctrl+D (0x04)" {
    const ev = try parseKeyEvent("\x04");
    try std.testing.expectEqual(@as(u8, 'd'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent Ctrl+E (0x05)" {
    const ev = try parseKeyEvent("\x05");
    try std.testing.expectEqual(@as(u8, 'e'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Arrow key tests (ESC [ X)
// =============================================================================

test "parseKeyEvent arrow up ESC[A" {
    const ev = try parseKeyEvent("\x1b[A");
    try std.testing.expectEqual(@as(u8, 'p'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent arrow down ESC[B" {
    const ev = try parseKeyEvent("\x1b[B");
    try std.testing.expectEqual(@as(u8, 'n'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent arrow right ESC[C" {
    const ev = try parseKeyEvent("\x1b[C");
    try std.testing.expectEqual(@as(u8, 'f'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent arrow left ESC[D" {
    const ev = try parseKeyEvent("\x1b[D");
    try std.testing.expectEqual(@as(u8, 'b'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Delete key test (ESC [ 3 ~)
// =============================================================================

test "parseKeyEvent delete key ESC[3~" {
    const ev = try parseKeyEvent("\x1b[3~");
    try std.testing.expectEqual(@as(u8, 0x7f), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Home/End tests (ESC [ H / ESC [ F)
// =============================================================================

test "parseKeyEvent home ESC[H" {
    const ev = try parseKeyEvent("\x1b[H");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent end ESC[F" {
    const ev = try parseKeyEvent("\x1b[F");
    try std.testing.expectEqual(@as(u8, 'e'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// ESC O sequence tests
// =============================================================================

test "parseKeyEvent ESC O H (home)" {
    const ev = try parseKeyEvent("\x1bOH");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent ESC O F (end)" {
    const ev = try parseKeyEvent("\x1bOF");
    try std.testing.expectEqual(@as(u8, 'e'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent ESC O A (up)" {
    const ev = try parseKeyEvent("\x1bOA");
    try std.testing.expectEqual(@as(u8, 'p'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent ESC O D (left)" {
    const ev = try parseKeyEvent("\x1bOD");
    try std.testing.expectEqual(@as(u8, 'b'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Modifier sequence tests (ESC [ 1 ; n X)
// =============================================================================

test "parseKeyEvent Ctrl+Right ESC[1;5C" {
    const ev = try parseKeyEvent("\x1b[1;5C");
    // modifier '5' is ctrl: is_ctrl=true, key_char='C' -> KeyEvent{ .key='f', .alt=true }
    try std.testing.expectEqual(@as(u8, 'f'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

test "parseKeyEvent Ctrl+Left ESC[1;5D" {
    const ev = try parseKeyEvent("\x1b[1;5D");
    // modifier '5' is ctrl: is_ctrl=true, key_char='D' -> KeyEvent{ .key='b', .alt=true }
    try std.testing.expectEqual(@as(u8, 'b'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

test "parseKeyEvent Alt+Right ESC[1;3C" {
    const ev = try parseKeyEvent("\x1b[1;3C");
    // modifier '3' is alt: is_ctrl=false, key_char='C' -> KeyEvent{ .key='f', .ctrl=true }
    try std.testing.expectEqual(@as(u8, 'f'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent Ctrl+Up ESC[1;5A" {
    const ev = try parseKeyEvent("\x1b[1;5A");
    // modifier '5': is_ctrl=true, is_alt=false, key_char='A' -> key='p', ctrl=true, alt=false
    try std.testing.expectEqual(@as(u8, 'p'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent Ctrl+Alt+Right ESC[1;7C" {
    const ev = try parseKeyEvent("\x1b[1;7C");
    // modifier '7': is_ctrl=true, is_alt=true, key_char='C' -> key='f', alt=true (is_ctrl branch)
    try std.testing.expectEqual(@as(u8, 'f'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

// =============================================================================
// Alt-letter tests
// =============================================================================

test "parseKeyEvent Alt+a (ESC followed by 'a')" {
    const ev = try parseKeyEvent("\x1ba");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

test "parseKeyEvent Alt+z (ESC followed by 'z')" {
    const ev = try parseKeyEvent("\x1bz");
    try std.testing.expectEqual(@as(u8, 'z'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

test "parseKeyEvent Alt+A (ESC followed by uppercase)" {
    const ev = try parseKeyEvent("\x1bA");
    try std.testing.expectEqual(@as(u8, 'a'), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(ev.alt);
}

// =============================================================================
// Bare ESC test
// =============================================================================

test "parseKeyEvent bare ESC (single 0x1b byte)" {
    const ev = try parseKeyEvent("\x1b");
    try std.testing.expectEqual(@as(u8, 0x1b), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Empty input test
// =============================================================================

test "parseKeyEvent empty input returns error" {
    const result = parseKeyEvent("");
    try std.testing.expectError(error.NoInput, result);
}

// =============================================================================
// Extended sequences: Insert, Page Up, Page Down
// =============================================================================

test "parseKeyEvent insert ESC[2~" {
    const ev = try parseKeyEvent("\x1b[2~");
    try std.testing.expectEqual(@as(u8, 0x02), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent page up ESC[5~" {
    const ev = try parseKeyEvent("\x1b[5~");
    try std.testing.expectEqual(@as(u8, 0x05), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

test "parseKeyEvent page down ESC[6~" {
    const ev = try parseKeyEvent("\x1b[6~");
    try std.testing.expectEqual(@as(u8, 0x06), ev.key);
    try std.testing.expect(!ev.ctrl);
    try std.testing.expect(!ev.alt);
}

// =============================================================================
// Shift+Tab test
// =============================================================================

test "parseKeyEvent Shift+Tab ESC[Z" {
    const ev = try parseKeyEvent("\x1b[Z");
    try std.testing.expectEqual(@as(u8, 'i'), ev.key);
    try std.testing.expect(ev.ctrl);
    try std.testing.expect(ev.alt);
}

// =============================================================================
// getKeyEventLength tests
// =============================================================================

test "getKeyEventLength empty input" {
    try std.testing.expectEqual(@as(usize, 0), getKeyEventLength(""));
}

test "getKeyEventLength single regular character" {
    try std.testing.expectEqual(@as(usize, 1), getKeyEventLength("a"));
}

test "getKeyEventLength single control character" {
    try std.testing.expectEqual(@as(usize, 1), getKeyEventLength("\x01"));
}

test "getKeyEventLength arrow key ESC[A is 3 bytes" {
    try std.testing.expectEqual(@as(usize, 3), getKeyEventLength("\x1b[A"));
}

test "getKeyEventLength arrow key ESC[D is 3 bytes" {
    try std.testing.expectEqual(@as(usize, 3), getKeyEventLength("\x1b[D"));
}

test "getKeyEventLength delete ESC[3~ is 4 bytes" {
    try std.testing.expectEqual(@as(usize, 4), getKeyEventLength("\x1b[3~"));
}

test "getKeyEventLength modifier sequence ESC[1;5C is 6 bytes" {
    try std.testing.expectEqual(@as(usize, 6), getKeyEventLength("\x1b[1;5C"));
}

test "getKeyEventLength ESC O sequence is 3 bytes" {
    try std.testing.expectEqual(@as(usize, 3), getKeyEventLength("\x1bOH"));
}

test "getKeyEventLength alt-letter ESC+a is 2 bytes" {
    try std.testing.expectEqual(@as(usize, 2), getKeyEventLength("\x1ba"));
}

test "getKeyEventLength bare ESC is 1 byte" {
    try std.testing.expectEqual(@as(usize, 1), getKeyEventLength("\x1b"));
}

test "getKeyEventLength ESC[ without third byte is 2 bytes" {
    try std.testing.expectEqual(@as(usize, 2), getKeyEventLength("\x1b["));
}

test "getKeyEventLength ESC O without third byte is 2 bytes" {
    try std.testing.expectEqual(@as(usize, 2), getKeyEventLength("\x1bO"));
}

// =============================================================================
// Fuzz tests -- coverage-guided testing for input parser robustness
// =============================================================================

test "fuzz parseKeyEvent" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) anyerror!void {
            // parseKeyEvent must handle any non-empty input without crashing.
            // Empty input returns error.NoInput which is expected, not a crash.
            if (input.len == 0) return;
            _ = try parseKeyEvent(input);
        }
    }.testOne, .{
        .corpus = &.{
            "a",
            "\x1b[A",
            "\x1b[3~",
            "\x1b[1;5C",
            "\x1bOH",
            "\x1ba",
            "\x1b",
            "\x01",
            " ",
            "~",
        },
    });
}

test "fuzz getKeyEventLength" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) anyerror!void {
            // getKeyEventLength must handle any input without crashing and
            // must return a value <= input.len (or 0 for empty input).
            const len = getKeyEventLength(input);
            if (input.len == 0) {
                try std.testing.expectEqual(@as(usize, 0), len);
            } else {
                try std.testing.expect(len >= 1);
                try std.testing.expect(len <= input.len);
            }
        }
    }.testOne, .{
        .corpus = &.{
            "",
            "a",
            "\x1b[A",
            "\x1b[3~",
            "\x1b[1;5C",
            "\x1bOH",
            "\x1ba",
            "\x1b",
            "\x01",
        },
    });
}
