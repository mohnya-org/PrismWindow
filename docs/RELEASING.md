# Release Maintenance

These instructions are for maintainers of the official distribution. They are not required
to build, use, or fork Prism Window. All commands below run from the repository root.

## Release Build

Build a local release-configuration `.app` bundle (ad-hoc signed, not notarized):

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

For local builds without a VERSION override, the development version is read from:

```bash
Resources/Info.plist
```

Local development default (published versions are assigned by CI):

```bash
1.3.0
```

Published archives use `PrismWindow-<version>-macOS.zip` (no spaces). The app bundle remains `Prism Window.app`. GitHub normalizes asset names containing spaces, so both appcast generation and publication reject unsafe filenames.

## Release CI

GitHub Actions workflow:

```bash
.github/workflows/release-macos-app.yml
```

The workflow:

- runs on main pushes and optional manual dispatch
- increments the latest stable patch, or uses an explicit newer manual version
- builds `Prism Window.app` with that version, signs it, and notarizes it
- creates a tag for the built commit after artifacts are ready
- uploads the ZIP, checksum, and appcast to a draft, then publishes the complete release

Required GitHub secrets:

- `APPLE_CERT_BASE64`
- `APPLE_CERT_PASSWORD`
- `APPLE_API_PRIVATE_KEY`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_TEAM_ID`

Organization Secrets must be made available to this repository. The workflow also requires
`SPARKLE_PRIVATE_KEY` and `SPARKLE_PUBLIC_ED_KEY` for the existing updater. Before any build,
`macos-distribution.py preflight` reports missing/invalid variable names only; it never prints values.

### Local signing versus distribution signing

`./scripts/build-app.sh` defaults to `SIGNING_MODE=adhoc`. It signs nested code from the inside
out for local execution without accessing Developer ID credentials. This is **not** a Gatekeeper
approved distribution build. `SIGNING_MODE=unsigned` creates the CI staging bundle; neither mode
performs notarization. The old `CODESIGN_IDENTITY` build override is no longer used.

Distribution uses `scripts/macos-distribution.py release <app> <zip>` in CI. It imports the
certificate into a uniquely named temporary keychain, selects exactly one valid Developer ID
Application identity whose certificate OU matches `APPLE_TEAM_ID`, and passes that keychain
explicitly to every signing command. It also appends that keychain to the user's search list,
preserving every existing entry; `codesign` can fail to resolve the identity without this on
self-hosted macOS runners. Cleanup deletes only this job's keychain and its search-list entry,
preserving other jobs' entries rather than restoring a stale list snapshot. The default keychain
is never changed. All temporary paths are unique to the invocation.

Every physical Mach-O executable (including Sparkle helpers), XPC service, nested app and framework
is signed before its enclosing bundle; the host app is signed last. Signing uses Hardened Runtime
and a secure timestamp, without `--deep`. This Swift/AppKit app and the pinned Sparkle 2.10.0
binaries require no entitlements: no JIT, unsigned executable memory, debugger, or disabled library
validation exceptions are added. Verification rejects unexpected entitlements; review this policy
when changing dependencies. Accessibility permission remains a user-granted TCC permission.

The release flow then:

1. Removes AppleDouble metadata and extended attributes **before** signing.
2. Verifies all signatures, signing teams, Hardened Runtime and timestamps.
3. Creates a ZIP with `ditto --norsrc --noextattr` and rejects any `._*`/`__MACOSX` entries.
4. Submits with `notarytool` using the App Store Connect API key and requires JSON status `Accepted`.
5. Staples the ticket, then recreates the final ZIP with the same metadata exclusions.
6. Extracts the final ZIP into a fresh directory and requires `codesign --verify --deep --strict`,
   matching teams for all nested code, `stapler validate`, and `spctl --assess --type execute`.
7. Generates the checksum and Sparkle appcast from this final ZIP, then rechecks the checksum and
   extracted app before allowing the existing publication step to run.

After code signing, only ticket stapling is allowed; do not edit bundle contents, clean metadata,
or re-sign the app afterward. The temporary certificate, API key and keychain are cleaned in a
`finally` block on success/failure and on SIGINT/SIGTERM; an `always()` workflow step retries cleanup
after cancellation. A cleanup failure blocks publication. A machine crash/SIGKILL cannot run process
cleanup, so the workflow fallback must run when the runner recovers; do not share runner OS accounts
with untrusted jobs (environment variables and process arguments are not an isolation boundary).

For a pre-merge validation, manually dispatch `release-macos-app.yml` on the trusted fix branch
with `validate_only=true`. It uses the configured Secrets and runs signing, notarization and final
artifact verification, but never creates tags, drafts or published releases. No changes to main
are required. Normal main pushes retain the existing automatic publication behavior.
Signing failures identify the component and exit code and classify known codesign errors;
raw tool output, certificate identities, keychain paths and secret values remain suppressed.

Offline checks (no secrets or Apple service requests):

```bash
python3 -B scripts/test-macos-distribution.py
python3 -B scripts/test-release-version.py
python3 -B scripts/test-publish-release.py
bash scripts/test-update-configuration.sh
actionlint .github/workflows/release-macos-app.yml
zsh -n scripts/build-app.sh
```

See [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and [Sparkle nested-code signing](https://sparkle-project.org/documentation/sandboxing/).

## Automatic Updates (Sparkle 2)

The app periodically checks for updates and uses Sparkle's standard interface to download,
install, and restart. Use “Automatically check for updates” to toggle periodic checks and
“Check for Updates…” to check manually. Update controls are in the Prism Window menu bar panel.

Configure these GitHub Actions repository secrets before distribution, or grant the repository
access to the corresponding Organization Secrets:

- `SPARKLE_PRIVATE_KEY`: the private key exported with Sparkle's `generate_keys -x`.
- `SPARKLE_PUBLIC_ED_KEY`: the public key shown by `generate_keys -p` for the same key pair.

After an SPM build, Sparkle's tools are in `.build/artifacts/sparkle/Sparkle/bin`.
For Xcode builds, they are under `SourcePackages/artifacts/sparkle/Sparkle/bin` in DerivedData.
Generate the key pair once with `generate_keys --account <app-name>` and use the same
`--account` with both `-p` and `-x`. Keep a secure backup of the private key and never commit
it to the repository. Reuse the key pair across releases to preserve update continuity.

The workflow embeds the public key in the app, signs the final notarized and stapled ZIP
for Sparkle, and attaches `appcast.xml` to the same GitHub Release. The feed URL is:

```text
https://github.com/mohnya-org/PrismWindow/releases/latest/download/appcast.xml
```

This setup targets standard releases in a public repository. Publish the ZIP and feed together.
Pushes to main, including PR merges, automatically assign the next `vX.Y.Z` version.
Normally, the patch number is incremented from the highest existing stable-version tag.
Unpublished tags used by other commits are treated as reserved and skipped; existing tags
are never overwritten. If there are no existing tags, the first version is `v0.0.1`.
No commit updating the source version is required. For a manual release, select main in
Actions and optionally supply a newer stable `version`, such as `1.5.0`. Leave it empty
for automatic version selection. Use `validate_only=true` to validate without publishing.

The selected version is embedded in the distributed app and ZIP filename.
`CFBundleVersion` uses the Actions run number. After the build, signing, notarization, and feed generation
succeed, the workflow tags the triggering commit. It publishes the draft only after the ZIP,
checksum, and appcast have all been uploaded, so release webhooks receive a complete set
of artifacts.

If a run fails, it can be rerun. An existing tag or draft for the same commit is reused;
a published release is left unchanged. Runs that would publish source older than the latest
stable release are rejected. Releases run sequentially, and an active run is not canceled.
GitHub Actions concurrency can replace a pending run with a newer one when several merges
arrive in quick succession. In that case, the release includes the changes in the latest commit.

Releases fail if required signing secrets are missing. The source Info.plist contains no
update feed or public key. The official CI injects both `SPARKLE_FEED_URL` and
`SPARKLE_PUBLIC_ED_KEY` before signing. Local builds and forks do not instantiate the updater
or show update controls unless both a valid HTTPS feed URL and a public key are supplied.

Forks do not need an update service. The bundled release workflow runs only in
`mohnya-org/PrismWindow`. Maintainers who intentionally want to distribute a fork with updates
must opt into their own workflow, feed, signing keys, and release assets; do not direct fork
builds to the official app's update feed.

Users upgrading from a version without automatic updates must install the first
update-enabled release manually.

## First installation: signed DMG

Releases include a signed, notarized `<app>-<version>-macOS.dmg` and its SHA-256 checksum.
Open the DMG in Finder, drag the app onto its Applications shortcut, eject the image,
and launch the installed app from Applications. Sparkle continues to use the ZIP and appcast.
Do not launch the app directly from the mounted image.

The DMG uses the existing `APPLE_CERT_BASE64` / `APPLE_CERT_PASSWORD` Developer ID
Application identity and `APPLE_TEAM_ID`. Notarization reuses `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID`, and `APPLE_API_PRIVATE_KEY`; no separate DMG certificate or API key
is needed. Apple Distribution certificates are not a substitute for Developer ID Application.
The workflow uses a private temporary keychain without changing the default keychain.
It signs and notarizes the image, staples its ticket, then mounts it read-only to verify
Gatekeeper acceptance, the embedded app signature/version, and the Applications shortcut.
All ZIP, DMG, checksum, and appcast files must exist before publication.

To validate a trusted branch without publishing, manually dispatch `release-macos-app.yml`
with `validate_only=true`. This uses signing secrets but creates no tag or release.
The verified DMG is retained as a workflow artifact for seven days. Offline DMG tests:
`python3 -B scripts/test-macos-dmg.py`.

Prefer organization secrets scoped to selected repositories or protected environments.
Inventory all consumers before narrowing existing all-repository access. Never copy another
organization's private keys into this project. Secret names alone do not establish certificate
validity; successful signing and notarization are required verification.

## Future PKG distribution

PKG creation is not enabled. It requires a separate **Developer ID Installer** certificate,
in addition to the Developer ID Application certificate that signs the bundled app.
An account holder should create it in Apple Developer, export it with its private key as a
password-protected `.p12`, and configure `APPLE_INSTALLER_CERT_BASE64` and
`APPLE_INSTALLER_CERT_PASSWORD` for the intended repositories. Do not replace the existing
Application certificate secrets. The current notarization API credentials can be reused;
a new App Store Connect app record or API key is not required just to add PKG packaging.

A future PKG workflow must sign with that Installer identity, notarize and staple the package,
and verify it with `pkgutil --check-signature`, `stapler validate`, and Gatekeeper's install
assessment before publication. Test installation and subsequent Sparkle updates on a clean Mac.
See [Apple's Developer ID certificate guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
