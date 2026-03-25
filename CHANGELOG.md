# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-01-26

### Changed
- Add release-semantic CI/CD component (v1.7.1) for GitLab releases
- Add default runner tags (company, linux) to CI configuration
- Add release stage to CI pipeline

## [0.1.0] - 2026-01-24

### Added
- Merge request template for consistent contribution workflow
- Issue templates for bug reports, feature requests, and questions
- Initial REPL library implementation with cross-platform support (Linux, macOS, Windows)
- Raw terminal mode with proper cleanup on exit/signals
- Emacs keybindings with runtime mode switching
  - Ctrl+A/E for line navigation
  - Ctrl+B/F for cursor movement
  - Ctrl+D for delete/EOF
  - Ctrl+K/U/W for kill operations
  - Ctrl+Y for yank (paste)
  - Ctrl+P/N for history navigation
  - Ctrl+R for reverse history search
  - Ctrl+L for screen clear
  - Tab for completion
- Vi keybindings support
  - Normal/insert mode switching
  - h/l for movement
  - 0/$ for line navigation
  - w/b for word movement
  - x for delete, dd for delete line
  - j/k for history navigation
  - / for history search
- Persistent command history with disk storage
- History search functionality (forward and backward)
- Extensible tab completion system with CompletionContext
- Multi-line input with automatic incomplete statement detection
- Built-in parsing utilities: isBalanced(), needsContinuation(), isComplete()
- Bracketed paste mode for proper pasted text handling
- Colored output with 16-color support
  - Standard colors: black, red, green, yellow, blue, magenta, cyan, white
  - Bright variants for all colors
- Semantic output helpers: writeError(), writeWarning(), writeSuccess(), writeInfo()
- Text styling support: bold, dim, italic, underline
- TerminalWriter for proper terminal output in raw mode
- Platform detection utilities: isStdinTty(), isStdoutTty()
- Configurable options:
  - Custom prompts and continuation prompts
  - Maximum history entries
  - Color enable/disable
  - Keymap selection
  - User context passing to callbacks
- Comprehensive documentation including README, Architecture, Contributing guide, and Roadmap

### Changed
- Updated CI catalog components to v1.7.1
- Licensed under Apache-2.0 for open source release

### Security
- Added GitLab native Secret Detection
- Enabled Advanced SAST and Dependency Scanning

### Infrastructure
- CI/CD pipeline using DevNW CI Catalog components
- SAST (Static Application Security Testing) integration
- Secret Detection configuration
- SBOM (Software Bill of Materials) generation
- Multi-platform builds with Windows marked as allow_failure
- Company runners with Alpine Linux support
- Code coverage support via CI catalog v1.6.0

[Unreleased]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.1...HEAD
[0.1.1]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.0...v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/repl/-/releases/v0.1.0
