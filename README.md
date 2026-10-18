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

## Development

Build and launch the app from source:

```bash
./scripts/build-app.sh
open ".build/release/Prism Window.app"
```

Use the app bundle for local testing: it includes the Sparkle framework required at runtime. `swift run PrismWindow` does not bundle that framework and can fail to launch. Quit any running copy of Prism Window before opening the newly built app.

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

## 自動アップデート（Sparkle 2）

アプリは定期的に更新を確認し、Sparkle 標準の画面でダウンロード・インストール・再起動します。
「Automatically check for updates」で定期チェックを切り替え、「Check for Updates…」で手動確認できます。
更新操作は Prism Window / FinderOne ではメニューバーのパネル、TartDesk ではアプリメニューにあります。

配布前に GitHub Actions の repository secrets を設定してください。

- `SPARKLE_PRIVATE_KEY`: Sparkle の `generate_keys -x` で書き出した秘密鍵。
- `SPARKLE_PUBLIC_ED_KEY`: 同じ鍵の `generate_keys -p` が表示する公開鍵。

Sparkle のツールは SPM ビルド後の `.build/artifacts/sparkle/Sparkle/bin`、
Xcode では DerivedData の `SourcePackages/artifacts/sparkle/Sparkle/bin` にあります。
`generate_keys --account <app-name>` で鍵を一度だけ生成し、同じ `--account` を
`-p` と `-x` にも指定します。秘密鍵はリポジトリに保存せず、安全にバックアップしてください。
更新を継続できるよう、リリースごとに鍵を生成し直さないでください。

ワークフローは公開鍵をアプリに埋め込み、公証・staple 後の最終 ZIP に署名し、
`appcast.xml` を同じ GitHub Release に添付します。フィードは
`https://github.com/mohnya-org/PrismWindow/releases/latest/download/appcast.xml` です。
公開リポジトリの通常リリースが対象です。ZIP とフィードは一緒に公開してください。
main への push（PR マージを含む）で次の `vX.Y.Z` を自動採番します。
通常は既存の正式版タグの最大バージョンからパッチ番号を 1 増やします。
他のコミットで使われた未公開タグも予約済みとして飛ばし、タグを上書きしません。
初回タグがない場合は `v0.0.1` です。ソースのバージョンを書き換えるコミットは不要です。
Actions の手動実行では main を選び、任意で `version` に `1.5.0` のような
新しい正式版を指定できます。空欄なら自動採番します。

採番値を配布アプリのバージョンと ZIP 名に埋め込みます。
`CFBundleVersion` は Prism Window / FinderOne では Actions の run number、
TartDesk では採番したリリースバージョンです。
ビルド・署名・公証・フィード生成後にトリガー元コミットへタグを作り、
ZIP・チェックサム・appcast のアップロードが全部成功してから draft を公開します。
これにより Release 公開 Webhook は必要な成果物がそろった状態で通知されます。

失敗した場合は同じ Actions 実行を再実行できます。途中で作成済みの同一コミットの
タグ・draft は再利用し、公開済みなら何も変更しません。新しい正式版より古い
ソースを再公開する実行は拒否します。リリースは直列実行し、実行中のものは中止しません。
GitHub Actions の concurrency により、短時間にマージが続くと待機中の実行は最新のものに
置き換わる場合があります。その場合は最新コミットに含まれる変更をまとめて公開します。

秘密鍵が未設定ならリリースは失敗して停止します。公開鍵を省略した開発ビルドでは更新は無効です。
ローカルで有効にするには、SPM の build-app.sh に `SPARKLE_PUBLIC_ED_KEY` を渡すか、
FinderOne のビルド済み Info.plist の `SUPublicEDKey` に同じ公開鍵を設定してから署名します。
既存の自動更新未対応版からは、最初の対応版だけ手動でインストールする必要があります。
