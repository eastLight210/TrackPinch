# Changelog

## 0.1.0-alpha.3 - 2026-08-08

Improves first-launch clarity for a menu-bar-only app.

### Added

- Dedicated first-run setup window with a two-step permission and gesture flow
- Persistent `Setup Guide` entry point in the menu bar popover
- Explicit handoff from completed setup to the menu bar controls

### Changed

- Keep permission setup visible while macOS System Settings is open
- Present onboarding as a fixed, single-instance utility window without a Dock icon
- Clarify where TrackPinch lives after setup and what Accessibility observes

### Distribution

- The prerelease DMG remains ad hoc signed and not notarized.
- Universal Apple Silicon and Intel packaging remains unchanged.

## 0.1.0-alpha.2 - 2026-08-08

Improved the initial alpha after short-display and clean-permission testing.

### Changed

- Fit and scroll the menu bar popover on short displays
- Request only the Accessibility permission required by the event tap
- Start and retry input monitoring only after Accessibility is granted
- Clarify permission, onboarding, and diagnostics copy

## 0.1.0-alpha.1 - 2026-08-08

First experimental TrackPinch prerelease.

### Included

- Modifier plus two-finger horizontal, vertical, and diagonal window resizing
- Active-window capture for the duration of a gesture
- Scroll suppression for gestures owned by TrackPinch
- Accessibility and Input Monitoring onboarding
- Configurable modifier chord and resize sensitivity
- Universal macOS app for Apple Silicon and Intel

### Known limitations

- The prerelease DMG is ad hoc signed and not notarized.
- Signed-build manual QA across the supported matrix is incomplete.
- Launch at login and automatic updates are not implemented.
