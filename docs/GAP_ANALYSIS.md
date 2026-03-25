# Gap Analysis Report

**Project:** Zig REPL Library (`/home/benji/src/gl/devnw/zig/repl`)
**Date:** 2026-03-25 (Phase 16 -- 0 new gaps added, 7 resolved)
**Previous audit:** 2026-03-24 (Phase 15, 8 open gaps)
**Auditor:** Principal Engineer Audit (Claude Opus 4.6)
**Zig Version Installed:** 0.15.2
**Build Status:** Tests pass (`zig build test` exits 0, 285 tests)

---

## Summary

- **Total gaps identified (all time):** 65
- **Resolved (all time):** 64 (GAP-0001..GAP-0051, GAP-0053..GAP-0065)
- **Total open gaps:** 1
- **Carried forward (still open):** 1 (GAP-0052 -- blocked on #31)
- **New this phase:** 0
- **Resolved this phase:** 7 (GAP-0059..GAP-0065)
- **Previous resolved cycles:** 57 gaps resolved across Phases 1-14. All in [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)

---

## Gap Index (Open Only)

| Gap-ID | Title | Category | Severity | Issue | Status |
|--------|-------|----------|----------|-------|--------|
| GAP-0052 | SECURITY.md release signing claim unverified | Security | Medium | [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) | Open (blocked) |

---

## Gap Priority Matrix (Open Only)

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 1 | GAP-0052 |
| Low | 0 | -- |

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

### GAP-0052: SECURITY.md release signing claim unverified
- **Issue:** [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) (existing -- do NOT create duplicate)
- **Category:** Security
- **Severity:** Medium
- **Requirement source:** SECURITY.md:41; GitLab issue #31
- **Current state (evidence):**
  - `SECURITY.md:41` -- claims "All releases are tagged and signed"
  - No evidence of signing keys, CI signing steps, or verification instructions
  - Blocked on existing GitLab issue #31 (open)
- **Why this is a gap:** SECURITY.md makes a claim about release signing that cannot be verified. No signing infrastructure or documentation exists.
- **Impact/Risk:** Users may trust release integrity based on an unverified claim. If signing is not actually implemented, this is a misleading security assertion.
- **Recommended fix:** Either implement release signing (GPG key, CI automation, verification instructions) or revise the SECURITY.md claim to match the actual state.
- **Acceptance criteria:**
  - Either release signing is implemented and documented, or the SECURITY.md claim is revised to match reality

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
6. ~~**GAP-0025** -- Add unit tests for render.zig (pure functions, easy to test)~~ Resolved

### Phase 2: Infrastructure (blocked)
7. ~~**GAP-0004** -- Verify CI pipeline on runners~~ Resolved (pipeline 2406048174 passed all stages)
8. ~~**GAP-0026** -- Add fuzz targets to source code~~ Resolved

### Phase 3: Platform (blocked) -- COMPLETED
9. ~~**GAP-0010** -- Windows terminal improvements~~ Resolved (cross-platform comptime branching, real Windows API calls)

### Phase 4: Feature work (deferred) -- COMPLETED
10. ~~**GAP-0018** -- Real undo implementation~~ Resolved (bounded UndoStack in src/undo.zig, integrated into core.zig)

### Phase 5: New gaps (2026-03-24 sync)
11. ~~**GAP-0035** -- Commit and push all working tree changes~~ Resolved (issue #87 closed)
12. ~~**GAP-0036** -- Correct GAP-0024 resolution evidence line counts~~ Resolved (issue #88 closed)
13. ~~**GAP-0037** -- Update stale test counts in GAP_ANALYSIS.md~~ Resolved (issue #89 closed)

### Phase 6: Post-resolution audit gaps (2026-03-24) -- COMPLETED
14. ~~**GAP-0045** -- Fix Delete key collision with undo in Emacs mode (High, Bug)~~ Resolved (SyntheticKey.delete=0x04)
15. ~~**GAP-0046** -- Fix Delete key dead binding in Vi insert mode (High, Bug)~~ Resolved (same root cause)
16. ~~**GAP-0042** -- Add 5 missing modules to ARCHITECTURE.md (Medium, Docs)~~ Resolved
17. ~~**GAP-0038** -- Add undo.zig to CONTRIBUTING.md tree (Low, Docs)~~ Resolved
18. ~~**GAP-0039** -- Add Ctrl+_ to README Emacs keybindings (Low, Docs)~~ Resolved
19. ~~**GAP-0040** -- Add u to README Vi keybindings (Low, Docs)~~ Resolved
20. ~~**GAP-0041** -- Reduce core.zig below 800 lines or document exception (Low, Code Quality)~~ Resolved (justified in ARCHITECTURE.md)
21. ~~**GAP-0043** -- Update ROADMAP.md stale issue statuses (Low, Docs)~~ Resolved
22. ~~**GAP-0044** -- Add undo to README Features list (Low, Docs)~~ Resolved

### Phase 7: Validation audit finding (2026-03-24) -- COMPLETED
23. ~~**GAP-0047** -- Add config.zig to ARCHITECTURE.md (Low, Docs)~~ Resolved

### Phase 8: Validation audit -- docs staleness (2026-03-24) -- COMPLETED (except GAP-0052 blocked)
24. ~~**GAP-0048** -- Update ROADMAP.md issue #15 status to Closed (Low, Docs)~~ Resolved (issue #107 closed)
25. ~~**GAP-0049** -- Add 5 missing files to CONTRIBUTING.md docs/ tree (Low, Docs)~~ Resolved (issue #108 closed)
26. ~~**GAP-0050** -- Remove closed issues #1, #15 from README Current Priorities (Low, Docs)~~ Resolved (issue #109 closed)
27. ~~**GAP-0051** -- Remove closed issues #15, #21 from README Contributing section (Low, Docs)~~ Resolved (issue #109 closed)
28. **GAP-0052** -- Resolve SECURITY.md release signing claim (Medium, Security) -- [#31](https://gitlab.com/devnw/zig/repl/-/issues/31) (blocked)

### Phase 9: Full audit findings (2026-03-24) -- COMPLETED
29. ~~**GAP-0053** -- Update stale test count in GAP_ANALYSIS.md (Low, Docs)~~ Resolved
30. ~~**GAP-0054** -- Add 10 root-level files to CONTRIBUTING.md project tree (Low, Docs)~~ Resolved
31. ~~**GAP-0055** -- Add Gitleaks to SECURITY.md CI scanning list (Low, Security)~~ Resolved
32. ~~**GAP-0056** -- Add SBOM to SECURITY.md CI scanning list (Low, Security)~~ Resolved
33. ~~**GAP-0057** -- Add SyntheticKey to README API Reference (Low, Docs)~~ Resolved
34. ~~**GAP-0058** -- Fix minimum Zig version inconsistency (Low, Docs)~~ Resolved

### Phase 10: Documentation and quality cleanup (2026-03-25) -- COMPLETED
35. ~~**GAP-0060** -- Add v0.1.1 entry to CHANGELOG.md and fix broken links (Medium, Docs)~~ Resolved (issue #114)
36. ~~**GAP-0062** -- Update CONTRIBUTING.md Zig version from 0.14.0 to 0.15.0 (Low, Docs)~~ Resolved (issue #112)
37. ~~**GAP-0065** -- Update README and CONTRIBUTING.md format check commands (Low, Docs)~~ Resolved (issue #118)
38. ~~**GAP-0059** -- Add 8 missing public items to README API Reference (Low, Docs)~~ Resolved (issue #113)
39. ~~**GAP-0063** -- Consolidate duplicate CONTRIBUTING.md files (Low, Docs)~~ Resolved (issue #116)
40. ~~**GAP-0061** -- Update stale copyright years and unify entity name (Low, Docs/Legal)~~ Resolved (issue #115)
41. ~~**GAP-0064** -- Clean up .gitignore to Zig-only rules (Low, Code Quality)~~ Resolved (issue #117)
