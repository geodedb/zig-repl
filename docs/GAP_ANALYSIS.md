# Gap Analysis Report

**Project:** Zig REPL Library (`/home/benji/src/gl/devnw/zig/repl`)
**Date:** 2026-06-12 (Audit Cycle 3 / Gap Closure -- 8 new gaps assigned (GAP-0066..GAP-0073); 7 resolved this cycle; 2 issues closed as already-implemented (#13, #56))
**Previous audit:** 2026-03-25 (Phase 20, Audit Cycle 2, 1 open gap)
**Auditor:** Principal Engineer Audit (Claude Opus 4.6)
**Zig Version Installed:** 0.15.2
**Build Status:** Tests pass (`zig build test` exits 0)

---

## Summary

- **Total gaps identified (all time):** 73
- **Resolved (all time):** 71 (GAP-0001..GAP-0051, GAP-0053..GAP-0072)
- **Total open gaps:** 2 (GAP-0052, GAP-0073)
- **Carried forward (still open):** 1 (GAP-0052 -- blocked on #31)
- **New this cycle:** 8 (GAP-0066..GAP-0073)
- **Resolved this cycle:** 7 (GAP-0066, GAP-0067, GAP-0068, GAP-0069, GAP-0070, GAP-0071, GAP-0072)
- **Deferred this cycle:** 1 (GAP-0073 -- API docs not generated/published; low priority, remains open)
- **Previous resolved cycles:** 64 gaps resolved across Phases 1-20. All in [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)
- **Audit cycle 3 notes:** Third full audit (branch `audit-cycle-3-gap-closure`). 8 new gaps assigned; 7 resolved in this cycle across commits ec9a1dc (config/history/compat permissions), 5eae04d (sync_diamond_deps blast radius), cf50500 (observability seam + Docker digest pin), and d039c05 (processInput testability). GAP-0052 remains blocked on GitLab issue #31. GAP-0073 deferred (no generated API docs yet). Stale-tracking issues #13 (terminal resize) and #56 (processInput refactor) closed as already-implemented. Next Gap-ID: GAP-0074.

---

## Gap Index (Open Only)

| Gap-ID | Title | Category | Severity | Issue | Status |
|--------|-------|----------|----------|-------|--------|
| GAP-0052 | SECURITY.md release signing partially verified -- docs and CI enforcement missing | Security | Medium | [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) | Open (blocked) |
| GAP-0073 | API documentation partial -- inline doc comments exist but no generated/published docs | Docs | Low | [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) | Open (deferred) |

---

## Gap Priority Matrix (Open Only)

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 1 | GAP-0052 |
| Low | 1 | GAP-0073 |

---

## Detailed Gap Sections

### GAP-0048: ROADMAP.md issue #15 status stale [RESOLVED]

- **Issue:** [#107](https://gitlab.com/devnw/zig/repl/-/issues/107) (closed)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** ROADMAP.md line for issue #15 updated to Closed status.
- **Evidence:** `docs/ROADMAP.md` -- issue #15 row shows Closed.
- **Resolved date:** 2026-03-24

### GAP-0049: CONTRIBUTING.md docs/ tree incomplete [RESOLVED]

- **Issue:** [#108](https://gitlab.com/devnw/zig/repl/-/issues/108) (closed)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** All 5 missing gap analysis files added to CONTRIBUTING.md docs/ tree: GAP_ANALYSIS.md, GAP_ANALYSIS_RESOLVED.md, PERF_GAP_ANALYSIS.md, QUALITY_GAP_ANALYSIS.md, SECURITY_GAP_ANALYSIS.md.
- **Evidence:** `docs/CONTRIBUTING.md` -- docs/ section now lists all 8 files.
- **Resolved date:** 2026-03-24

### GAP-0050: README "Current Priorities" lists closed issues #1 and #15 [RESOLVED]

- **Issue:** [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed, combined with GAP-0051)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Closed issues #1, #15, and #21 removed from README.md Current Priorities and Contributing sections. Replaced with open issues.
- **Evidence:** `README.md` -- all issues listed in Current Priorities table are open in GitLab.
- **Resolved date:** 2026-03-24

### GAP-0051: README Contributing section lists closed issues #15 and #21 [RESOLVED]

- **Issue:** [#109](https://gitlab.com/devnw/zig/repl/-/issues/109) (closed, combined with GAP-0050)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Closed issues #15 and #21 removed from README Contributing section. Replaced with open issues.
- **Evidence:** `README.md` -- all issues listed in Contributing help-needed section are open in GitLab.
- **Resolved date:** 2026-03-24

### GAP-0052: SECURITY.md release signing partially verified -- docs and CI enforcement missing

- **Issue:** [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) (existing -- do NOT create duplicate)
- **Category:** Security
- **Severity:** Medium
- **Requirement source:** SECURITY.md:41; GitLab issue #31
- **Current state (evidence):**
  - `SECURITY.md:41` -- claims "All releases are tagged and signed"
  - `git tag -v v0.1.0` -- tag IS signed (ECDSA key SHA256:c+tO0MB9d6c4N2U4a+lYakImvwZXOqaiZwkBPphZ91o), verified good signature
  - Documentation of signing key and verification instructions: NOT present
  - CI enforcement of tag signing: NOT implemented
  - Blocked on existing GitLab issue #31 (open)
- **Why this is a gap:** Tags are signed in practice, but SECURITY.md lacks verification instructions for users, and CI does not enforce signing on release tags. The signing claim is partially substantiated but not fully documented or automated.
- **Impact/Risk:** Users cannot independently verify release signatures without documentation of the signing key and verification steps. Unsigned tags could be pushed if CI does not enforce signing.
- **Recommended fix:**
  1. Add verification instructions to SECURITY.md (key fingerprint, `git tag -v` command)
  2. Add CI job to enforce tag signature verification on release pipelines
  3. Document the signing key identity and rotation policy
- **Acceptance criteria:**
  - SECURITY.md contains verification instructions with key fingerprint
  - CI pipeline rejects unsigned release tags
  - Key rotation policy is documented

### GAP-0073: API documentation partial -- no generated/published docs

- **Issue:** [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) (existing -- do NOT create duplicate)
- **Category:** Docs
- **Severity:** Low
- **Status:** Open (deferred -- not addressed in Audit Cycle 3)
- **Requirement source:** GitLab issue #20 ("Write API documentation")
- **Current state (evidence):**
  - Inline doc comments (`///`) exist across `src/*.zig` for public types and functions
  - `README.md` API Reference section documents the public surface of `src/repl.zig`
  - No `zig build docs` step or autodoc target exists in `build.zig`
  - No generated/published HTML API documentation is produced or hosted
- **Why this is a gap:** Issue #20 calls for API documentation. Inline comments and the README cover the surface, but there is no generated, browsable, published API reference (e.g., Zig autodoc output), so the requirement is only partially satisfied.
- **Impact/Risk:** Consumers must read source or the README rather than a generated reference. Low impact -- the public API is small and documented inline -- but the requirement remains formally unmet.
- **Recommended fix:**
  1. Add a `zig build docs` target (autodoc) to `build.zig`
  2. Publish generated docs (e.g., GitLab Pages) and link from README
  3. Close issue #20 once generated docs are published
- **Acceptance criteria:**
  - `zig build docs` produces browsable API documentation
  - Generated docs are published and linked from README
  - Issue #20 closed with the published docs URL as evidence

### GAP-0053: GAP_ANALYSIS.md test count stale (257 -> 285) [RESOLVED]

- **Issue:** -- (doc staleness)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Updated GAP_ANALYSIS.md header test count from "257 tests" to "285 tests" to reflect the 28 new processAction unit tests added in QF-026/QF-066 work.
- **Evidence:** `docs/GAP_ANALYSIS.md:8` -- "285 tests"
- **Resolved date:** 2026-03-24

### GAP-0054: CONTRIBUTING.md project tree missing 10 root-level files [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Added build.zig.zon, Makefile, LICENSE, CHANGELOG.md, SECURITY.md, CODE_OF_CONDUCT.md, CODEOWNERS, NOTICE, SUPPORT.md, and README.md to the CONTRIBUTING.md project structure tree.
- **Evidence:** `docs/CONTRIBUTING.md:150-160` -- all root-level files listed
- **Resolved date:** 2026-03-24

### GAP-0055: SECURITY.md CI scanning list missing Gitleaks [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Security
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Added "Gitleaks: Enhanced secrets detection" to the CI/CD Security Scanning list in SECURITY.md. Pipeline evidence confirms security-gitleaks job runs.
- **Evidence:** `SECURITY.md` CI/CD Security Scanning section lists Gitleaks
- **Resolved date:** 2026-03-24

### GAP-0056: SECURITY.md CI scanning list missing SBOM [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Security
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Added "SBOM: Software Bill of Materials generation and scanning" to the CI/CD Security Scanning list in SECURITY.md. Pipeline evidence confirms sbom-generate and sbom-scan jobs run.
- **Evidence:** `SECURITY.md` CI/CD Security Scanning section lists SBOM
- **Resolved date:** 2026-03-24

### GAP-0057: README API Reference missing SyntheticKey type [RESOLVED]

- **Issue:** -- (doc gap)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Added SyntheticKey to the README Core Types section: "SyntheticKey - Named constants for special keys (Insert, Delete, Page Up, Page Down)".
- **Evidence:** `README.md:303` -- SyntheticKey listed in Core Types
- **Resolved date:** 2026-03-24

### GAP-0058: Minimum Zig version inconsistency (build.zig.zon says 0.15.0, docs say 0.14.0) [RESOLVED]

- **Issue:** -- (doc/manifest discrepancy)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Updated build.zig.zon `.minimum_zig_version` from "0.14.0" to "0.15.0" and README status table from "0.14.0+" to "0.15.x" to match the actual Zig 0.15.2 installed and required by the codebase.
- **Evidence:** `build.zig.zon:5` -- `"0.15.0"`; `README.md:10` -- "0.15.x"
- **Resolved date:** 2026-03-24

### GAP-0059: README API Reference missing 8 public items [RESOLVED]

- **Issue:** [#113](https://gitlab.com/devnw/zig/repl/-/issues/113)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Added Config, CompleteFn, terminalWriter, getStdinHandle, getStdoutHandle, getStderrHandle, isStderrTty, and version constants (version, version_major, version_minor, version_patch) to README.md API Reference section.
- **Evidence:** `README.md` API Reference section now documents all public exports from `src/repl.zig`
- **Resolved date:** 2026-03-25

### GAP-0060: CHANGELOG.md missing v0.1.1 entry and broken links [RESOLVED]

- **Issue:** [#114](https://gitlab.com/devnw/zig/repl/-/issues/114)
- **Category:** Docs
- **Severity:** Medium
- **Status:** Closed / Implemented
- **Resolution:** Added `## [0.1.1] - 2026-01-26` section with CI/CD changes. Fixed [Unreleased] link to compare v0.1.1...HEAD, added [0.1.1] comparison link, and fixed [0.1.0] link to releases page.
- **Evidence:** `CHANGELOG.md` -- v0.1.1 section present; all comparison links use correct tag-based URLs
- **Resolved date:** 2026-03-25

### GAP-0061: Copyright year 2024-2025 stale in source files and LICENSE [RESOLVED]

- **Issue:** [#115](https://gitlab.com/devnw/zig/repl/-/issues/115)
- **Category:** Docs (Legal)
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Updated copyright year from "2024-2025" to "2024-2026" in all src/*.zig (15 files), examples/*.zig (8 files), tests/integration.zig, build.zig, LICENSE, .gitleaks.toml, and CODEOWNERS. Entity name discrepancy (CodePros vs DevNW LLC) left as maintainer decision per instructions.
- **Evidence:** `grep -r "2024-2025"` returns only GAP_ANALYSIS.md references to the old state
- **Resolved date:** 2026-03-25

### GAP-0062: CONTRIBUTING.md:9 says "0.14.0" instead of "0.15.0" [RESOLVED]

- **Issue:** [#112](https://gitlab.com/devnw/zig/repl/-/issues/112)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Updated `docs/CONTRIBUTING.md:9` from "Zig (0.14.0 or later)" to "Zig 0.15.0 or later" to match `build.zig.zon` `.minimum_zig_version`.
- **Evidence:** `docs/CONTRIBUTING.md:9` -- "Zig 0.15.0 or later"
- **Resolved date:** 2026-03-25

### GAP-0063: Root CONTRIBUTING.md duplicates docs/CONTRIBUTING.md [RESOLVED]

- **Issue:** [#116](https://gitlab.com/devnw/zig/repl/-/issues/116)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Replaced root CONTRIBUTING.md content with a short redirect to docs/CONTRIBUTING.md. No unique content from the root file needed merging.
- **Evidence:** `CONTRIBUTING.md` -- 3-line redirect to `docs/CONTRIBUTING.md`
- **Resolved date:** 2026-03-25

### GAP-0064: .gitignore contains irrelevant Go/Python/Rust/Docker/Node rules [RESOLVED]

- **Issue:** [#117](https://gitlab.com/devnw/zig/repl/-/issues/117)
- **Category:** Code Quality
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Rewrote .gitignore from 206 lines to ~35 lines containing only Zig build artifacts, editor/IDE files, OS artifacts, secrets, and temporary files. Removed all Go, Python, Rust, Docker, and Node.js rules. Retained .claude/settings.local.json ignore.
- **Evidence:** `.gitignore` -- contains only Zig-relevant rules
- **Resolved date:** 2026-03-25

### GAP-0065: README Building section incomplete format check command [RESOLVED]

- **Issue:** [#118](https://gitlab.com/devnw/zig/repl/-/issues/118)
- **Category:** Docs
- **Severity:** Low
- **Status:** Closed / Implemented
- **Resolution:** Updated both README.md and docs/CONTRIBUTING.md format check commands from `zig fmt --check src/` to `zig fmt --check src/ tests/ examples/ build.zig` matching the Makefile check target.
- **Evidence:** `README.md` and `docs/CONTRIBUTING.md` both show the complete format check command
- **Resolved date:** 2026-03-25

---

## Recommended Remediation Order

### Phase 1: Quick wins (no blockers) -- COMPLETED

1. ~~**GAP-0027** -- Add `examples/` to Makefile fmt/check targets~~ Resolved
2. ~~**GAP-0028** -- Add `examples/` to CONTRIBUTING.md project structure tree~~ Resolved
3. ~~**GAP-0032** -- Update ROADMAP.md issue #19 status to Closed~~ Resolved
4. ~~**GAP-0033** -- Update ROADMAP.md issues #21, #22, #23, #24 status to Closed~~ Resolved
5. ~~**GAP-0034** -- Add authoritative-source notice to ROADMAP.md~~ Resolved

### Phase 1b: Test gaps (no blockers)

1. ~~**GAP-0025** -- Add unit tests for render.zig (pure functions, easy to test)~~ Resolved

### Phase 2: Infrastructure (blocked)

1. ~~**GAP-0004** -- Verify CI pipeline on runners~~ Resolved (pipeline 2406048174 passed all stages)
2. ~~**GAP-0026** -- Add fuzz targets to source code~~ Resolved

### Phase 3: Platform (blocked) -- COMPLETED

1. ~~**GAP-0010** -- Windows terminal improvements~~ Resolved (cross-platform comptime branching, real Windows API calls)

### Phase 4: Feature work (deferred) -- COMPLETED

1. ~~**GAP-0018** -- Real undo implementation~~ Resolved (bounded UndoStack in src/undo.zig, integrated into core.zig)

### Phase 5: New gaps (2026-03-24 sync)

1. ~~**GAP-0035** -- Commit and push all working tree changes~~ Resolved (issue #87 closed)
2. ~~**GAP-0036** -- Correct GAP-0024 resolution evidence line counts~~ Resolved (issue #88 closed)
3. ~~**GAP-0037** -- Update stale test counts in GAP_ANALYSIS.md~~ Resolved (issue #89 closed)

### Phase 6: Post-resolution audit gaps (2026-03-24) -- COMPLETED

1. ~~**GAP-0045** -- Fix Delete key collision with undo in Emacs mode (High, Bug)~~ Resolved (SyntheticKey.delete=0x04)
2. ~~**GAP-0046** -- Fix Delete key dead binding in Vi insert mode (High, Bug)~~ Resolved (same root cause)
3. ~~**GAP-0042** -- Add 5 missing modules to ARCHITECTURE.md (Medium, Docs)~~ Resolved
4. ~~**GAP-0038** -- Add undo.zig to CONTRIBUTING.md tree (Low, Docs)~~ Resolved
5. ~~**GAP-0039** -- Add Ctrl+_ to README Emacs keybindings (Low, Docs)~~ Resolved
6. ~~**GAP-0040** -- Add u to README Vi keybindings (Low, Docs)~~ Resolved
7. ~~**GAP-0041** -- Reduce core.zig below 800 lines or document exception (Low, Code Quality)~~ Resolved (justified in ARCHITECTURE.md)
8. ~~**GAP-0043** -- Update ROADMAP.md stale issue statuses (Low, Docs)~~ Resolved
9. ~~**GAP-0044** -- Add undo to README Features list (Low, Docs)~~ Resolved

### Phase 7: Validation audit finding (2026-03-24) -- COMPLETED

1. ~~**GAP-0047** -- Add config.zig to ARCHITECTURE.md (Low, Docs)~~ Resolved

### Phase 8: Validation audit -- docs staleness (2026-03-24) -- COMPLETED (except GAP-0052 blocked)

1. ~~**GAP-0048** -- Update ROADMAP.md issue #15 status to Closed (Low, Docs)~~ Resolved (issue #107 closed)
2. ~~**GAP-0049** -- Add 5 missing files to CONTRIBUTING.md docs/ tree (Low, Docs)~~ Resolved (issue #108 closed)
3. ~~**GAP-0050** -- Remove closed issues #1, #15 from README Current Priorities (Low, Docs)~~ Resolved (issue #109 closed)
4. ~~**GAP-0051** -- Remove closed issues #15, #21 from README Contributing section (Low, Docs)~~ Resolved (issue #109 closed)
5. **GAP-0052** -- Resolve SECURITY.md release signing: tags signed but docs and CI enforcement missing (Medium, Security) -- [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) (open/partial)

### Phase 9: Full audit findings (2026-03-24) -- COMPLETED

1. ~~**GAP-0053** -- Update stale test count in GAP_ANALYSIS.md (Low, Docs)~~ Resolved
2. ~~**GAP-0054** -- Add 10 root-level files to CONTRIBUTING.md project tree (Low, Docs)~~ Resolved
3. ~~**GAP-0055** -- Add Gitleaks to SECURITY.md CI scanning list (Low, Security)~~ Resolved
4. ~~**GAP-0056** -- Add SBOM to SECURITY.md CI scanning list (Low, Security)~~ Resolved
5. ~~**GAP-0057** -- Add SyntheticKey to README API Reference (Low, Docs)~~ Resolved
6. ~~**GAP-0058** -- Fix minimum Zig version inconsistency (Low, Docs)~~ Resolved

### Phase 10: Documentation and quality cleanup (2026-03-25) -- COMPLETED

1. ~~**GAP-0060** -- Add v0.1.1 entry to CHANGELOG.md and fix broken links (Medium, Docs)~~ Resolved (issue #114)
2. ~~**GAP-0062** -- Update CONTRIBUTING.md Zig version from 0.14.0 to 0.15.0 (Low, Docs)~~ Resolved (issue #112)
3. ~~**GAP-0065** -- Update README and CONTRIBUTING.md format check commands (Low, Docs)~~ Resolved (issue #118)
4. ~~**GAP-0059** -- Add 8 missing public items to README API Reference (Low, Docs)~~ Resolved (issue #113)
5. ~~**GAP-0063** -- Consolidate duplicate CONTRIBUTING.md files (Low, Docs)~~ Resolved (issue #116)
6. ~~**GAP-0061** -- Update stale copyright years and unify entity name (Low, Docs/Legal)~~ Resolved (issue #115)
7. ~~**GAP-0064** -- Clean up .gitignore to Zig-only rules (Low, Code Quality)~~ Resolved (issue #117)

### Phase 11: Audit Cycle 3 findings (2026-06-12)

1. ~~**GAP-0066** -- Config files written world-readable; no-op chmod + missing .permissions (High, Security)~~ Resolved (commit ec9a1dc, issue #122)
2. ~~**GAP-0067** -- History permission enforcement on pre-existing files removed (Medium, Security)~~ Resolved (commit ec9a1dc, issue #123)
3. ~~**GAP-0068** -- compat.chmod is a silent no-op (Low, Security)~~ Resolved (commit ec9a1dc, issue #126)
4. ~~**GAP-0069** -- sync_diamond_deps --cascade --apply blast radius (Medium, Security)~~ Resolved (commit 5eae04d, issue #124)
5. ~~**GAP-0070** -- Observability seam hardcoded enabled=false (Low, Code Quality)~~ Resolved (commit cf50500, issues #127/#140)
6. ~~**GAP-0071** -- Docker base image not digest-pinned (Low, CI-CD)~~ Resolved (commit cf50500, issue #133)
7. ~~**GAP-0072** -- processInput zero direct tests (Medium, Test)~~ Resolved (commit d039c05, issue #52)
8. **GAP-0073** -- API docs partial; no generated/published docs (Low, Docs) -- [#20](https://gitlab.com/devnw/zig/repl/-/issues/20) (open/deferred)
