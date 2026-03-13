# AGENTS.md

This repository is for a macOS DeskPins-style window pinning tool.

## Source of Truth

Read these first before making architectural or product changes:

- `deskpins-project-book-v2.md`
- `Docs/product-spec.md`
- `Docs/architecture.md`
- `Docs/mvp-checklist.md`
- `Docs/permission-model.md`

## Current Stage

The repository is in implementation bootstrap.

That means:

- prioritize compile-ready scaffolding and verification before UI-heavy feature code
- keep changes small and explainable
- avoid speculative abstractions
- prefer core logic that can be validated with Swift Package Manager before full Xcode app wiring

## Product Boundaries

Do:

- follow a public-API-first approach
- treat Accessibility as the only MVP permission
- use app-owned overlays for pin state and visual feedback
- preserve a lightweight menu bar-first UX

Do not:

- add private APIs
- add Dock injection or app injection
- design features that require disabling SIP
- request Screen Recording in MVP
- promise perfect system-level always-on-top semantics for all third-party windows

## Repo Structure

- `Docs/` contains stable product and architecture docs.
- `App/` is the future application entry layer.
- `Core/Accessibility/` owns Accessibility access and observation.
- `Core/WindowCatalog/` owns visible window discovery and search.
- `Core/Pinned/` owns pin state, identity, and ordering.
- `Core/Overlay/` owns pin badge, borders, and overlay behavior.
- `Core/HotKey/` owns global shortcut behavior.
- `Scripts/` contains simple helper scripts only.

## Change Rules

- If a change affects scope or architecture, update the relevant `Docs/*.md` file in the same turn.
- Prefer additive changes over broad rewrites.
- Keep naming aligned with the module layout above.
- Use ASCII by default unless a file already requires otherwise.

## Git Workflow Rules

### Task Sizing

- `Small` task: changes `<= 2` files, estimated diff `<= 80` lines, and does not touch permissions, build config, core window management, persistence, or public API.
- `Medium/Large` task: any task that exceeds the small-task limits, introduces a new module or directory, or touches `Package.swift`, Xcode project files, entitlements, CI, Accessibility, Overlay, Pinned, or HotKey core paths.

### Branch and Worktree Policy

- `Medium/Large` tasks must use a dedicated branch or worktree.
- Branch names must use the `codex/` prefix.
- Recommended branch formats:
  - `codex/feat-<topic>`
  - `codex/fix-<topic>`
  - `codex/refactor-<topic>`
- Never commit directly to `main` or `master`.
- `Small` tasks may work in the current task workspace, but if the current branch is `main` or `master`, a new branch is still required before committing.

### Pre-Work Checks

- Check `git status --short` before starting git operations.
- If the worktree is dirty with unrelated changes, stop automatic git actions and request user confirmation.
- Check the current branch name before committing.
- In local CLI or IDE workflows, do not automatically run `git pull` unless the user explicitly asks for it.

### Required Validation Before Commit

- Run `./Scripts/verify.sh` before every commit.
- If `./Scripts/verify.sh` does not exist yet, automatic git behavior is limited to draft changes or branch-local draft commits only.
- Do not commit while required verification is failing.

### Commit Rules

- Commit only after required verification passes.
- Keep each commit focused on one logical change.
- Use conventional commit prefixes such as:
  - `feat:`
  - `fix:`
  - `refactor:`
  - `docs:`
  - `chore:`
- Do not amend existing commits unless explicitly requested.
- After committing, confirm the worktree is clean or that any remaining changes are intentional and explained.

### Push Rules

- In local CLI or IDE workflows, do not automatically push unless the user explicitly asks for push.
- In cloud or app task workflows, automatic push is allowed only when all of the following are true:
  - the branch is not `main` or `master`
  - required local verification passed
  - the worktree is clean
  - there are no unexplained extra files
  - the task does not modify permissions, signing, entitlements, CI, or core build configuration
- If the task is high-risk, do not auto-push even after verification. Wait for user confirmation.

### Pull Request Rules

- Do not automatically open a PR unless the user explicitly allows it or repository rules are later updated to permit it.
- Even when PR creation is allowed, require all of the following:
  - work is on a dedicated branch
  - `./Scripts/verify.sh` passed
  - CI is expected to pass
  - the PR description includes summary, test evidence, risks, and rollback notes
- Do not automatically merge PRs.

### Current Stage Restriction

- This repository is still in bootstrap mode.
- Until remote CI is active and the real macOS app target is in place:
  - automatic branch or worktree creation is allowed
  - automatic commits for docs, repo-structure work, and bootstrap code are allowed
  - automatic push is not allowed
  - automatic PR creation is not allowed

### Escalate To User When

- unrelated local changes already exist
- the task would commit to `main` or `master`
- the change affects permissions, signing, entitlements, CI, or build system configuration
- verification is missing or failing
- the task scope grows beyond the agreed plan
- push or PR is requested before repo gates are in place

## Testing Expectations

Before claiming a feature is done:

- confirm it matches the MVP checklist
- note any untested macOS edge cases
- call out permission assumptions explicitly
