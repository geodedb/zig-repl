# Architecture Overview

This document describes the internal architecture of the Zig REPL Library.

## Module Structure

```text
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
    │         │              │              │            │
    ▼         ▼              ▼              ▼            ▼
┌────────┐ ┌──────────┐ ┌───────────┐ ┌──────────┐ ┌────────┐ ┌────────┐
│history │ │input.zig │ │keymap_*.  │ │render.zig│ │platform│ │config  │
│ .zig   │ │          │ │  zig      │ │          │ │ .zig   │ │ .zig   │
│        │ │parseKey  │ │           │ │renderLine│ │        │ │        │
│History │ │ Event()  │ │handleKey()│ │calcVisual│ │enterRaw│ │Config  │
│ Store  │ │escape seq│ │Emacs/Vi   │ │ Lines()  │ │getTerm │ │load/   │
│load/   │ │ handling │ │modes      │ │cursor    │ │ Width  │ │ save   │
│ save   │ │          │ │           │ │ calc     │ │isStdin │ │XDG/    │
│search  │ │          │ │           │ │          │ │ Tty    │ │AppData │
└────────┘ └──────────┘ └───────────┘ └──────────┘ └────────┘ └────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
     ┌─────────────┐  ┌────────────┐  ┌─────────────┐
     │completion.  │  │ search.zig │  │  undo.zig   │
     │  zig        │  │            │  │             │
     │Completion   │  │handleSearch│  │ UndoStack   │
     │ Context     │  │reverse     │  │ push/pop    │
     │addCandidate │  │ incremental│  │ bounded     │
     └─────────────┘  └────────────┘  └─────────────┘
              │                              │
              ▼                              ▼
     ┌─────────────┐              ┌──────────────────┐
     │  parse.zig  │              │  text_utils.zig  │
     │             │              │                  │
     │ isComplete  │              │ findWordStart    │
     │ isBalanced  │              │ findWordEnd      │
     └─────────────┘              │ sanitizePaste    │
                                  │ pathSafety       │
                                  └──────────────────┘
```

## Key Components

### core.zig - Main REPL Engine

> **Size note:** core.zig exceeds the 800-line soft guideline at ~1194 non-test
> lines (grew ~+288 in Audit Cycle 3 from the bracketed-paste carry-over state
> machine and the lazy-undo mutation predictor: `processReadBuffer`,
> `carryOverSplit`, `isMarkerPrefix`, `keyMayMutate`/`emacsKeyMayMutate`/
> `viKeyMayMutate`). Input parsing, rendering, search, text utilities, and undo
> have already been extracted into dedicated modules. The remaining code is
> tightly coupled REPL state management (buffer, cursor, action dispatch, paste
> handling) that does not decompose further without fragmenting the core event
> loop. Tracked as QF-050 (Accepted).

The core module contains:

- **`Repl`**: Main entry point with `run()` function
- **`ReplState`**: Session state including buffer, cursor, history reference
- **`processInput()`**: Key event loop that reads and processes input
- **`renderPrompt()`**: Display rendering with line wrapping support
- **`KeyEvent`**: Parsed keyboard input
- **`KeyAction`**: Actions returned from key handlers

**Input Processing Pipeline:**

```text
Raw bytes → parseKeyEvent() [input.zig] → KeyEvent → handleKey() [keymap_*.zig] → KeyAction → processAction()
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

### config.zig - Configuration Management

Application-level persistent configuration:

- **`Config`**: Settings struct with keymap, format, history, colors, timing, verbose, max_history
- **`loadDefault()`**: Returns defaults with color detection via `platform.shouldUseColor()`
- **`loadFromFile()`**: Parses a `key=value` config file (supports `repl.` prefixed keys)
- **`saveToFile()`**: Serializes settings to a config file with `0o600` permissions
- **`getDefaultConfigPath()`**: Resolves platform-specific paths (XDG on Linux, `~/Library/Preferences` on macOS, `%APPDATA%` on Windows)

Config is a consumer-facing API — applications load it and map fields to `Repl.Options` before calling `Repl.run()`.

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

### input.zig - Terminal Input Parsing

Handles low-level terminal input:

- **`parseKeyEvent()`**: Converts raw byte sequences into `KeyEvent` values
- ANSI escape sequence decoding (cursor keys, function keys, etc.)
- Control character recognition
- Bracketed paste sequence detection

Called by `core.zig`'s input loop to translate raw stdin bytes into structured key events.

### render.zig - Prompt Rendering

Calculates display layout for prompt and buffer content:

- Visual line and cursor position calculation
- Line wrapping logic that accounts for prompt width
- Rendering coordinate math used by `core.zig`'s `renderPrompt()`

Separated from `core.zig` to isolate pure calculation from I/O side effects.

### search.zig - Reverse Incremental Search

Implements Ctrl+R interactive history search:

- **`handleSearch()`**: State machine for search mode input
- Incremental matching against history entries
- Search buffer management and result display
- Integrates with `history.zig`'s `HistoryStore` for backward search

### text_utils.zig - Shared Text Helpers

Common text manipulation utilities used across modules:

- **`findWordStart()` / `findWordEnd()`**: Word boundary detection for Ctrl+W, Alt+B, Alt+F, and Vi word motions
- **`sanitizePasteContent()`**: Filters unsafe control characters from bracketed paste input
- **`isUnsafeControlChar()`**: Identifies control characters that should not appear in the edit buffer
- **`appendHistoryFiltered()`**: Path-safe history appending

Extracted from `core.zig` to keep shared logic in one place and reduce module size.

### undo.zig - Undo Stack

Bounded undo stack for edit buffer snapshots:

- **`UndoStack`**: Fixed-capacity stack of `(buffer, cursor)` snapshots
- **`push()`**: Duplicates and saves buffer state before destructive edits
- **`pushOwned()`**: Takes ownership of an already-allocated buffer snapshot
- **`pop()`**: Restores the most recent snapshot (LIFO order)
- Oldest entries are automatically evicted when the stack exceeds `max_entries`

Used by `core.zig` to snapshot state before kill, delete, and paste operations.
Triggered by Ctrl+_ in Emacs mode and `u` in Vi normal mode.

## Data Flow

### Normal Input

```text
1. User types character
2. stdin.read() receives bytes
3. parseKeyEvent() creates KeyEvent
4. handleKey() (Emacs/Vi) returns KeyAction
5. processAction() modifies ReplState
6. renderPrompt() updates display
```

### Command Execution

```text
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

```text
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
