# Contributing

Thanks for your interest in contributing to DeskPins.

## Development Setup

1. Fork and clone the repository.
2. Create a feature branch with the `codex/` prefix.
3. Run:

```bash
./Scripts/verify.sh
```

All changes should pass this verification gate before commit.

## Pull Requests

Please keep pull requests focused:

- one logical change per PR
- include a concise summary of behavior changes
- include verification evidence (command outputs or test notes)
- call out known risks and rollback strategy for non-trivial changes

## Code Guidelines

- Prefer public API usage only.
- Keep changes additive and easy to review.
- Avoid speculative abstractions.
- Preserve module boundaries documented in `Docs/architecture.md`.

## Issue Reporting

For bugs, include:

- macOS version
- reproduction steps
- expected vs actual behavior
- logs or screenshots when possible

## Security

Do not include private credentials, tokens, or personal data in commits, issues, or PRs.
