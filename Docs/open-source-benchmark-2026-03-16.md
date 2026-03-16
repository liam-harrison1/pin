# Open-Source Benchmark Notes (2026-03-16)

## Goal

Review successful macOS open-source utility repositories and extract practical patterns for:

- README information architecture
- onboarding clarity
- user-facing scope boundaries
- contribution funnel

## Repositories Reviewed

1. [MrKai77/Loop](https://github.com/MrKai77/Loop)
2. [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle)
3. [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos)
4. [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)

## Patterns Worth Reusing

1. Strong README top section:
   - clear one-line value proposition
   - badges for CI/license
   - immediate install/run entry point

2. Practical "Known Boundary" section:
   - explicitly document platform/API limits
   - avoid over-promising behavior that macOS public APIs cannot guarantee

3. Installation + troubleshooting split:
   - fast path for normal users
   - dedicated diagnostics notes for edge cases

4. Explicit project status:
   - clearly state maturity (bootstrap/beta/stable)
   - list what is implemented vs in-progress

5. Contribution funnel:
   - CONTRIBUTING.md with verification gate
   - issue templates to improve bug report quality

## Applied to DeskPins

The following open-source polish updates were applied:

1. README rewritten with:
   - concise product positioning
   - architecture-at-a-glance
   - quick start
   - permission model
   - known boundary and docs map

2. Added contributor workflow docs:
   - `CONTRIBUTING.md`
   - `.github/ISSUE_TEMPLATE/bug_report.md`
   - `.github/ISSUE_TEMPLATE/feature_request.md`

3. Removed temporary deep-research handoff artifacts that were useful internally but noisy for public repository presentation.

4. Replaced local absolute path links with repo-relative links in core docs.
