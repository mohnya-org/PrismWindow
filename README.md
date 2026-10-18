# Prism Window

Prism Window is a macOS menu bar app that moves the focused window to the correct display using user-defined rules.

## Features

- Rule-based window placement per app
- Fullscreen or windowed placement rules
- Auto-apply when an app becomes frontmost
- Multiple named setup profiles for the same physical display arrangement
- Manual move UI in the menu bar
- Remove the focused app's rule directly from the menu bar for the current display setup and profile
- Visual display layout picker
- Settings UI for editing rules, profiles, and display setups

## Installation and Updates

Download the app from [GitHub Releases](https://github.com/mohnya-org/PrismWindow/releases/latest).
Official builds support automatic updates. Use “Automatically check for updates” or
“Check for Updates…” in the menu bar panel.

## Development

Build and launch the app from source:

```bash
./scripts/build-app.sh
open ".build/release/Prism Window.app"
```

Use the app bundle for local testing: it includes the Sparkle framework required at runtime. `swift run PrismWindow` does not bundle that framework and can fail to launch. Quit any running copy of Prism Window before opening the newly built app.

Local builds use ad-hoc signing and are not notarized. Official distribution builds use
Developer ID signing and Apple notarization. Automatic updates are not configured in local
builds or forks, and update controls are hidden. No update service or signing secrets are
required to build and run the app locally.

## Permissions

- Accessibility: required for reading and moving windows
- Screen Recording: not required

## How It Works

Prism Window uses the macOS Accessibility API to move windows between displays.

For normal windows, Prism Window updates the window position and size directly.

For fullscreen windows, Prism Window uses a public-API fallback flow:

1. Exit fullscreen
2. Move the window to the target display
3. Re-enter fullscreen if required

This keeps the app compatible with direct distribution and avoids private CGS APIs, but it is not a true Space-to-Space transfer.

## Display Setup Profiles

Rules are organized in two layers:

- Physical display setup: the currently connected monitor arrangement
- Setup profile: a named rule set for that arrangement, such as `Work`, `Home`, or `Presentation`

You can keep multiple profiles for the same display setup and switch which one auto-applies.

## Limitations

- Some apps refuse `AXFullScreen` toggling or window resize operations
- Fullscreen moves use a fallback flow, so stale snapshots or residual animations can sometimes remain on the source display
- Stage Manager, Mission Control, and Space transitions can affect perceived behavior
- Public APIs do not provide a true Space-to-Space fullscreen move

## Maintainer Documentation

Official release, signing, notarization, and update-feed procedures are documented in
[Release Maintenance](docs/RELEASING.md).
