# Zig REPL Library

A cross-platform, feature-rich REPL (Read-Eval-Print Loop) library for Zig.

## Status

| Aspect | Info |
|--------|------|
| API Stability | Beta |
| Zig Version | 0.16.x |
| Platforms | Linux, macOS, Windows |

## Features

- **Raw terminal mode** with cleanup on normal exit, on SIGTERM/SIGHUP, and on suspend/resume (SIGTSTP/SIGCONT)
- **Emacs and Vi keybindings** - switch modes at runtime
- **Persistent command history** - saved to disk, searchable
- **Tab completion** - extensible completion system
- **Multi-line input** - automatic detection of incomplete statements
- **Undo support** -- bounded undo stack with Ctrl+_ (Emacs) and u (Vi normal mode)
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
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();

    try repl.Repl.run(.{
        .allocator = da.allocator(),
        .prompt = ">>> ",
        .run_fn = runCommand,
    });
}

fn runCommand(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    input: []const u8,
    _: *repl.HistoryStore,
) anyerror!bool {
    if (std.mem.eql(u8, input, "quit")) {
        return false; // exit REPL
    }

    const out = repl.terminalWriter();
    try out.print("You entered: {s}\n", .{input});
    return true; // continue REPL
}
```

## Configuration Options

The `Repl.run()` function accepts a configuration struct with these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `allocator` | `Allocator` | required | Memory allocator |
| `prompt` | `[]const u8` | `"> "` | Primary prompt string |
| `continuation_prompt` | `[]const u8` | `"... "` | Multi-line continuation prompt |
| `keymap` | `Keymap` | `.emacs` | `.emacs` or `.vi` |
| `history_enabled` | `bool` | `true` | Enable command history |
| `app_name` | `[]const u8` | `"repl"` | Application name (used for default history file path) |
| `history_path` | `?[]const u8` | `null` | Custom history file path (overrides default) |
| `max_history` | `usize` | `5000` | Maximum history entries kept in memory and persisted |
| `run_fn` | `?RunFn` | `null` | Command handler callback (see Quick Start) |
| `is_complete_fn` | `?IsCompleteFn` | `null` | Multi-line input detection |
| `complete_fn` | `?CompleteFn` | `null` | Tab completion callback |
| `welcome_fn` | `?WelcomeFn` | `null` | Welcome message printer (called before entering raw mode) |
| `verbose` | `bool` | `false` | Show verbose output |
| `user_context` | `?*anyopaque` | `null` | User context passed to `run_fn` callback |

> **Note:** `Repl.Options` is for REPL initialization. The separate `Config` type
> (`repl.Config`) provides application-level persistence via `loadFromFile()` and
> `saveToFile()`. These are separate by design -- `Config` is not auto-loaded by
> `Repl.run()`. Applications that want config file support should load a `Config`,
> then map its fields to `Options` when calling `Repl.run()`.

## Terminal Output

The library provides `TerminalWriter` for proper terminal output in raw mode.
Use the convenience function `repl.terminalWriter()` or construct one from a file handle:

```zig
const repl = @import("repl");

// Create a TerminalWriter for stdout
const out = repl.terminalWriter();

// Basic output (handles \n -> \r\n conversion automatically)
try out.write("Hello, world!\n");
try out.writeLine("This adds a newline");
try out.print("Formatted: {d}\n", .{42});

// Colored output
try out.writeColored(.green, "Success!");
try out.writeColored(.red, "Error!");

// Styled output (style, color, text)
try out.writeBold("Important");
try out.writeStyled(.italic, .default, "Emphasized");

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

The `HistoryStore` is passed to your `run_fn` callback:

```zig
fn runCommand(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    input: []const u8,
    hist: *repl.HistoryStore,
) anyerror!bool {
    // Show history count
    const count = hist.count();
    _ = count;

    // Search history
    if (hist.searchBackward("pattern", null)) |result| {
        _ = result;
    }

    // Clear history
    hist.clear();

    return true;
}
```

History is automatically saved if `history_path` is configured or if `history_enabled`
is `true` (which uses a default path based on `app_name`).

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
| Ctrl+_ | Undo last edit |
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
| u | Undo last edit (normal mode) |
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

- `Repl` - Main REPL runner (call `Repl.run(options)` to start)
- `ReplState` - Internal state (exposed for advanced use)
- `Config` - Application configuration (persistent via `loadFromFile`/`saveToFile`)
- `KeyEvent` - Parsed key events
- `KeyAction` - Internal action enum for key dispatch (not returned by user callbacks)
- `Keymap` - Keymap selection (`.emacs` or `.vi`)
- `CompleteFn` - Tab completion callback function type
- `SyntheticKey` - Named constants for special keys (Insert, Delete, Page Up, Page Down)
- `Format` - Output format enum (`.text`, `.json`, `.csv`, `.table`)

