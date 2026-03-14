# App

Application entry layer for the DeskPins menu bar app, settings surfaces, and lifecycle wiring.

Current layout:

- `App/Support/`: app-facing state orchestration that bridges core pinning services into menu-bar-friendly presentation state
- `App/MenuBarApp/`: minimal runnable menu bar shell built with AppKit

The current shell is intentionally small:

- status item in the macOS menu bar
- pre-menu workspace capture so the menu can act on the last external focused window
- actions for workspace refresh, accessibility permission request, current-window pin toggle, and visible-window pinning
- a separate action for requesting Screen Recording when the mirrored content overlay branch is in use
- bring-forward and unpin menu items for already pinned windows
- app-owned floating `📌` badges for pinned windows
- on the Screen Recording branch, mirrored pinned-content overlays rendered above other apps
- a global shortcut for toggling the current focused window pin
- JSON-backed pinned-window restore on startup

Richer settings, overlay tuning, and a dedicated Xcode app target are still future work.
