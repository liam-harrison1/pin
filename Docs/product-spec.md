# DeskPins for macOS Product Spec

## Goal

Build a lightweight macOS menu bar app that gives users a DeskPins-style way to pin important windows above their workflow without relying on private APIs or invasive system modifications.

## Product Promise

The app should feel:

- fast to trigger
- easy to understand
- explicit about permissions
- stable under normal desktop workflows

## Target Users

- Knowledge workers keeping meetings, notes, or reference docs visible.
- Developers and researchers keeping terminals, specs, or issue trackers visible.
- Creators and operators keeping chat panels or dashboards visible.

## Primary Jobs To Be Done

- Pin the current window in one action.
- Pin a different visible window from a searchable list.
- Keep track of multiple pinned windows.
- Understand which pinned window is currently on top and why.
- Recover cleanly when permissions are missing or a target window disappears.

## MVP Scope

### Required

- Menu bar app entry point.
- Accessibility permission detection and guidance.
- Pin/Unpin current focused window.
- Searchable visible window list built from `CGWindowListCopyWindowInfo`.
- Multiple pinned windows.
- Floating `📌` badge overlay near the pinned window title bar.
- Global shortcut for pinning the current window.
- Ordering rule based on recent interaction or recent pin time.
- Graceful degradation for missing permissions and invalid windows.

### Experimental Branch Scope

On `codex/feat-screen-recording-overlay`, DeskPins also renders mirrored pinned-window content above other apps.

This branch explicitly requires:

- Accessibility
- Screen Recording

### Out of Scope

- Guaranteed true system-level always-on-top for every third-party window.
- Private API usage.
- Injection-based enhancements.
- Screen content preview in MVP.
- Sync, cloud, or account features.
- Complex automation rules in the first release.

## UX Principles

- The first successful pin must require minimal setup beyond permission granting.
- The product must always explain why it cannot act.
- The app should not feel like a generic automation utility.
- Pinned state should be visible even when the user forgets how they pinned the window.

## Core User Flows

### Flow 1: Pin Current Window

1. User triggers a shortcut or menu item.
2. App checks Accessibility trust.
3. App reads the focused window.
4. App stores the pinned item.
5. App shows overlay feedback and updates order.

### Flow 2: Pin From Window List

1. User opens the window list.
2. App refreshes visible windows.
3. User searches by app name or title.
4. User selects a window to pin.
5. App stores the pinned item and renders feedback.

### Flow 3: Manage Pinned Windows

Per pinned window, MVP should support:

- Focus
- Unpin
- Toggle click-through
- Adjust opacity
- Show status if the original window becomes unavailable

## Success Criteria

- A user can successfully pin the current window after granting Accessibility permission.
- A user can pin at least 3 visible windows and manage them from the app.
- The ordering behavior is predictable enough to be explained in one sentence in settings.
- Missing-permission and invalid-window states are recoverable without restarting the app.

## Permissions

### Required in Baseline MVP

- Accessibility

### Required in Experimental Content-Overlay Mode

- Accessibility
- Screen Recording

Rule:

Do not request Screen Recording until the project explicitly adds window content preview or capture.
