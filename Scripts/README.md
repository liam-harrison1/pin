# Scripts

Shell helpers for build, lint, and manual verification live here.

## Current Scripts

- `verify.sh`: repository verification entry point used by local workflow, pre-commit, and GitHub Actions
- `Tools/DeskPinsPinnedSmokeTests`: bootstrap smoke-test executable for pinned-window ordering logic

## Notes

- `verify.sh` is intentionally stage-aware: it verifies docs and git gates now, runs SwiftPM build plus smoke tests during bootstrap, and can expand further into SwiftLint and Xcode checks once those artifacts exist.
