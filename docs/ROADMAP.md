# Roadmap

This document outlines the development roadmap for the Zig REPL Library. All items are tracked as GitLab issues and organized into milestones.

## Milestones

### [Phase 1: Quality & Testing](https://gitlab.com/devnw/zig/repl/-/milestones/1)

Establish comprehensive test coverage, CI/CD pipeline, and quality metrics.

| Issue | Title | Priority | Status |
|-------|-------|----------|--------|
| [#1](https://gitlab.com/devnw/zig/repl/-/issues/1) | Set up CI/CD pipeline | High | Open |
| [#2](https://gitlab.com/devnw/zig/repl/-/issues/2) | Add comprehensive unit tests | High | Open |
| [#3](https://gitlab.com/devnw/zig/repl/-/issues/3) | Add integration tests | Medium | Open |
| [#4](https://gitlab.com/devnw/zig/repl/-/issues/4) | Set up test coverage reporting | Medium | Open |

### [Phase 2: Enhanced Input](https://gitlab.com/devnw/zig/repl/-/milestones/2)

Improve input handling, keybindings, and editing capabilities.

| Issue | Title | Priority | Status |
|-------|-------|----------|--------|
| [#5](https://gitlab.com/devnw/zig/repl/-/issues/5) | Implement full undo/redo stack | Medium | Open |
| [#6](https://gitlab.com/devnw/zig/repl/-/issues/6) | Add configurable keybindings | Low | Open |
| [#7](https://gitlab.com/devnw/zig/repl/-/issues/7) | Implement transpose characters (Ctrl+T) | Low | Open |
| [#8](https://gitlab.com/devnw/zig/repl/-/issues/8) | Add word case operations | Low | Open |
| [#9](https://gitlab.com/devnw/zig/repl/-/issues/9) | Implement numeric argument prefixes | Low | Open |
| [#24](https://gitlab.com/devnw/zig/repl/-/issues/24) | Add history deduplication | Medium | Open |
| [#25](https://gitlab.com/devnw/zig/repl/-/issues/25) | Add history timestamps | Low | Open |
| [#26](https://gitlab.com/devnw/zig/repl/-/issues/26) | Implement history import/export | Low | Open |

### [Phase 3: Terminal Features](https://gitlab.com/devnw/zig/repl/-/milestones/3)

Advanced terminal features including colors, Unicode, and display improvements.

| Issue | Title | Priority | Status |
|-------|-------|----------|--------|
| [#10](https://gitlab.com/devnw/zig/repl/-/issues/10) | Add syntax highlighting support | Medium | Open |
| [#11](https://gitlab.com/devnw/zig/repl/-/issues/11) | Implement 256-color and true color support | Medium | Open |
| [#12](https://gitlab.com/devnw/zig/repl/-/issues/12) | Add Unicode and wide character support | High | Open |
| [#13](https://gitlab.com/devnw/zig/repl/-/issues/13) | Implement terminal resize handling | Medium | Open |
| [#14](https://gitlab.com/devnw/zig/repl/-/issues/14) | Add mouse support | Low | Open |

### [Phase 4: Platform & Extensibility](https://gitlab.com/devnw/zig/repl/-/milestones/4)

Platform-specific improvements and extensibility features.

| Issue | Title | Priority | Status |
|-------|-------|----------|--------|
| [#15](https://gitlab.com/devnw/zig/repl/-/issues/15) | Improve Windows terminal support | High | Open |
| [#16](https://gitlab.com/devnw/zig/repl/-/issues/16) | Add plugin/hook system | Low | Open |
| [#17](https://gitlab.com/devnw/zig/repl/-/issues/17) | Implement async input handling | Medium | Open |
| [#18](https://gitlab.com/devnw/zig/repl/-/issues/18) | Add configurable tab width | Low | Open |
| [#19](https://gitlab.com/devnw/zig/repl/-/issues/19) | Improve signal handling | Medium | Open |

### [v1.0 Release](https://gitlab.com/devnw/zig/repl/-/milestones/5)

First stable release with complete documentation and full test coverage.

| Issue | Title | Priority | Status |
|-------|-------|----------|--------|
| [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) | Write API documentation | High | Open |
| [#21](https://gitlab.com/devnw/zig/repl/-/issues/21) | Create usage examples | High | Open |
| [#22](https://gitlab.com/devnw/zig/repl/-/issues/22) | Write architecture documentation | Medium | Open |
| [#23](https://gitlab.com/devnw/zig/repl/-/issues/23) | Create contribution guide | Medium | Open |

## Priority Definitions

- **Critical**: Security or blocking issues requiring immediate attention
- **High**: Important for next release, should be prioritized
- **Medium**: Should be addressed, but not blocking
- **Low**: Nice to have, can be deferred

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for information on how to contribute to this project.

Want to work on an issue? Comment on it to let others know you're interested!
