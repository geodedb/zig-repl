# Zig REPL Library

A cross-platform, feature-rich REPL (Read-Eval-Print Loop) library for Zig.

## Status

| Aspect | Info |
|--------|------|
| API Stability | Beta |
| Zig Version | 0.14.0+ |
| Platforms | Linux, macOS, Windows |

## Features

- **Raw terminal mode** with proper cleanup on exit/signals
- **Emacs and Vi keybindings** - switch modes at runtime
- **Persistent command history** - saved to disk, searchable
- **Tab completion** - extensible completion system
- **Multi-line input** - automatic detection of incomplete statements
- **Bracketed paste mode** - properly handles pasted text
- **Colored output** - 16-color support with semantic helpers
- **Cross-platform** - Linux, macOS, and Windows support

## Installation

Add the library to your `build.zig.zon`:

```zig
.dependencies = .{
    .repl = .{
        .url = "https://gitlab.com/devnw/zig/repl/-/archive/main/repl-main.tar.gz",
        // Add the hash after first build attempt
    },
},
```

Then in your `build.zig`:

```zig
const repl_dep = b.dependency("repl", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("repl", repl_dep.module("repl"));
```

## Quick Start

```zig
const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try repl.Repl.run(.{
        .allocator = gpa.allocator(),
        .prompt = ">>> ",
        .execute_fn = executeCommand,
    });
}

fn executeCommand(
    input: []const u8,
    out: repl.TerminalWriter,
    _: *repl.HistoryStore,
    _: *anyopaque,
) !repl.KeyAction {
    if (std.mem.eql(u8, input, "quit")) {
        return .quit;
    }

    try out.write("You entered: ");
    try out.writeLine(input);
    return .none;
}
```

## Configuration Options

The `Repl.run()` function accepts a configuration struct with these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `allocator` | `Allocator` | required | Memory allocator |
| `prompt` | `[]const u8` | `"> "` | Primary prompt string |
| `continuation_prompt` | `[]const u8` | `"... "` | Multi-line continuation prompt |
| `execute_fn` | `ExecuteFn` | required | Callback for command execution |
| `complete_fn` | `?CompleteFn` | `null` | Tab completion callback |
| `is_complete_fn` | `?IsCompleteFn` | `null` | Multi-line input detection |
| `history_file` | `?[]const u8` | `null` | Path to persist history |
| `max_history` | `usize` | `1000` | Maximum history entries |
| `use_color` | `bool` | `true` | Enable colored output |
| `keymap` | `Keymap` | `.emacs` | `.emacs` or `.vi` |
| `context` | `*anyopaque` | undefined | User context passed to callbacks |

## Terminal Output

The library provides `TerminalWriter` for proper terminal output in raw mode:

```zig
fn executeCommand(
    input: []const u8,
    out: repl.TerminalWriter,
    history: *repl.HistoryStore,
    ctx: *anyopaque,
) !repl.KeyAction {
    // Basic output (handles \n -> \r\n conversion automatically)
    try out.write("Hello, world!\n");
    try out.writeLine("This adds a newline");
    try out.print("Formatted: {d}\n", .{42});

    // Colored output
    try out.writeColored(.green, "Success!");
    try out.writeColored(.red, "Error!");

    // Styled output
    try out.writeBold("Important");
    try out.writeStyled(.italic, "Emphasized");

    // Semantic helpers
    try out.writeError("Something went wrong");    // Red "Error: " prefix
    try out.writeWarning("Be careful");            // Yellow "Warning: " prefix
    try out.writeSuccess("Operation completed");   // Green message
    try out.writeInfo("FYI");                      // Cyan message

    // Screen control
    try out.clearScreen();
    try out.clearLine();

    // Manual color control
    try out.setColor(.blue);
    try out.write("Blue text");
    try out.resetStyle();

    return .none;
}
```

### Available Colors

```zig
const Color = enum {
    default,
    black, red, green, yellow, blue, magenta, cyan, white,
    bright_black, bright_red, bright_green, bright_yellow,
    bright_blue, bright_magenta, bright_cyan, bright_white,
};
```

### Available Styles

```zig
const Style = enum {
    reset, bold, dim, italic, underline,
};
```

## Tab Completion

Implement tab completion by providing a `complete_fn`:

```zig
const commands = [_][]const u8{ "help", "quit", "history", "clear", "echo" };

fn completeCommand(
    prefix: []const u8,
    ctx: *repl.CompletionContext,
) void {
    for (commands) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            ctx.addCandidate(cmd) catch {};
        }
    }
}

// In configuration:
.complete_fn = completeCommand,
```

## Multi-line Input

Enable multi-line input by providing an `is_complete_fn`:

```zig
fn isComplete(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");

    // Continue if line ends with backslash
    if (std.mem.endsWith(u8, trimmed, "\\")) return false;

    // Use built-in bracket balancing
    return repl.isBalanced(input);
}

// In configuration:
.is_complete_fn = isComplete,
```

The library provides these parsing utilities:

