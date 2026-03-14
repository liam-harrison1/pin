# DeskPins for macOS

DeskPins is a macOS DeskPins-style window pinning project built around public system APIs.

The repository is currently in a bootstrap-but-runnable state:

- core pinning, focused-window reading, and window-catalog logic compile with Swift Package Manager
- a minimal AppKit menu bar shell can be launched from the package
- repository verification, smoke tests, PR template, and CI scaffolding are in place
- the final overlay UI and richer app-shell surfaces are not built yet

## Current Capabilities

This repository currently includes:

- Accessibility trust detection
- focused-window snapshot reading
- visible-window catalog enumeration through `CGWindowListCopyWindowInfo`
- pin and unpin workflows for the current focused window
- pin and unpin workflows for visible catalog entries
- stale pinned-window reconciliation when a catalog refresh no longer matches an entry
- a workspace coordinator that combines catalog state, focused-window state, and pinned-window state into a single refresh snapshot
- JSON persistence for pinned-window store snapshots
- a runnable menu bar app shell with refresh, permission request, and current-window pin toggle actions

## What Is Not Built Yet

The current branch does not yet include:

- overlay badges or border rendering
- pinning from the menu-bar window list UI
- global hotkey registration
- a finished Xcode project target

## Requirements

- macOS with Xcode Command Line Tools installed
- Swift toolchain compatible with `swift-tools-version: 6.0`

Full Xcode is now available on this machine, but the repository still builds and runs through Swift Package Manager.

## Quick Start

Clone the repository and run:

```bash
./Scripts/verify.sh
```

This script currently checks:

- required docs and repo workflow files
- merge conflict markers
- shell script syntax
- `swift build`
- all smoke-test executables in `Tools/`

If `swiftlint` is installed locally, the script will run it automatically. If an Xcode project or workspace is later added, `verify.sh` will also require an Xcode scheme via `DESKPINS_XCODE_SCHEME`.

## Manual Try-Out Guide

The current manual verification path is code-level rather than UI-level.

### 1. Run the full repository gate

```bash
./Scripts/verify.sh
```

Expected result:

- build completes successfully
- all smoke tests print `... smoke tests passed`

### 2. Run individual smoke tests if you want to inspect one subsystem at a time

```bash
swift run DeskPinsAccessibilitySmokeTests
swift run DeskPinsAppSupportSmokeTests
swift run DeskPinsPinnedSmokeTests
swift run DeskPinsPinnedPersistenceSmokeTests
swift run DeskPinsPinningSmokeTests
swift run DeskPinsWindowCatalogSmokeTests
```

### 3. Launch the current menu bar shell

```bash
swift run DeskPinsMenuBarApp
```

What you should expect:

- a `Pins` status item appears in the macOS menu bar
- the menu offers refresh, accessibility permission request, and current-window pin toggle actions
- pinned windows are saved to `~/Library/Application Support/DeskPins/PinnedWindows.json`

Manual step you will likely need:

- grant Accessibility access to the host process you are using to launch the app

If you launch through Terminal:

- add Terminal under `Privacy & Security > Accessibility`

If you launch through Xcode:

- add Xcode under `Privacy & Security > Accessibility`

### 4. Review the current implementation areas

- `App/Support/`: menu-bar-facing app state orchestration
- `App/MenuBarApp/`: minimal AppKit menu bar shell
- `Core/Accessibility/`: Accessibility permission and focused-window reads
- `Core/WindowCatalog/`: CoreGraphics window enumeration, filtering, and search
- `Core/Pinned/`: pinned-window model, identity, ordering, invalidation state, and JSON persistence
- `Core/Pinning/`: pinning workflows and workspace-level refresh coordination

## Branch Guide

Use descriptive branches rather than `v1`, `v2`, or `v3`.

- `codex/feat-project-init`: earliest bootstrap history; kept for traceability, not the branch to continue on
- `codex/feat-project-init-pr`: the stable review branch for the current bootstrap PR
- `codex/feat-pinning-workspace-state`: a completed local feature branch that introduced the workspace coordinator and has already been folded forward
- `codex/feat-pinned-store-persistence`: a completed local feature branch that introduced JSON persistence and has already been folded forward
- `codex/feat-menu-bar-app-shell`: the branch that should continue receiving new implementation work now

Branch naming format:

- `codex/feat-<topic>` for new functionality
- `codex/fix-<topic>` for bug fixes
- `codex/refactor-<topic>` for internal restructuring

Reason:

- names stay tied to the actual purpose of the work
- review is easier than opaque version labels
- cross-thread branch prompts are easier to interpret

## Important Bootstrap Notes

- This project intentionally avoids private macOS APIs.
- The current code is structured so that UI wiring can be added later without moving business logic into the app layer.
- Current testing uses smoke-test executables instead of XCTest because the active local environment is bootstrap-oriented and CLT-friendly.

## Project Docs

See these documents for the current source of truth:

- `deskpins-project-book-v2.md`
- `Docs/product-spec.md`
- `Docs/architecture.md`
- `Docs/mvp-checklist.md`
- `Docs/permission-model.md`
- `Docs/release-plan.md`

## Suggested Review Flow

For this bootstrap PR, the fastest review path is:

1. read `Docs/architecture.md`
2. skim `App/Support/` and `App/MenuBarApp/`
3. run `./Scripts/verify.sh`
4. optionally launch `swift run DeskPinsMenuBarApp`
5. inspect the smoke tests in `Tools/`

That should give you a good picture of the current foundation before overlay windows and hotkeys are added.
