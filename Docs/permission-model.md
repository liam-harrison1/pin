# DeskPins for macOS Permission Model

## Principle

Request the minimum permission required for the currently shipped feature set.

## Baseline MVP Permission

### Accessibility

Why it is needed:

- read the focused window
- inspect relevant window attributes
- observe changes needed for pin state maintenance

What happens without it:

- the app can still open
- the app cannot perform real pin actions on external windows
- the UI must explain the missing capability clearly

## Experimental Content-Overlay Permission

### Screen Recording

Request this only on the mirrored content-overlay branch or when the shipped feature set truly includes window mirroring.

It becomes required when the project explicitly adds:

- content preview
- window mirroring
- capture-assisted selection

## Hard Rules

- Never request Screen Recording as part of first-run onboarding.
- Never hide permission-dependent behavior behind vague messaging.
- Never add private or elevated system access to work around missing permission.
