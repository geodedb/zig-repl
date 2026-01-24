# Architecture Overview

This document describes the internal architecture of the Zig REPL Library.

## Module Structure

```
┌─────────────────────────────────────────────────────────────┐
│                        Application                          │
│                    (Uses Repl.run())                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        repl.zig                             │
│                   (Public API exports)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        core.zig                             │
│              (Main REPL loop and state)                     │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  ReplState  │  │ processInput│  │    renderPrompt     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌───────────────┐    ┌─────────────────┐    ┌───────────────┐
│  history.zig  │    │  keymap_*.zig   │    │ platform.zig  │
│               │    │                 │    │               │
│ HistoryStore  │    │ handleKey()     │    │ enterRawMode  │
│ load/save     │    │ Emacs/Vi modes  │    │ getTermWidth  │
│ search        │    │                 │    │ isStdinTty    │
└───────────────┘    └─────────────────┘    └───────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │ completion.zig  │
                     │                 │
                     │ CompletionCtx   │
                     │ addCandidate    │
                     └─────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │   parse.zig     │
                     │                 │
                     │ isComplete      │
                     │ isBalanced      │
                     └─────────────────┘
```

## Key Components

### core.zig - Main REPL Engine

The core module contains:

- **`Repl`**: Main entry point with `run()` function
- **`ReplState`**: Session state including buffer, cursor, history reference
- **`processInput()`**: Key event loop that reads and processes input
- **`renderPrompt()`**: Display rendering with line wrapping support
- **`KeyEvent`**: Parsed keyboard input
- **`KeyAction`**: Actions returned from key handlers

**Input Processing Pipeline:**
```
Raw bytes → parseKeyEvent() → KeyEvent → handleKey() → KeyAction → processAction()
```

### platform.zig - Platform Abstraction

Handles platform-specific terminal operations:

- Raw terminal mode entry/exit
- Terminal size detection
- TTY detection
- Signal handling
- Color capability detection

Supports Linux, macOS, and Windows.

### history.zig - Command History

Manages persistent command history:

- **`HistoryStore`**: History storage and search
- File-based persistence (XDG paths on Unix, AppData on Windows)
- Forward and backward search
- Configurable maximum entries

### keymap_emacs.zig / keymap_vi.zig - Keybindings

Implement keymap-specific behavior:

- Map `KeyEvent` to `KeyAction`
- Maintain mode state (for Vi)
- Handle compound commands

### completion.zig - Tab Completion

Provides completion infrastructure:

- **`CompletionContext`**: Collects completion candidates
- Prefix matching
- Candidate cycling
- Word boundary detection

### parse.zig - Input Parsing

Utilities for analyzing input:

- Bracket/brace/paren balancing
- Continuation detection (trailing operators)
- Multi-line input support

## Data Flow

### Normal Input
```
1. User types character
2. stdin.read() receives bytes
3. parseKeyEvent() creates KeyEvent
4. handleKey() (Emacs/Vi) returns KeyAction
5. processAction() modifies ReplState
6. renderPrompt() updates display
```

### Command Execution
```
1. User presses Enter
2. KeyAction.run returned
3. Multi-line buffer assembled
4. isComplete() checks if statement complete
5. If complete:
   a. History updated
   b. run_fn callback invoked
   c. Buffer cleared
6. If incomplete:
   a. Continuation mode entered
   b. Continue collecting input
```

### Tab Completion
```
1. User presses Tab
2. KeyAction.complete returned
3. complete_fn callback populates CompletionContext
4. Current candidate inserted
5. Subsequent Tabs cycle candidates
```

## Extension Points

Applications customize behavior through:

1. **`run_fn`**: Command execution callback
2. **`complete_fn`**: Tab completion callback
3. **`is_complete_fn`**: Multi-line detection callback
4. **`welcome_fn`**: Startup message callback
5. **Configuration options**: Prompts, history, keymap, etc.

## Related Issues

- [#22 - Write architecture documentation](https://gitlab.com/devnw/zig/repl/-/issues/22)
- [#16 - Add plugin/hook system](https://gitlab.com/devnw/zig/repl/-/issues/16)
- [#17 - Implement async input handling](https://gitlab.com/devnw/zig/repl/-/issues/17)
