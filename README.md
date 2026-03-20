# Prism

Prism is a macOS menu bar app that automatically places windows on the correct display based on user-defined rules.

## Features

- **Rule-based window placement** — assign each app to a specific display with fullscreen or windowed mode
- **Auto-apply on focus** — when an app becomes frontmost, Prism moves its window to the configured display
- **Fullscreen re-enforcement** — if a fullscreen rule is manually exited, Prism detects the Space change and re-applies the rule
- **Display setup profiles** — create multiple named profiles per physical display arrangement (e.g. "Work", "Home")
- **Auto-apply toggle** — enable or disable automatic rule application from the menu bar
- **Launch at Login** — optionally start Prism when you log in (configurable in Settings)
- **Menu bar UI** — move the focused window manually via buttons or a visual display layout selector

## Build

```bash
swift build
swift run Prism
```

## Permissions

- **Accessibility** — required for reading and moving windows via the Accessibility API
- Screen Recording is not required

## How it works

Prism uses the macOS Accessibility API (public, not private) to move windows between displays. For fullscreen windows, the process is:

1. Hide the app and wait for confirmation
2. Exit fullscreen via `AXFullScreen` attribute
3. Wait for the Space transition to complete (`activeSpaceDidChangeNotification`)
4. Move the window to the target display
5. Re-enter fullscreen if the rule requires it
6. Unhide and activate the app

## Limitations

- Some apps may refuse `AXFullScreen` toggling or window resize operations
- Windows on non-visible Spaces (e.g. a hidden fullscreen Space on another display) cannot be moved programmatically via public APIs
- Stage Manager / Mission Control settings can affect perceived fullscreen behavior
