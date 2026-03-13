# DeskPins for macOS MVP Checklist

## Phase 0: Project Setup

- [x] Confirm project docs are the source of truth.
- [x] Keep [deskpins-project-book-v2.md](/Users/lzc/Documents/科研/deskpins尝试/deskpins-project-book-v2.md) as the umbrella document.
- [x] Create and maintain `Docs/product-spec.md`.
- [x] Create and maintain `Docs/architecture.md`.
- [x] Create and maintain `Docs/permission-model.md`.
- [x] Create and maintain `Docs/release-plan.md`.
- [x] Keep project-level `AGENTS.md` aligned with architecture decisions.
- [x] Keep `Scripts/verify.sh` aligned with the current repository stage.
- [x] Keep `.github/workflows/verify.yml` aligned with local verification.
- [x] Keep `.github/pull_request_template.md` aligned with git workflow rules.
- [x] Keep `.pre-commit-config.yaml` aligned with `Scripts/verify.sh`.
- [x] Initialize a compile-ready Swift Package Manager bootstrap for core modules.
- [x] Add a smoke-test executable for bootstrap validation of pinned-window ordering.

## Phase 1: Menu Bar and Permission Foundation

- [ ] Create a runnable menu bar app shell.
- [x] Add Accessibility trust detection.
- [ ] Add a permission guidance entry in the UI.
- [ ] Add basic app logging for startup and action failures.
- [ ] Add a settings surface for shortcut and ordering behavior.

## Phase 2: Pin Current Window

- [x] Read the current focused window through Accessibility.
- [x] Create the pinned model and storage layer.
- [ ] Implement pin for the current focused window.
- [ ] Implement unpin for the current focused window.
- [ ] Handle invalid or missing focused window states gracefully.

## Phase 3: Overlay and Ordering

- [ ] Add pin badge feedback.
- [ ] Add border or highlight overlay.
- [ ] Add ordering behavior based on recent interaction.
- [ ] Add optional mode for recent pin priority.
- [ ] Add opacity and click-through controls for pinned overlays.

## Phase 4: Window List and Search

- [ ] Enumerate visible windows with `CGWindowListCopyWindowInfo`.
- [ ] Filter obvious noise windows.
- [ ] Build searchable app name and title views.
- [ ] Allow pinning from the window list.
- [ ] Handle stale window entries cleanly.

## Phase 5: Stability and Release Readiness

- [ ] Validate multiple pinned windows.
- [ ] Validate target window exit and app termination behavior.
- [ ] Validate multi-display behavior.
- [ ] Validate Space and fullscreen degradation behavior.
- [ ] Validate shortcut registration failure messaging.
- [ ] Prepare signing and notarization notes.

## Acceptance Checks

- [ ] A user can pin the current window after granting Accessibility.
- [ ] A user can pin a non-focused visible window from the window list.
- [ ] Three to five pinned windows remain manageable without app instability.
- [ ] The app never silently fails on missing permission.
- [ ] No private API has entered the MVP path.
- [ ] Local verification and CI use the same repository verification entry point.
