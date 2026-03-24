# Contributing to Zig REPL Library

Thank you for your interest in contributing to the Zig REPL Library! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- [Zig](https://ziglang.org/download/) (0.14.0 or later)
- Git
- A terminal emulator for testing

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://gitlab.com/devnw/zig/repl.git
   cd repl
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run tests:
   ```bash
   zig build test
   ```

4. Run the example:
   ```bash
   zig build run
   ```

## Code Style

### Formatting

- Use `zig fmt` for all Zig code
- Run `zig fmt --check src/` before committing
- The CI pipeline enforces formatting

### Naming Conventions

- Functions: `camelCase`
- Types: `PascalCase`
- Constants: `SCREAMING_SNAKE_CASE` or `snake_case`
- Fields: `snake_case`

### Documentation

- Add doc comments (`///`) to all public functions and types
- Include usage examples in doc comments where helpful
- Keep comments up-to-date with code changes

## Making Changes

### Workflow

1. Check existing [issues](https://gitlab.com/devnw/zig/repl/-/issues) for related work
2. Create a new branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```
3. Make your changes
4. Write or update tests
5. Run the test suite
6. Commit with clear messages
7. Push and create a merge request

### Commit Messages

Use clear, descriptive commit messages:

```
feat: add transpose character command

- Implement Ctrl+T for Emacs mode
- Implement xp for Vi mode
- Handle edge cases at line boundaries

Closes #7
```

Prefix commits with:
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test additions or changes
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

### Testing

- Add tests for new features
- Update tests when changing behavior
- Ensure all tests pass before submitting
- Test on multiple platforms if possible

### Merge Requests

1. Fill out the merge request template
2. Link related issues
3. Ensure CI passes
4. Request review from maintainers
5. Address review feedback
6. Squash commits if requested

## Project Structure

```
repl/
├── src/
│   ├── core.zig         # Main REPL implementation
│   ├── repl.zig         # Public API root (re-exports for consumers)
│   ├── input.zig        # Terminal input parsing (ANSI/control sequences)
│   ├── render.zig       # Rendering calculation utilities
│   ├── search.zig       # Interactive reverse-incremental search
│   ├── history.zig      # Command history
│   ├── completion.zig   # Tab completion
│   ├── parse.zig        # Input parsing utilities
│   ├── platform.zig     # Platform abstraction
│   ├── keymap_emacs.zig # Emacs keybindings
│   ├── keymap_vi.zig    # Vi keybindings
│   ├── config.zig       # Configuration types
│   ├── text_utils.zig   # Shared text helpers (word boundaries, sanitization)
│   └── example.zig      # Example application
├── examples/
│   ├── basic.zig        # Basic REPL usage
│   ├── calculator.zig   # Calculator example
│   ├── colors.zig       # Color output example
│   ├── completions.zig  # Tab completion example
│   ├── history.zig      # History usage example
│   ├── multiline.zig    # Multi-line input example
│   ├── shell.zig        # Shell-like REPL example
│   └── vi_mode.zig      # Vi keybinding example
├── tests/
│   └── integration.zig  # Integration tests
├── docs/
│   ├── ROADMAP.md       # Project roadmap
│   ├── CONTRIBUTING.md  # This file
│   └── ARCHITECTURE.md  # Architecture overview
├── build.zig            # Build configuration
└── README.md            # Project overview
```

## Issue Tracking

All work is tracked in GitLab issues organized by milestones:

- [Phase 1: Quality & Testing](https://gitlab.com/devnw/zig/repl/-/milestones/1)
- [Phase 2: Enhanced Input](https://gitlab.com/devnw/zig/repl/-/milestones/2)
- [Phase 3: Terminal Features](https://gitlab.com/devnw/zig/repl/-/milestones/3)
- [Phase 4: Platform & Extensibility](https://gitlab.com/devnw/zig/repl/-/milestones/4)
- [v1.0 Release](https://gitlab.com/devnw/zig/repl/-/milestones/5)

See [ROADMAP.md](./ROADMAP.md) for the full list of planned work.

## Getting Help

- Check existing issues and documentation
- Open a new issue for bugs or feature requests
- Tag issues appropriately with labels

## Code of Conduct

Be respectful and constructive in all interactions. We welcome contributors of all experience levels.

## License

By contributing, you agree that your contributions will be licensed under the Apache License, Version 2.0.
