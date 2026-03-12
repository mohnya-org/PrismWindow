# Prism

Prism is a macOS menu bar app that moves the focused window to another display.

Current implementation priority is the fallback path for native fullscreen windows:

1. Exit fullscreen via Accessibility.
2. Move the window to the target display.
3. Re-enter fullscreen.

This works without disabling SIP and stays compatible with direct distribution. It does not yet perform a true Space-to-Space transfer through private CGS APIs.

## Features

- Menu bar resident SwiftUI app
- Global shortcut: `Control + Option + Command + F`
- Move the focused window to the next display
- Per-app display rules for the frontmost app

## Build

```bash
swift build
swift run Prism
```

## Permissions

- Accessibility permission is required
- Screen Recording is optional for debugging, not required for the fallback mover

## Notes

- Some apps may refuse `AXFullScreen` toggling or window resize operations
- Stage Manager / Mission Control settings can affect perceived fullscreen behavior
- The rule engine currently applies when the app becomes frontmost
