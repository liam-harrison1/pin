# DeskPins for macOS

DeskPins is a macOS DeskPins-style window pinning project built around public system APIs.

The repository is currently in a bootstrap-but-runnable state:

- core pinning, focused-window reading, and window-catalog logic compile with Swift Package Manager
- repository verification, smoke tests, PR template, and CI scaffolding are in place
- the final menu bar app target and overlay UI are not built yet

## Current Capabilities

This repository currently includes:

- Accessibility trust detection
- focused-window snapshot reading
- visible-window catalog enumeration through `CGWindowListCopyWindowInfo`
- pin and unpin workflows for the current focused window
- pin and unpin workflows for visible catalog entries
- stale pinned-window reconciliation when a catalog refresh no longer matches an entry
- a workspace coordinator that combines catalog state, focused-window state, and pinned-window state into a single refresh snapshot

## What Is Not Built Yet

The current branch does not yet include:

- a runnable menu bar app shell
- overlay badges or border rendering
- persistent storage across launches
- global hotkey registration
- a finished Xcode app target

## Requirements

- macOS with Xcode Command Line Tools installed
- Swift toolchain compatible with `swift-tools-version: 6.0`

Full Xcode is optional for the current bootstrap phase. The repository can be verified with Command Line Tools alone.

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
swift run DeskPinsPinnedSmokeTests
swift run DeskPinsPinningSmokeTests
swift run DeskPinsWindowCatalogSmokeTests
```

### 3. Review the current implementation areas

- `Core/Accessibility/`: Accessibility permission and focused-window reads
- `Core/WindowCatalog/`: CoreGraphics window enumeration, filtering, and search
- `Core/Pinned/`: pinned-window model, identity, ordering, and invalidation state
- `Core/Pinning/`: pinning workflows and workspace-level refresh coordination

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
2. skim `Core/Pinning/`
3. run `./Scripts/verify.sh`
4. inspect the smoke tests in `Tools/`

That should give you a good picture of the current foundation before the menu bar app shell is added.
