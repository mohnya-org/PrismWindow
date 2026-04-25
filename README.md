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
1.2.12
```

## Updates

Prism Window uses Sparkle for in-app updates. The appcast is published as a
GitHub Release asset and read from:

```bash
https://github.com/mohnya-org/PrismWindow/releases/latest/download/appcast.xml
```

Generate Sparkle keys once on a trusted Mac:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
```

Add the printed public key to the GitHub secret:

```bash
SPARKLE_PUBLIC_ED_KEY
```

Add the exported private key contents to:

```bash
SPARKLE_PRIVATE_KEY
```

Do not commit the private key. Release builds inject the public key into the
app bundle and use the private key to sign the update archive in `appcast.xml`.

## Compatibility

Prism Window requires macOS 26.0 or later.

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
- generates a Sparkle appcast
- uploads a zip archive, sha256 checksum, and appcast to GitHub Releases

The release workflow runs on the self-hosted macOS runner and uses the
currently selected Xcode on that machine.

Required GitHub secrets:

- `APPLE_CERT_BASE64`
- `APPLE_CERT_PASSWORD`
- `APPLE_API_PRIVATE_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_TEAM_ID`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_KEY`

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
