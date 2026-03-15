# DeskPins Optimization Design (2026-03-15)

## Objective

Align deep-research findings with the current repository implementation and land low-risk, compile-ready optimizations for bootstrap stage.

Hard constraints:

- public API only
- MVP baseline keeps Accessibility as the only required permission
- Screen Recording remains experimental branch behavior
- no speculative large rewrites in this pass

## Prompt-Engineering Output (Self-Feed Prompt)

This prompt is used to constrain implementation quality before touching code.

```text
You are the implementation owner for DeskPins (macOS, SwiftPM bootstrap).

Goal:
- Convert deep-research recommendations into minimal, verifiable repository changes.

Scope:
- Analyze Docs + App + Core + Tools.
- Prioritize P0 correctness and observability over feature expansion.

Must-do:
1) Window matching hardening:
   - Use windowNumber as first-class exact match for activation/move workflows.
   - Fall back to title/bounds scoring only when exact id is unavailable.
2) Lease-path observability:
   - Add structured app logs for lease handshake start/retry/success/timeout/failure.
   - Keep timeouts and retry cadence explicit constants.
3) Regression safety:
   - Add smoke-test coverage for lease render policy matrix (owner/suppressed/reset).
4) Docs sync:
   - Update architecture + MVP checklist when behavior or guarantees change.

Out of scope for this pass:
- private APIs
- full actor migration
- large-scale app-layer extraction across many files

Verification:
- Run ./Scripts/verify.sh.
- Report residual risks and untested macOS edge cases.
```

## Brainstorming Summary

### Option A (recommended)

Apply targeted reliability hardening in existing architecture:

- patch `WindowActivator` and `WindowMover` matching logic
- instrument lease handshake in app layer
- add focused smoke tests for lease render policy behavior

Pros:

- directly addresses current P0 risk patterns
- small diff and low refactor risk
- easy to verify with existing bootstrap pipeline

Tradeoff:

- does not fully solve long-term main.swift orchestration complexity

### Option B

Refactor lease state into a separate reducer/coordinator immediately.

Pros:

- cleaner architecture and testability

Tradeoff:

- high change surface for bootstrap stage
- larger regression risk and longer stabilization

### Option C

Prioritize performance changes first (Top-K dynamic frame rate and capture throttling).

Pros:

- may reduce system load in heavy multi-pin sessions

Tradeoff:

- does not directly eliminate current interaction correctness regressions

Decision:

Use Option A now, then stage Option B/C later.

## Changes Landed In This Pass

1. Accessibility matching hardening:
   - `Core/Accessibility/WindowActivator.swift`
   - `Core/Accessibility/WindowMover.swift`
   - behavior: exact `AXWindowNumber` match first, then existing heuristic fallback

2. Lease observability and handshake tuning:
   - `App/MenuBarApp/main.swift`
   - behavior:
     - explicit constants for lease timeout/retry
     - structured logs for lease acquiring/activation/clear/timeout/error
     - one handshake retry before timeout fallback

3. Smoke-test coverage for lease render-policy matrix:
   - `Tools/DeskPinsAppSupportSmokeTests/main.swift`
   - added assertions:
     - active lease owner -> `.directInteractionOwner`
     - suppressed competitors -> `.suppressed`
     - after clear -> all `.mirrorVisible`

4. Docs sync:
   - `Docs/architecture.md`
   - `Docs/mvp-checklist.md`

5. Lease state extraction (continuation):
   - `App/Support/OverlayInteractionLeaseState.swift`
   - `App/MenuBarApp/main.swift`
   - behavior:
     - isolate lease mode/suppression/focus-unknown/handshake timing into a reusable state model
     - reduce app delegate state branching while preserving current runtime behavior
     - add state-machine smoke assertions

## Next-Phase Design (Not Implemented Here)

1. Extract lease reducer/coordinator from `App/MenuBarApp/main.swift`.
2. Add structured metrics sink for:
   - lease success latency p50/p95
   - handshake timeout rate
   - focus mismatch rate during active lease
3. Add macOS scenario validation matrix:
   - browser tab title churn
   - multi-display
   - Spaces/fullscreen transitions

## Validation Plan

- run `./Scripts/verify.sh` as single source of truth
- confirm smoke tests remain green
- manually test:
  - two overlapping pinned browser windows, rapid A/B switching
  - content click -> lease acquisition -> active route
  - drag and unpin behavior under active/suppressed states
