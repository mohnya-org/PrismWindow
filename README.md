# Prism Window

Prism Window is a macOS menu bar app that moves the focused window to the correct display using user-defined rules.

## Features

- Rule-based window placement per app
- Fullscreen or windowed placement rules
- Auto-apply when an app becomes frontmost
- Multiple named setup profiles for the same physical display arrangement
- Manual move UI in the menu bar
- Visual display layout picker
- Settings UI for editing rules, profiles, and display setups

## Development

Run the app from source:

```bash
swift build
swift run PrismWindow
```

## Release Build

Build a distributable `.app` bundle:

```bash
./scripts/build-app.sh
```

Output:

```bash
.build/release/Prism Window.app
```

The executable inside the bundle remains:

```bash
PrismWindow
```

The app icon source image is stored at:

```bash
Resources/AppIcon.png
```

The build script converts it into an `.icns` file and places it in the app bundle.

The app version is read from:

```bash
Resources/Info.plist
```

Current app version:

```bash
1.2.0
```

## Release CI

GitHub Actions workflow:

```bash
.github/workflows/release-macos-app.yml
```

The workflow:

- resolves the release version from `workflow_dispatch` input or `Resources/Info.plist`
- creates a `v<version>` git tag if it does not already exist
- builds `Prism Window.app`
- signs and notarizes the app
- uploads a zip archive and sha256 checksum to GitHub Releases

Required GitHub secrets:

- `APPLE_CERT_BASE64`
- `APPLE_CERT_PASSWORD`
- `APPLE_API_PRIVATE_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

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
