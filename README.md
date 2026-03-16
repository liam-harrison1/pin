# DeskPins for macOS

[![Verify](https://github.com/liam-harrison1/pin/actions/workflows/verify.yml/badge.svg)](https://github.com/liam-harrison1/pin/actions/workflows/verify.yml)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

DeskPins is an open-source macOS menu bar utility for pinning important windows in front of your workflow using public APIs.

## Highlights

- Menu bar-first UX for fast pin/unpin actions
- Pin current focused window or pin from a searchable visible-window list
- Multi-window pin management with interaction-aware ordering
- App-owned overlay system (`preview` / `drag` / `badge`) for pin feedback
- Global shortcut support (`Control-Option-Command-P` by default)
- JSON persistence at `~/Library/Application Support/DeskPins/PinnedWindows.json`

## Current Status

This repository is in a runnable bootstrap stage:

- SwiftPM build is the primary development path
- Core modules and smoke tests are stable
- Menu bar app shell is usable for day-to-day testing
- Settings UI and advanced controls are still being refined

## Architecture (at a glance)

- `App/MenuBarApp`: app entry + menu bar shell
- `App/Support`: state orchestration and menu-facing controller
- `Core/Accessibility`: AX trust, focused-window reads, activation/move
- `Core/WindowCatalog`: visible-window catalog via `CGWindowListCopyWindowInfo`
- `Core/Pinned`: pin identity, ordering, invalidation, persistence
- `Core/Pinning`: pin/unpin workflows and workspace refresh coordinator
- `Core/Overlay`: overlay rendering and interaction handling
- `Core/HotKey`: global shortcut registration and routing

## Requirements

- macOS
- Xcode Command Line Tools
- Swift toolchain compatible with `swift-tools-version: 6.0`

## Quick Start

```bash
./Scripts/verify.sh
./Scripts/run-app.sh
```

Expected behavior:

- `verify.sh` passes build + smoke tests
- `Pins` appears in the menu bar when launching the app

## Permissions

Baseline branch:

- Accessibility (required)

Experimental mirrored-content mode:

- Accessibility
- Screen Recording

See [Docs/permission-model.md](Docs/permission-model.md) for details.

## Known Boundary

DeskPins does not promise absolute system-level always-on-top semantics for every third-party window object.  
It prioritizes a public-API-first approach and app-owned overlay consistency.

## Documentation

- [Project Book](deskpins-project-book-v2.md)
- [Product Spec](Docs/product-spec.md)
- [Architecture](Docs/architecture.md)
- [MVP Checklist](Docs/mvp-checklist.md)
- [Permission Model](Docs/permission-model.md)
- [Release Plan](Docs/release-plan.md)

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

MIT. See [LICENSE](LICENSE).
