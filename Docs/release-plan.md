# DeskPins for macOS Release Plan

## Release Strategy

The first release is an independently distributed, signed, and notarized app candidate, not an App Store-first product.

## Why

- Accessibility is a core dependency.
- Public-API compliance must remain clear.
- The project should prove stability and user value before considering distribution expansion.

## Release Gates

### Product Gates

- Pin current window works reliably.
- Window list pinning works reliably.
- Multiple pinned windows are manageable.
- Ordering behavior is understandable.
- If mirrored content overlay is shipped, Screen Recording permission and degraded fallback behavior are both clear.

### Technical Gates

- No private APIs.
- No SIP assumptions.
- Graceful handling of missing permissions.
- Clear logging for failure states.
- `Scripts/verify.sh` is the single local verification entry point.
- GitHub Actions runs the same repository verification gate.
- PR descriptions include summary, validation, risk, and rollback notes.
- During bootstrap, Swift verification may use a smoke-test executable before the full macOS app target and unit-test stack are available.

### QA Gates

- Multi-window validation
- Multi-display validation
- Space and fullscreen validation
- Window-close and app-exit validation

## Post-MVP Candidates

- automation rules
- App Intents
- XCF-enhanced development workflow

## Experimental Branch Note

`codex/feat-screen-recording-overlay` is intentionally exploring a more DeskPins-like mirrored content overlay.

It is not release-ready until the project confirms:

- Screen Recording messaging is acceptable
- mirrored overlays remain understandable and performant with multiple pinned windows
- fallback behavior without Screen Recording remains non-destructive

## Repository Gates

- Protect `main` and `master` from direct pushes.
- Require pull requests for integration.
- Require the `Verify` workflow to pass.
- Keep local pre-commit and CI behavior consistent with `Scripts/verify.sh`.
