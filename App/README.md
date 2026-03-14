# App

Application entry layer for the DeskPins menu bar app, settings surfaces, and lifecycle wiring.

Current layout:

- `App/Support/`: app-facing state orchestration that bridges core pinning services into menu-bar-friendly presentation state
- `App/MenuBarApp/`: minimal runnable menu bar shell built with AppKit

The current shell is intentionally small:

- status item in the macOS menu bar
- pre-menu workspace capture so the menu can act on the last external focused window
- actions for workspace refresh, accessibility permission request, and current-window pin toggle
- direct unpin menu items for already pinned windows
- JSON-backed pinned-window restore on startup

Overlay windows, hotkeys, and richer settings are still future work.
