# Scripts

Shell helpers for build, lint, and manual verification live here.

## Current Scripts

- `verify.sh`: repository verification entry point used by local workflow, pre-commit, and GitHub Actions
- `run-app.sh`: launch the real menu bar app executable (`DeskPinsMenuBarApp`) so the `Pins` status item appears in the macOS menu bar
- `Tools/DeskPinsAccessibilitySmokeTests`: smoke tests for Accessibility trust and focused-window adaptation
- `Tools/DeskPinsAppSupportSmokeTests`: smoke tests for app-facing menu-bar state orchestration
- `Tools/DeskPinsPinnedSmokeTests`: smoke tests for pinned-window ordering and store lifecycle
- `Tools/DeskPinsPinnedPersistenceSmokeTests`: smoke tests for JSON persistence of pinned-window state
- `Tools/DeskPinsPinningSmokeTests`: smoke tests for pin-current, pin-from-catalog, and workspace refresh flows
- `Tools/DeskPinsWindowCatalogSmokeTests`: smoke tests for visible-window filtering and search

## Notes

- `verify.sh` is intentionally stage-aware: it verifies docs and git gates now, runs SwiftPM build plus smoke tests during bootstrap, and can expand further into SwiftLint and Xcode checks once those artifacts exist.
