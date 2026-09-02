# Sefirah for Mac

Native **SwiftUI** macOS companion for [Sefirah Android](https://github.com/shrimqy/Sefirah-Android). It speaks the same TLS + NDJSON protocol as the Windows/Linux desktop app so an already-paired phone does not need Android-side changes.

This repository is a work-in-progress port. The original C# Uno sources live in [`legacy/`](legacy/) as a protocol reference and will be removed after the Mac app reaches feature parity.

## Status

Linux-parity SwiftUI companion: pairing, clipboard, notifications, SMS, file transfer, remote media, ringer/DND, scrcpy, battery, actions, menu bar, incoming-call overlay. Android storage opens via `sftp://` in Finder (no File Provider).

C# sources stay in [`legacy/`](legacy/) as the protocol oracle.

## Ports

Open **5149–5169** on the Mac firewall (UDP **5149** for discovery, TLS **5150–5169** for the control channel, **5152–5169** for file transfer).

## Build

Requires Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), macOS 14+.

```sh
scripts/fetch-scrcpy.sh   # vendors scrcpy/adb/scrcpy-server (pinned in scripts/scrcpy.lock)
xcodegen generate
xcodebuild -scheme Sefirah -destination 'platform=macOS' test
```

Open `Sefirah.xcodeproj` after generating. `xcodegen generate` fails if `Vendor/scrcpy/` has not been
populated, and a pre-build script fails the build if the vendored version drifts from the lock file.

## Screen mirroring

Sefirah.app bundles [scrcpy](https://github.com/Genymobile/scrcpy) (`scrcpy`, `adb`, `scrcpy-server`)
so **Mirror** works with no extra setup: connect the phone over USB with USB debugging enabled.
Third-party notices ship in `Contents/Resources/scrcpy/NOTICES.md`.

The default **native** backend mirrors inside the app's *Mirror* tab: Sefirah pushes `scrcpy-server`
with the bundled `adb`, opens an `adb forward` tunnel, decodes H.264/H.265 with VideoToolbox, plays
Opus/AAC/PCM audio through `AVAudioEngine` (no third-party codecs) and forwards mouse, scroll and
keyboard input as scrcpy control messages. The *Apps* tab launches a single app on a virtual display
(`new_display` + `START_APP`). Toolbar: Back / Home / Recents / Rotate / Screen off / Notifications /
Mute / Volume / Power / Fullscreen; the *Mirror* menu adds ⌘⇧M start, ⌘⇧. stop, ⌘⇧U mute, ⌘⇧R rotate.
A lost connection is retried once automatically (re-running `adb connect` for Wi-Fi devices).

Settings → Screen mirroring: backend (native or the external scrcpy window), "fall back to external
scrcpy when the native mirror fails", verbose server logs, and per device: Wi-Fi ADB, screen off,
UHID keyboard, clipboard autosync, hover forwarding, video (codec, max size, bit rate, fps, crop,
display id, rotation), audio (Mac / Mac+phone / phone only, Opus/AAC/raw, bit rate, buffer,
microphone), virtual display (size, flexible resize, unlock commands) and custom `key=value` server
options. An Advanced section takes custom scrcpy/adb paths (a custom scrcpy uses its own
scrcpy-server). Design notes: [`docs/design/native-mirror.md`](docs/design/native-mirror.md).

Some phones (Xiaomi/HyperOS) silently drop injected touches until *USB debugging (Security
settings)* is enabled; the mirror still works read-only and the toolbar keys keep working.

Release flow: archive → `xcodebuild -exportArchive -exportOptionsPlist scripts/ExportOptions.plist` →
`scripts/verify-bundle.sh build/export/Sefirah.app` → `notarytool submit` → `stapler staple`.

## Protocol notes

- UDP discovery `:5149`, TLS control channel `:5150–5169`
- Mutual TLS, ECDSA P-256, verification code = SHA-256 of sorted SPKIs (first 8 hex chars)
- QR pairing URL scheme: `sefirah://pair?data=...`

Upstream Windows/Linux documentation: [`legacy/README.md`](legacy/README.md). Android app: [Sefirah-Android](https://github.com/shrimqy/Sefirah-Android).
