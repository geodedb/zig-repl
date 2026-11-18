# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.23] - 2026-11-17

### Changed

- otel v0.1.28 -> v0.1.30, whose tree (slog, json, config, yaml, metrics, tls, grpc-zig v0.1.16) is on thread-pool v0.2.11, so this library and its consumers resolve a single otel and thread-pool (SONNY-6630).

## [0.1.17] - 2026-09-15

### Changed

- Converge grpc_zig v0.1.10 (GAP-0838 diamond sync).

## [0.1.16] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5, config v0.1.13 (GAP-0838 diamond sync).

## [0.1.15] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5 (GAP-0838 diamond sync).

## [0.1.10] - 2026-06-12

Audit Cycle 4: closes the residual security findings and the high-priority
quality bugs from the 2026-06-12 full audit.

### Security
- Drop C1 control bytes (raw 0x80–0x9F and UTF-8-encoded U+0080–U+009F) in the
  history ingest filter and render path, closing 8-bit CSI/OSC terminal-escape
  injection from crafted history entries (GAP-0074)
- Strip 8-bit CSI and zero-padded bracketed-paste markers in
  `sanitizePasteContent`, closing the pastejacking residual (GAP-0075)
- Restore terminal state if `enterRawMode` fails after entering raw mode
  (errdefer) (#147)
- Widen `parse.zig` bracket-depth counters to `i64` (GAP-0076)

### Fixed
- Paste and Vi direct-mutation operators (dd/dw/db/de/cc) are now undoable
  (#146)
- `Config.max_history` is honored via `Repl.Options.max_history` instead of
  being silently ignored (#149)
- `handleSearch` cancels gracefully on transient I/O errors instead of tearing
  down the REPL (#153)
- Restore terminal state on suspend/resume via SIGTSTP/SIGCONT handlers (#155)
- Fix a pre-existing test that deadlocked `zig build test`'s `--listen` runner
  by dispatching terminal-I/O actions

### Changed
- Assert and document the `cursor <= buffer.len` invariant on the public
  `ReplState` (#151)
- Extract a shared `killRange` helper (8 call sites) (#154)
- Add `HistoryStore` boundary tests; doc, constant, and comment hygiene
  (#156, #112-class items)

## [0.1.9] - 2026-06-12

### Fixed
- Harden config/history file permissions: implement a real `compat.chmod`
  (POSIX `setPermissions`), create config files via atomic temp-file +
  `0o600`, and re-tighten pre-existing history files on open (NEW-001/002/005)
- Persist bracketed-paste state across `read()` boundaries so markers torn
  across reads are reassembled; add a read-span safety bound (ADV-001)
- Restore the OpenTelemetry seam so `-Dwith_otel=true` is functional again,
  reverting the hardcoded `enabled=false` workaround (NEW-006)
- Harden `sync_diamond_deps.py --cascade --apply`: repo allowlist, interactive
  confirmation token, and tag-signature/commit verification before push (#124)

### Changed
- Single-source the version from `build.zig.zon` (derive `repl.version*`
  constants at build time) so the manifest is the only source of truth
- Pin the CI Docker base image by digest (`debian:bookworm-slim@sha256:…`)
- Lazy undo snapshots: pure cursor moves no longer dup/free the buffer

## [0.1.8] - 2026-06-02

### Changed
- Converge `tls` dependency onto v0.1.9 via diamond-dependency sync

## [0.1.7] - 2026-05-31

### Changed
- Converge dependency-graph pins across sibling packages

## [0.1.6] - 2026-05-02

### Changed
- Converge sibling dependency pins

## [0.1.5] - 2026-05-02

### Fixed
- Hardcode observability `enabled=false` to work around a Zig 0.16
  `build_options` module-deduplication error (later restored in 0.1.9)

## [0.1.4] - 2026-05-02

### Changed
- Release bump with tagged sibling dependencies

## [0.1.3] - 2026-05-02

### Changed
- Release bump with tagged sibling dependencies

## [0.1.2] - 2026-05-02

### Added
- OpenTelemetry observability seam gated behind `-Dwith_otel` (no-op when
  disabled), with init helper and enabled-mode eval-span smoke test
- Diamond-dependency detector and pre-commit hook

### Changed
- Migrate to Zig 0.16.0 (`src/compat.zig` std.Io compatibility shim); update
  README and `build.zig.zon` minimum version to 0.16.0
- Pin CI Zig 0.16.0 toolchain by SHA-256; standardize `.pre-commit-config.yaml`

### Fixed
- Close 21 audit findings across three cycles: bounds checks, persistent
  history handle, reverse-search ESC handling, dangling-pointer fix,
  arena allocator, SIGWINCH handling, single-pass render, and O(n) dedup

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

[Unreleased]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.10...HEAD
[0.1.10]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.9...v0.1.10
[0.1.9]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.8...v0.1.9
[0.1.8]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.7...v0.1.8
[0.1.7]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.6...v0.1.7
[0.1.6]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.5...v0.1.6
[0.1.5]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.4...v0.1.5
[0.1.4]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.3...v0.1.4
[0.1.3]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.2...v0.1.3
[0.1.2]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.1...v0.1.2
[0.1.1]: https://gitlab.com/devnw/zig/repl/-/compare/v0.1.0...v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/repl/-/releases/v0.1.0
