# Gap Analysis Report

**Project:** Zig REPL Library (`/home/benji/src/gl/devnw/zig/repl`)
**Date:** 2026-03-24 (Phase 14 -- 6 gaps resolved, 1 blocked)
**Previous audit:** 2026-03-24 (Phase 13, 1 open gap)
**Auditor:** Principal Engineer Audit (Claude Opus 4.6)
**Zig Version Installed:** 0.15.2
**Build Status:** Tests pass (`zig build test` exits 0, 285 tests)

---

## Summary

- **Total gaps identified (all time):** 58
- **Resolved (all time):** 57 (GAP-0001..GAP-0051, GAP-0053..GAP-0058)
- **Total open gaps:** 1
- **Carried forward (still open):** 1 (GAP-0052 -- blocked on #31)
- **Resolved this phase:** 6 (GAP-0053..GAP-0058)
- **Previous resolved cycles:** 51 gaps resolved across Phases 1-13; 6 resolved in Phase 14. All in [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md)

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

### GAP-0053: GAP_ANALYSIS.md test count stale (257 → 285) [RESOLVED]
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