- `repl.isBalanced(input)` - Check if brackets/braces/parens are balanced
- `repl.needsContinuation(input)` - Check for trailing operators
- `repl.isComplete(input)` - Combined check for complete statements

## Command History

The `HistoryStore` is passed to your execute function:

```zig
fn executeCommand(
    input: []const u8,
    out: repl.TerminalWriter,
    history: *repl.HistoryStore,
    ctx: *anyopaque,
) !repl.KeyAction {
    // Show history
    const count = history.count();
    for (history.entries.items, 0..) |entry, i| {
        try out.print("{d}: {s}\n", .{ i + 1, entry });
    }

    // Search history
    if (history.searchBackward("pattern", null)) |result| {
        try out.print("Found at {d}: {s}\n", .{ result.index, result.entry });
    }

    // Clear history
    history.clear();

    return .none;
}
```

History is automatically saved if `history_file` is configured.

## Keybindings

### Emacs Mode (default)

| Key | Action |
|-----|--------|
| Ctrl+A | Move to beginning of line |
| Ctrl+E | Move to end of line |
| Ctrl+B | Move cursor left |
| Ctrl+F | Move cursor right |
| Ctrl+D | Delete character / EOF on empty line |
| Ctrl+K | Kill to end of line |
| Ctrl+U | Kill to beginning of line |
| Ctrl+W | Kill previous word |
| Ctrl+Y | Yank (paste) killed text |
| Ctrl+P | Previous history |
| Ctrl+N | Next history |
| Ctrl+R | Reverse history search |
| Ctrl+L | Clear screen |
| Tab | Trigger completion |

### Vi Mode

| Key | Action |
|-----|--------|
| Esc | Enter normal mode |
| i | Enter insert mode |
| a | Enter insert mode after cursor |
| h/l | Move left/right |
| 0/$ | Move to beginning/end of line |
| w/b | Move word forward/backward |
| x | Delete character |
| dd | Delete line |
| j/k | Next/previous history |
| / | Search history |

## Running the Example

```bash
# Build and run with Emacs bindings (default)
zig build run

# Run with Vi bindings
zig build run -- --vi

# Build and run tests
zig build test
```

## API Reference

### Core Types

- `Repl` - Main REPL runner
- `ReplState` - Internal state (exposed for advanced use)
- `KeyEvent` - Parsed key events
- `KeyAction` - Return values from execute function
- `Keymap` - Keymap selection (`.emacs` or `.vi`)
- `Format` - Terminal formatting utilities

### Platform Utilities

- `TerminalWriter` - Terminal output with raw mode handling
- `Color` - Terminal colors
- `Style` - Text styles (bold, dim, italic, underline)
- `isStdinTty()` - Check if stdin is a TTY
- `isStdoutTty()` - Check if stdout is a TTY

### History

- `HistoryStore` - Command history storage and search

### Completion

- `CompletionContext` - Completion results builder

### Parsing

- `isComplete(input)` - Check if input is a complete statement
- `isBalanced(input)` - Check bracket balance
- `needsContinuation(input)` - Check for continuation operators

## Building

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Check formatting
zig fmt --check src/
```

## Roadmap

Development is tracked through GitLab issues organized into milestones:

### Current Priorities

| Priority | Issue | Description |
|----------|-------|-------------|
| High | [#1](https://gitlab.com/devnw/zig/repl/-/issues/1) | Set up CI/CD pipeline |
| High | [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) | Add comprehensive unit tests |
| High | [#12](https://gitlab.com/devnw/zig/repl/-/issues/12) | Add Unicode and wide character support |
| High | [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) | Improve Windows terminal support |
| High | [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) | Write API documentation |

### Milestones

- **[Phase 1: Quality & Testing](https://gitlab.com/devnw/zig/repl/-/milestones/1)** - CI/CD, testing, coverage
- **[Phase 2: Enhanced Input](https://gitlab.com/devnw/zig/repl/-/milestones/2)** - Undo/redo, keybindings, history
- **[Phase 3: Terminal Features](https://gitlab.com/devnw/zig/repl/-/milestones/3)** - Colors, Unicode, mouse support
- **[Phase 4: Platform & Extensibility](https://gitlab.com/devnw/zig/repl/-/milestones/4)** - Windows, plugins, async
- **[v1.0 Release](https://gitlab.com/devnw/zig/repl/-/milestones/5)** - Documentation and stable release

See [docs/ROADMAP.md](docs/ROADMAP.md) for the complete roadmap.

## Contributing

Contributions are welcome! Please see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

Key areas where help is needed:
- [#3](https://gitlab.com/devnw/zig/repl/-/issues/3) - Integration tests
- [#12](https://gitlab.com/devnw/zig/repl/-/issues/12) - Unicode support
- [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) - Windows testing
- [#21](https://gitlab.com/devnw/zig/repl/-/issues/21) - Usage examples

## Documentation

- [Architecture Overview](docs/ARCHITECTURE.md) - Internal design
- [Contributing Guide](docs/CONTRIBUTING.md) - How to contribute
- [Roadmap](docs/ROADMAP.md) - Development plans

## License

Apache-2.0 License - See LICENSE file for details.
