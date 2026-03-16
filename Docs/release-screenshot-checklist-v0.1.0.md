# Screenshot Checklist for First Public Release

Use this checklist to produce consistent GitHub visuals for README and Release pages.

## 1) Capture Standards

- Resolution:
  - Desktop standard: `2560x1600` or `2880x1800`
  - Fallback: `1920x1200`
- Format: PNG
- Language:
  - Prefer English UI for global audience
  - Optional second set in Chinese if needed
- Naming:
  - `01-menu-overview.png`
  - `02-pin-current-window.png`
  - `03-pin-from-window-list.png`
  - `04-multi-pin-ordering.png`
  - `05-drag-interaction.png`
  - `06-unpin-workflow.png`
  - `07-permission-guidance.png`
  - `08-experimental-mirror-mode.png`

## 2) Required Screenshot Set

1. Menu bar overview
- Show `Pins` status item and open menu
- Include pinned count and primary actions

2. Pin current window
- Before and after pin action
- Ensure `📌` badge is visible

3. Pin from visible-window list
- Show searchable list and selection flow

4. Multi-pin ordering behavior
- Two or three pinned windows in one frame
- Demonstrate interaction-aware ordering

5. Drag interaction
- Show drag handle interaction state
- Window relocation result should be visible

6. Unpin workflow
- Single unpin via badge or menu
- Optional “Unpin All Windows” menu state

7. Permission guidance
- Accessibility prompt/help state
- If possible, include post-grant success state

8. Experimental mirrored-content mode (optional but recommended)
- Show mirrored overlay behavior
- Must clearly label this as experimental and requiring Screen Recording

## 3) Visual Quality Rules

- Keep desktop background simple and low-contrast.
- Avoid unrelated personal apps/messages in frame.
- Keep window titles non-sensitive.
- Use consistent zoom level and UI scale.
- Crop to emphasize workflow, not empty desktop area.

## 4) README Placement Plan

- Hero screenshot:
  - `01-menu-overview.png`
- Feature strip:
  - `02-pin-current-window.png`
  - `03-pin-from-window-list.png`
  - `04-multi-pin-ordering.png`
  - `05-drag-interaction.png`
- Advanced/experimental section:
  - `08-experimental-mirror-mode.png`

## 5) Release Page Placement Plan

- Top:
  - short GIF or static hero (`01`)
- Middle:
  - workflow sequence (`02` -> `03` -> `04`)
- Bottom:
  - permissions (`07`) and experimental mode (`08`)

## 6) Pre-Publish Checklist

1. All screenshots are free of personal/private information.
2. File names follow the agreed sequence.
3. README and release notes refer to existing file names only.
4. Experimental mode is explicitly marked as optional.
5. At least one screenshot validates core value: fast, predictable pinning.
