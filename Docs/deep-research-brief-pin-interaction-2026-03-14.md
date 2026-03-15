# DeskPins Deep Research Brief (Pin Interaction Regressions)

Date: 2026-03-14  
Branch: `codex/feat-screen-recording-overlay`  
Priority: Critical interaction correctness while preserving current smoothness gains.

## 1) Context and Current Architecture

The app uses a mirrored-overlay model (not native OS-level always-on-top).

- A pinned target is represented as three overlay windows:
  - `PinnedPreviewWindow` (mirrored content)
  - `PinnedDragHandleWindow` (drag and mode switching surface)
  - `PinnedBadgeWindow` (`pin/unpin` badge)
- All three are `NSPanel` at `.floating` level:
  - Preview: [`Core/Overlay/PinnedWindowOverlayManager.swift:531`](../Core/Overlay/PinnedWindowOverlayManager.swift#L531)
  - Drag handle: [`Core/Overlay/PinnedWindowOverlayManager.swift:601`](../Core/Overlay/PinnedWindowOverlayManager.swift#L601)
  - Badge: [`Core/Overlay/PinnedWindowOverlayManager.swift:779`](../Core/Overlay/PinnedWindowOverlayManager.swift#L779)
- Ordering policy is recency-based (`recentInteractionFirst`) from pinned store metadata:
  - [`Core/Pinned/PinnedWindowOrdering.swift:3`](../Core/Pinned/PinnedWindowOrdering.swift#L3)
  - [`Core/Pinned/PinnedWindowStore.swift:68`](../Core/Pinned/PinnedWindowStore.swift#L68)
  - Frontmost visible pinned window updates activation order during refresh:
    [`App/Support/DeskPinsMenuBarStateController.swift:325`](../App/Support/DeskPinsMenuBarStateController.swift#L325)

### Rendering / performance path currently in place

- SCStream-based preview capture with per-window session reuse and latest-frame cache:
  - [`Core/Overlay/WindowPreviewCapturer.swift:46`](../Core/Overlay/WindowPreviewCapturer.swift#L46)
- Current tuning:
  - `preferredFrameRate = 15`, `preferredQueueDepth = 3`
    [`Core/Overlay/WindowPreviewCapturer.swift:59`](../Core/Overlay/WindowPreviewCapturer.swift#L59)
  - `showsCursor = false`
    [`Core/Overlay/WindowPreviewCapturer.swift:433`](../Core/Overlay/WindowPreviewCapturer.swift#L433)
  - complete-frame filtering only
    [`Core/Overlay/WindowPreviewCapturer.swift:545`](../Core/Overlay/WindowPreviewCapturer.swift#L545)
- Overlay refresh/cadence controls:
  - App refresh timer: 80ms
    [`App/MenuBarApp/main.swift:515`](../App/MenuBarApp/main.swift#L515)
  - Drag flush: 60Hz
    [`App/MenuBarApp/main.swift:116`](../App/MenuBarApp/main.swift#L116)
  - Post-drag refresh delay: 60ms
    [`App/MenuBarApp/main.swift:117`](../App/MenuBarApp/main.swift#L117)
  - Overlay capture cooldown after drag: 120ms
    [`Core/Overlay/PinnedWindowOverlayManager.swift:51`](../Core/Overlay/PinnedWindowOverlayManager.swift#L51)

## 2) Current Direct-Interaction Implementation

The current behavior introduces a "direct interaction mode" for one pinned window:

1. Clicking content area on drag surface triggers:
   - `.contentInteractionRequested`
     [`Core/Overlay/PinnedWindowOverlayManager.swift:39`](../Core/Overlay/PinnedWindowOverlayManager.swift#L39)
2. App delegate handles it by:
   - activating target window (`AX raise/activate`)
   - marking this pinned id as `directInteractionPinnedWindowID`
   - refreshing overlays
     [`App/MenuBarApp/main.swift:609`](../App/MenuBarApp/main.swift#L609)
3. State controller emits overlay targets with:
   - selected pinned window => `shouldRenderPreview = false`
   - others => `true`
     [`App/Support/DeskPinsMenuBarStateController.swift:252`](../App/Support/DeskPinsMenuBarStateController.swift#L252)
4. Overlay manager then:
   - hides selected preview window
   - keeps selected drag-handle and badge overlays alive
     [`Core/Overlay/PinnedWindowOverlayManager.swift:181`](../Core/Overlay/PinnedWindowOverlayManager.swift#L181)

## 3) Regression Bugs (Observed)

### Bug A: Direct interaction is not truly "native usable"

User-visible symptoms:
- After clicking into the working area, the pinned window is not reliably usable as a normal window.
- In multi-pinned scenarios, other pinned overlays visually cover the interactive target.
- Typing may still work in existing text-focus areas, but pointer operations are inconsistent.

Important nuance:
- Preview overlays ignore mouse (`ignoresMouseEvents = true`), so clicks pass through them.
- But pass-through may land on whichever real window is geometrically underneath at that point, not necessarily the intended direct-interaction target.
- Result: the user sees one window, but clicks are routed unpredictably in overlapping regions.

Relevant code:
- Preview ignores mouse:
  [`Core/Overlay/PinnedWindowOverlayManager.swift:546`](../Core/Overlay/PinnedWindowOverlayManager.swift#L546)
- Drag-surface behavior in direct mode:
  [`Core/Overlay/PinnedWindowOverlayManager.swift:684`](../Core/Overlay/PinnedWindowOverlayManager.swift#L684)

### Bug B: Switching between pinned windows still has short visible delay

User-visible symptoms:
- Switching interaction from pinned window A to pinned window B is not immediate.
- A short waiting period is often needed before the next drag/interaction feels accepted.

Likely latency contributors (stacked):
- `performBackgroundRefresh` cadence: 80ms
  [`App/MenuBarApp/main.swift:515`](../App/MenuBarApp/main.swift#L515)
- `postDragRefreshDelay`: 60ms
  [`App/MenuBarApp/main.swift:117`](../App/MenuBarApp/main.swift#L117)
- post-interaction capture cooldown: 120ms
  [`Core/Overlay/PinnedWindowOverlayManager.swift:51`](../Core/Overlay/PinnedWindowOverlayManager.swift#L51)
- serialized capture (`maxConcurrentCaptures = 1`)
  [`Core/Overlay/PinnedWindowOverlayManager.swift:50`](../Core/Overlay/PinnedWindowOverlayManager.swift#L50)

## 4) Repro Scenarios

### Repro A (direct interaction mismatch)

1. Pin two overlapping browser windows A and B.
2. Click content area of A to enter direct interaction mode.
3. Try clicking controls in A where B's mirrored overlay overlaps visually.
4. Observe: click targets and visual target disagree; interaction is unreliable.

### Repro B (switch delay)

1. Pin two windows A and B.
2. Drag A and release.
3. Immediately try to drag B.
4. Observe: short delay before B becomes reliably draggable.

## 5) Desired Product Behavior (Target)

### Interaction correctness targets

1. When user enters direct interaction for pinned window X, pointer behavior should match native window interaction semantics for X (no hidden overlay routing surprises).
2. User must be able to return to "pin-drag mode" deterministically (single clear gesture).
3. In multi-pinned overlap, the active interaction target must remain visually and interactively unambiguous.

### Responsiveness targets

1. Window-to-window switch latency should be effectively immediate to users (target <= one frame if possible).
2. No regression to recently achieved smoothness (low stutter, low ghosting, low blur).

### Non-goals

- Do not remove SCStream optimization path that solved major lag/ghosting regressions.
- Do not break pin-order semantics:
  - later pin initially above
  - click/drag pinned window => it becomes top among pinned windows

## 6) Candidate Implementation Strategies to Evaluate (Research Focus)

### Strategy A (recommended baseline): Interaction Lease Model

Introduce explicit global mode:
- `overlayMode = previewPinned` (default)
- `overlayMode = directInteraction(windowID: X)`

When entering direct interaction on X:
- suppress preview overlays for **all** pinned windows or at least all overlapped competitors,
  not only X.
- keep only minimal non-obstructive control affordance for X
  (tiny top rail or corner control).
- ensure one deterministic "return to pin mode" action.

Pros:
- Highest interaction correctness.
- Removes click-routing ambiguity in overlap zones.

Tradeoff:
- Temporarily reduced global mirror visibility while in direct interaction.

### Strategy B: Active-Target Priority Layering

Keep all previews, but dynamically re-layer non-active previews below active real window interaction context.
This is hard because overlays are app-owned floating panels and real app windows stay at normal levels.

Pros:
- Preserves multi-preview visibility.

Tradeoff:
- Potentially fragile due to macOS window-server layering limits.
- Risk of reintroducing cursor/boundary anomalies.

### Strategy C: Event-forwarding / synthetic click handoff

Keep visual overlays, intercept clicks, then synthesize routed events to intended target.

Pros:
- Theoretically preserves visuals and interaction.

Tradeoff:
- High complexity and high regression/security risk.
- Likely brittle across apps and webviews.

## 7) Constraints for Any Final Solution

Must keep:
- SCStream capture architecture and latest-frame cache.
- Current drag smoothness profile.
- No reintroduction of severe edge-cursor anomaly.
- No accidental drop of core "pin content stays above" behavior.

## 8) Validation Metrics (Acceptance)

1. Direct interaction correctness:
   - 50 rapid clicks across overlapping zones route to intended active window.
2. Switch latency:
   - A->B drag switch median <= 50ms, p95 <= 100ms.
3. Stability:
   - no stale freeze, no severe ghosting spikes during 5-minute stress interaction.
4. Ordering:
   - pin order and click-to-top behavior remain correct in multi-pin.

## 9) Questions for Deep Research

1. What is the most robust macOS pattern for "temporarily interactive pinned mirror" without visual/input mismatch under overlap?
2. Is there a proven window-layer strategy that allows active target interaction without hiding all other floating overlays?
3. Which state-machine design minimizes switch latency while preserving smoothness?
4. Are there known ScreenCaptureKit + NSPanel interaction pitfalls and mitigation patterns for this exact UX?

## 10) Ready-to-Use Prompt for GPT Deep Research

Use this prompt as-is:

```text
I am building a macOS DeskPins-style app using ScreenCaptureKit mirrored overlays.
Current state:
- Pinned windows are mirrored using app-owned floating NSPanel overlays.
- I recently solved major lag/ghosting/blur with SCStream session reuse and latest-frame caching.
- New regressions:
  1) Direct interaction mode is unreliable in overlapping multi-pin scenarios: visual target and click routing mismatch.
  2) Switching interaction between pinned windows has short but noticeable delay.

Architecture pointers:
- Overlay manager with preview/drag-handle/badge panels:
  Core/Overlay/PinnedWindowOverlayManager.swift
- State controller chooses shouldRenderPreview per pinned target:
  App/Support/DeskPinsMenuBarStateController.swift
- App interaction + refresh scheduling:
  App/MenuBarApp/main.swift
- SCStream capture implementation:
  Core/Overlay/WindowPreviewCapturer.swift

Required outcome:
- Keep existing smoothness gains.
- Fix interaction correctness for overlapping pinned windows.
- Make cross-pinned switching feel immediate.
- Preserve pin ordering semantics (later pin above; clicked/dragged pinned window rises).

Please produce:
1) A concrete architecture recommendation with a state machine.
2) Why this is more robust than alternatives.
3) Step-by-step implementation plan (incremental and low-risk).
4) Instrumentation plan and measurable acceptance criteria.
5) Failure modes and rollback strategy.
```