### Platform Utilities

- `TerminalWriter` - Terminal output with raw mode handling
- `terminalWriter()` - Create a TerminalWriter for a given file handle
- `Color` - Terminal colors
- `Style` - Text styles (bold, dim, italic, underline)
- `getStdinHandle()` - Get a handle to stdin for direct I/O operations
- `getStdoutHandle()` - Get a handle to stdout for direct I/O operations
- `getStderrHandle()` - Get a handle to stderr for direct I/O operations
- `isStdinTty()` - Check if stdin is a TTY
- `isStdoutTty()` - Check if stdout is a TTY
- `isStderrTty()` - Check if stderr is a TTY

### History

- `HistoryStore` - Command history storage and search

### Completion

- `CompletionContext` - Completion results builder

### Parsing

- `isComplete(input)` - Check if input is a complete statement
- `isBalanced(input)` - Check bracket balance
- `needsContinuation(input)` - Check for continuation operators

### Version

- `version` - Library version string (e.g., `"0.1.0"`)
- `version_major` - Major version number
- `version_minor` - Minor version number
- `version_patch` - Patch version number

## Building

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Check formatting
zig fmt --check src/ tests/ examples/ build.zig
```

## Observability

This library ships an optional OpenTelemetry seam, gated behind
`-Dwith_otel=<bool>` (default `false`).

When `-Dwith_otel=false` (the default) the seam collapses to a
comptime-known no-op: every public helper in `repl.observability`
returns a zero-sized `Span{}`, the otel dependency is never resolved,
and the produced artifact contains zero otel symbols (verified by
`otel/scripts/verify-consumer-noop.sh`).

When `-Dwith_otel=true`, every accepted REPL line emits **one
internal-kind span per eval cycle**. Each span is named `"repl.eval"`
and reports outcome via `setStatus(.ok | .@"error", "")`. On failure,
a bounded-cardinality `repl.eval.error_kind` attribute is attached
carrying the handler's error name (e.g. `"OutOfMemory"`,
`"InvalidInput"`) -- never the error message body.

**PII INVARIANT:** the raw user-typed input is *never* attached as a
span attribute. REPL inputs may contain passwords, tokens, file paths,
or other sensitive data, so the seam refuses to accept user-supplied
strings on its public surface. Operators who want richer telemetry on
specific commands (where the command vocabulary is fixed and bounded)
can attach their own attributes via the underlying
`otel.api.trace.Span.setStringAttribute` after the seam returns.

Bootstrap from your application entry point:

```zig
const std = @import("std");
const repl = @import("repl");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var otel = try repl.observability_init.Otel.init(gpa.allocator(), "my-repl");
    otel.installGlobals();
    defer otel.deinit();

    try repl.Repl.run(.{
        .allocator = gpa.allocator(),
        .prompt = ">>> ",
        .run_fn = runCommand, // each accepted line emits one "repl.eval" span
    });
}
```

Configuration follows the OpenTelemetry environment-variable contract
(`OTEL_SERVICE_NAME`, `OTEL_TRACES_SAMPLER`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
etc). Defaults: `parentbased_traceidratio` @ 5%, OTLP/HTTP to
`http://localhost:4318`.

Verification gates (all three must pass):

```bash
zig build test                                              # default flag = false
zig build test -Dwith_otel=true                             # flag on
otel/scripts/verify-consumer-noop.sh --worktree <name> repl # symbol-leak check
```

See [otel/docs/integration/RECIPE.md](https://gitlab.com/devnw/zig/otel/-/blob/main/docs/integration/RECIPE.md)
for the full recipe.

## Roadmap

Development is tracked through GitLab issues organized into milestones:

### Current Priorities

| Priority | Issue | Description |
|----------|-------|-------------|
| High | [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) | Add comprehensive unit tests |
| High | [#12](https://gitlab.com/devnw/zig/repl/-/issues/12) | Add Unicode and wide character support |
| High | [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) | Write API documentation |
| Medium | [#10](https://gitlab.com/devnw/zig/repl/-/issues/10) | Add syntax highlighting support |
| Medium | [#3](https://gitlab.com/devnw/zig/repl/-/issues/3) | Add integration tests |

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
- [#10](https://gitlab.com/devnw/zig/repl/-/issues/10) - Syntax highlighting
- [#12](https://gitlab.com/devnw/zig/repl/-/issues/12) - Unicode support
- [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) - API documentation

## Documentation

- [Architecture Overview](docs/ARCHITECTURE.md) - Internal design
- [Contributing Guide](docs/CONTRIBUTING.md) - How to contribute
- [Roadmap](docs/ROADMAP.md) - Development plans

## License

Apache-2.0 License - See LICENSE file for details.
