# Bundling scrcpy in Sefirah.app — Design & Plan (final)

Branch: `feature/bundle-scrcpy` · Repo: `/Volumes/DATA/workspace/Sefirah-Mac` · No commits/pushes as part of this work.

## Summary

Ship `scrcpy`, `adb` and `scrcpy-server` inside `Sefirah.app` so **Mirror** works with zero user setup. The binaries come from the official Genymobile v4.1 macOS release tarballs (verified self-contained: only `/usr/lib` + system frameworks), are fetched by a pinned, sha256-verified script into a git-ignored `Vendor/scrcpy/`, and are placed in the bundle by xcodegen `copyFiles` entries with `CodeSignOnCopy`. Mach-O helpers live in `Contents/MacOS/` (nested code, re-signed with the app identity + hardened runtime); `scrcpy-server` and license/version data live in `Contents/Resources/scrcpy/`. Runtime resolution, environment building and stderr classification move into small pure `SefirahCore` types with unit tests; `AppModel.launchScrcpy` stops using `try?` and surfaces every failure in one alert. Mirroring still opens in scrcpy's own window (Option A).

This document merges the two candidates. Where they disagreed, I ran the mechanics on this machine (xcodegen 2.45.4, Xcode 26.5 SDK, Swift 6.3) — see Appendix A for what was verified and what was wrong in each candidate. The two most important corrections: **both candidates used a `buildPhases:` key that xcodegen does not have (it is silently ignored — nothing gets copied)**, and both placed executables in `Contents/Resources`, where codesign seals them as *data* rather than *nested code*.

## Goals / Non-goals

**Goals**
- Mirror works on a fresh install with no scrcpy/adb on the machine. No Homebrew.
- Notarizable Developer ID build: every embedded Mach-O signed with the app identity, hardened runtime, secure timestamp.
- Universal (arm64 + x86_64) — the app target has no `ARCHS` override, so Release archives are universal; the helpers must be too.
- Every failure path (missing binary, bad override path, spawn failure, non-zero exit, adb problems) is visible to the user.
- Power users keep the ability to point at their own scrcpy/adb.
- Reproducible vendoring: pinned version + sha256, one script, no network during `xcodebuild`.
- Pure, unit-tested core logic; the only untested code is the thin `Process` glue.

**Non-goals**
- Native in-app mirroring view (Option B) — see Future work.
- App Sandbox / Mac App Store — spawning adb/scrcpy and USB access preclude it; unchanged from today.
- Per-app window icons (`SCRCPY_ICON_PATH`), unlock-before-launch commands, video/audio codec pickers — legacy parity items deferred.
- PGP verification of `SHA256SUMS.txt.asc` — pinned sha256 is sufficient and avoids a `gpg` dependency.

## Background (current state)

- Build: `project.yml` (xcodegen) → `Sefirah.xcodeproj`; targets `SefirahCore` (framework), `Sefirah` (app), `SefirahCoreTests`. `SWIFT_VERSION: 6.0`, `CODE_SIGN_STYLE: Automatic`, Release sets `ENABLE_HARDENED_RUNTIME: YES` and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`. No entitlements file, no sandbox, `ENABLE_USER_SCRIPT_SANDBOXING` unset (defaults to NO, so script phases may read `$SRCROOT/Vendor`).
- Build/test command: `xcodebuild -project Sefirah.xcodeproj -scheme Sefirah -derivedDataPath build build test -destination 'platform=macOS'`.
- Launch path: `Sefirah/AppModel.swift:257-267` `launchScrcpy(package:appName:)` — path = `general.scrcpyPath` else `deviceSettings.scrcpyPath`; empty → silent return; `try? process.run()` swallows all errors; no environment, no stdout/stderr handling, no exit handling. Same idiom in `execute(_:)` (`AppModel.swift:273-283`).
- Callers: `Sefirah/Device/DeviceRailView.swift:39` (Mirror), `Sefirah/Apps/AppsView.swift:26` (Launch app), `AppModel.handleURL` (`sefirah://<package>`).
- Args: `SefirahCore/Features/ScrcpyArguments.swift` — pure builder, no path logic. **No tests exist for it.**
- Settings: `GeneralSettings.scrcpyPath/adbPath`, `DeviceSettings.scrcpyPath/adbPath/adbTcpipModeEnabled/adbAutoConnect/scrcpyDevicePreference` (`ScrcpyDevicePreferenceType: auto/usb/tcpip/askEverytime`). `Sefirah/Settings/SettingsView.swift:22-23` has two bare text fields. `ConnectedPeer` (`SefirahCore/Session/PeerModels.swift`) has `model` and `address`.
- Root UI: `Sefirah/RootView.swift` (one place for a global alert); `Sefirah/SefirahApp.swift` has an `AppDelegate` without model access.
- Legacy reference: `legacy/src/Sefirah/Services/ScreenMirrorService.cs` (`StartScrcpy` ~50, `DeviceSelection` ~370 matches adb devices by model + `ScrcpyDevicePreference`, `StartProcessMonitoring` ~492 collects stderr, treats exit 0/2 as OK); `AdbService.cs:696` `TryConnectTcp(host, model)` = `adb connect host:5555` → on failure find online USB device with matching model → `adb -s <serial> tcpip 5555` → wait 200 ms → retry connect.

## Binary acquisition

### Source of truth: Genymobile release v4.1

| Asset | SHA-256 |
|---|---|
| `scrcpy-macos-aarch64-v4.1.tar.gz` | `20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3` |
| `scrcpy-macos-x86_64-v4.1.tar.gz` | `ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72` |

URL base: `https://github.com/Genymobile/scrcpy/releases/download/v4.1/`. Verified facts: `scrcpy` links only `/usr/lib/*` and `/System/Library/Frameworks/*` (FFmpeg/SDL3/libusb static); `adb` is already a universal Mach-O signed by Google (Developer ID, hardened runtime); `adb` and `scrcpy-server` are byte-identical between the two tarballs; `scrcpy` is thin per arch and must be `lipo`'d. Upstream `scrcpy` is only ad-hoc/linker-signed (arm64) or unsigned (x86_64) → must be re-signed by our build (it is, via CodeSignOnCopy).

Local copies of both tarballs already exist in the scratch dir (`…/scratchpad/scrcpy-dl/`), and the fetch script accepts `SCRCPY_FETCH_TMP=<that dir>` to skip downloading.

### Vendor tree

```
Vendor/scrcpy/
  README.md        # committed: what this is, "run scripts/fetch-scrcpy.sh before xcodegen generate"
  NOTICES.md       # committed: third-party notices (shipped in the bundle)
  scrcpy           # ignored: universal, ad-hoc signed by the script (re-signed by Xcode)
  adb              # ignored: universal, Google-signed (re-signed by Xcode)
  scrcpy-server    # ignored: device-side payload (not Mach-O)
  LICENSE          # ignored: Apache-2.0 from the tarball
  VERSION          # ignored: "4.1"
  .stamp           # ignored: "<version>:<sha_aarch64>:<sha_x86_64>"
scripts/scrcpy.lock          # committed: single source of truth for version + sha256s
scripts/fetch-scrcpy.sh      # committed
scripts/verify-bundle.sh     # committed: post-archive signing checks
```

`.gitignore` additions (verified with `git check-ignore`):
```
# Vendored scrcpy (populated by scripts/fetch-scrcpy.sh)
Vendor/scrcpy/*
!Vendor/scrcpy/README.md
!Vendor/scrcpy/NOTICES.md
```

### `scripts/scrcpy.lock`
```bash
SCRCPY_VERSION=4.1
SCRCPY_AARCH64_SHA256=20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3
SCRCPY_X86_64_SHA256=ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72
```
Upgrading scrcpy = edit these three lines, run the script, rebuild. The pre-build guard compares `Vendor/scrcpy/VERSION` with the lock so a stale vendor tree fails the build instead of silently shipping the old version.

### `scripts/fetch-scrcpy.sh`
```bash
#!/usr/bin/env bash
# Vendor scrcpy/adb/scrcpy-server for Sefirah.app. Run before `xcodegen generate`.
# Idempotent. `--force` re-fetches. SCRCPY_FETCH_TMP=<dir> reuses already-downloaded tarballs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scrcpy.lock
source "$ROOT/scripts/scrcpy.lock"
OUT="$ROOT/Vendor/scrcpy"
BASE="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}"
STAMP="${SCRCPY_VERSION}:${SCRCPY_AARCH64_SHA256}:${SCRCPY_X86_64_SHA256}"
WORK="${SCRCPY_FETCH_TMP:-$(mktemp -d)}"
[[ -n "${SCRCPY_FETCH_TMP:-}" ]] || trap 'rm -rf "$WORK"' EXIT

if [[ "${1:-}" != "--force" && -f "$OUT/.stamp" && "$(cat "$OUT/.stamp")" == "$STAMP" && -x "$OUT/scrcpy" ]]; then
  echo "scrcpy $SCRCPY_VERSION already vendored at $OUT"; exit 0
fi

fetch() { # <arch> <sha256>
  local name="scrcpy-macos-$1-v${SCRCPY_VERSION}.tar.gz" file
  file="$WORK/$name"
  [[ -f "$file" ]] || curl -fsSL --retry 3 -o "$file" "$BASE/$name"
  echo "$2  $file" | shasum -a 256 -c - >/dev/null || { echo "error: sha256 mismatch for $name" >&2; exit 1; }
  rm -rf "$WORK/$1"; mkdir -p "$WORK/$1"
  tar -xzf "$file" -C "$WORK/$1" --strip-components=1
}
fetch aarch64 "$SCRCPY_AARCH64_SHA256"
fetch x86_64  "$SCRCPY_X86_64_SHA256"
A="$WORK/aarch64"; X="$WORK/x86_64"

# adb and scrcpy-server are arch-independent; refuse to guess if upstream changes that.
cmp -s "$A/adb" "$X/adb"                     || { echo "error: adb differs between arch tarballs" >&2; exit 1; }
cmp -s "$A/scrcpy-server" "$X/scrcpy-server" || { echo "error: scrcpy-server differs between arch tarballs" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/scrcpy "$OUT"/adb "$OUT"/scrcpy-server "$OUT"/LICENSE "$OUT"/VERSION "$OUT"/.stamp
lipo -create "$A/scrcpy" "$X/scrcpy" -output "$OUT/scrcpy"
cp "$A/adb" "$A/scrcpy-server" "$A/LICENSE" "$OUT/"
chmod 755 "$OUT/scrcpy" "$OUT/adb"; chmod 644 "$OUT/scrcpy-server" "$OUT/LICENSE"
xattr -c "$OUT/scrcpy" "$OUT/adb" "$OUT/scrcpy-server" "$OUT/LICENSE" 2>/dev/null || true
# Ad-hoc sign with a stable identifier. Xcode's Copy Files phase re-signs with the app identity
# using --preserve-metadata=identifier, so this identifier is what ships (otherwise it would be the
# linker-generated "scrcpy-5555…" hash name).
codesign --force --sign - --identifier io.github.madeye.sefirah.scrcpy "$OUT/scrcpy"

# Sanity: universal, self-contained, runnable.
lipo -info "$OUT/scrcpy" | grep -q 'x86_64 arm64' || { echo "error: scrcpy is not universal" >&2; exit 1; }
if otool -L "$OUT/scrcpy" "$OUT/adb" | grep -Eq '@rpath|@executable_path|@loader_path|/opt/|/usr/local/'; then
  echo "error: vendored binaries have non-system dylib dependencies" >&2; exit 1
fi
"$OUT/scrcpy" --version | head -1
"$OUT/adb" version | head -1
printf '%s\n' "$SCRCPY_VERSION" > "$OUT/VERSION"
printf '%s\n' "$STAMP" > "$OUT/.stamp"
echo "vendored scrcpy $SCRCPY_VERSION -> $OUT"
```
Stock tools only (`curl`, `shasum`, `tar`, `lipo`, `codesign`, `otool`, `xattr`).

### Licenses / notices
`Vendor/scrcpy/NOTICES.md` (committed, copied into `Contents/Resources/scrcpy/`) lists: scrcpy + scrcpy-server — Apache-2.0, © Genymobile / Romain Vimont; adb (Android platform-tools) — Apache-2.0, Google; statically linked into the scrcpy binary: FFmpeg (LGPL-2.1+), SDL3 (zlib), libusb (LGPL-2.1), with upstream links. The tarball's `LICENSE` ships next to it. Settings gets a "Third-party notices" link (see Settings).

## Bundle layout & signing

### Layout
```
Sefirah.app/Contents/
  MacOS/Sefirah                 # main executable
  MacOS/scrcpy                  # nested code, CodeSignOnCopy
  MacOS/adb                     # nested code, CodeSignOnCopy
  Resources/scrcpy/scrcpy-server
  Resources/scrcpy/LICENSE
  Resources/scrcpy/NOTICES.md
  Resources/scrcpy/VERSION
```
Why `Contents/MacOS` and not `Contents/Resources/scrcpy` (both candidates): verified on a scratch project that executables copied to `Contents/MacOS` are recorded in `_CodeSignature/CodeResources` under `files2` with `cdhash` + `requirement` (i.e. as **nested code**), while anything under `Resources/` is sealed with a plain `hash2` (**data**). TN2206 says not to put executable code in `Resources`; Xcode's export re-sign walks nested-code locations, and Gatekeeper/notarization treat them as code. `Bundle.url(forAuxiliaryExecutable:)` is the API designed for exactly this location. scrcpy's built-in "portable" fallback also finds `adb` next to itself in this layout, but we set env vars explicitly regardless.

### `project.yml` changes (target `Sefirah`)

xcodegen has **no `buildPhases` key** — both candidates' YAML generates a project that copies nothing (verified: `xcodegen generate` succeeds, the build succeeds, the bundle contains no helpers). The supported form is a `sources` entry with `buildPhase.copyFiles` and `attributes: [CodeSignOnCopy]`, which produces `settings = {ATTRIBUTES = (CodeSignOnCopy, ); }` in the pbxproj (verified):

```yaml
  Sefirah:
    type: application
    platform: macOS
    sources:
      - Sefirah
      # Vendored scrcpy — populated by scripts/fetch-scrcpy.sh (run it before `xcodegen generate`;
      # xcodegen fails on missing source paths). Mach-O helpers → Contents/MacOS as nested code,
      # signed on copy with the app identity (+ hardened runtime in Release). Data → Resources/scrcpy.
      - path: Vendor/scrcpy/scrcpy
        buildPhase: { copyFiles: { destination: executables } }
        attributes: [CodeSignOnCopy]
      - path: Vendor/scrcpy/adb
        buildPhase: { copyFiles: { destination: executables } }
        attributes: [CodeSignOnCopy]
      - path: Vendor/scrcpy/scrcpy-server
        buildPhase: { copyFiles: { destination: resources, subpath: scrcpy } }
      - path: Vendor/scrcpy/LICENSE
        buildPhase: { copyFiles: { destination: resources, subpath: scrcpy } }
      - path: Vendor/scrcpy/NOTICES.md
        buildPhase: { copyFiles: { destination: resources, subpath: scrcpy } }
      - path: Vendor/scrcpy/VERSION
        buildPhase: { copyFiles: { destination: resources, subpath: scrcpy } }
    preBuildScripts:
      - name: Check vendored scrcpy
        shell: /bin/bash
        basedOnDependencyAnalysis: false
        script: |
          source "$SRCROOT/scripts/scrcpy.lock"
          V="$SRCROOT/Vendor/scrcpy"
          if [ ! -x "$V/scrcpy" ] || [ ! -x "$V/adb" ] || [ ! -f "$V/scrcpy-server" ]; then
            echo "error: Vendor/scrcpy is missing — run scripts/fetch-scrcpy.sh" >&2; exit 1
          fi
          HAVE="$(cat "$V/VERSION" 2>/dev/null || echo none)"
          if [ "$HAVE" != "$SCRCPY_VERSION" ]; then
            echo "error: Vendor/scrcpy is v$HAVE but scripts/scrcpy.lock pins v$SCRCPY_VERSION — run scripts/fetch-scrcpy.sh" >&2; exit 1
          fi
    dependencies:
      - target: SefirahCore
    # info:, settings: unchanged
```
No changes to `settings`. In particular **no `OTHER_CODE_SIGN_FLAGS: --timestamp`**: Xcode passes `--timestamp=none` during normal builds and `-exportArchive` re-signs with a secure timestamp for Developer ID; the flag is redundant (ad-hoc + `--timestamp` happens to be accepted, but it is noise).

Verified signing behaviour of the Copy Files phase (Release, `ENABLE_HARDENED_RUNTIME=YES`):
```
codesign --force --sign <identity> -o runtime --timestamp=none \
  --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der …/Contents/MacOS/scrcpy
```
→ nested `scrcpy`/`adb` get `flags=…(runtime)` and the app is signed last (inside-out, no `--deep`). In Debug (no hardened runtime) the same phase signs without `-o runtime`, which is fine for local runs. Nothing else is needed: scrcpy/adb load no third-party dylibs, no JIT, no plugins → no hardened-runtime exception entitlements; no sandbox → no `com.apple.security.inherit`.

xcodegen validates source paths: generating without the vendor tree fails with `Spec validation error: Target "Sefirah" has a missing source directory …/Vendor/scrcpy/scrcpy`. This is acceptable and documented ("fetch before generate"); the pre-build guard covers the case where the tree is deleted or stale after generation.

### Release signing & notarization flow
```
scripts/fetch-scrcpy.sh && xcodegen generate
xcodebuild -project Sefirah.xcodeproj -scheme Sefirah -configuration Release archive \
  -archivePath build/Sefirah.xcarchive -allowProvisioningUpdates \
  -authenticationKeyID 9FU24T97RY -authenticationKeyIssuerID 488e5361-7842-427f-80e3-80ca80ff3cd6 \
  -authenticationKeyPath /Users/mlv/.appstoreconnect/private_keys/AuthKey_9FU24T97RY.p8
xcodebuild -exportArchive -archivePath build/Sefirah.xcarchive -exportPath build/export \
  -exportOptionsPlist scripts/ExportOptions.plist        # method: developer-id, teamID: 32B45SMMQL, signingStyle: automatic
scripts/verify-bundle.sh build/export/Sefirah.app        # fails unless every nested Mach-O has runtime+timestamp+Developer ID
ditto -c -k --keepParent build/export/Sefirah.app build/Sefirah.zip
xcrun notarytool submit build/Sefirah.zip --key …/AuthKey_9FU24T97RY.p8 --key-id 9FU24T97RY --issuer 488e5361-… --wait
xcrun stapler staple build/export/Sefirah.app
```
`scripts/verify-bundle.sh <app>` asserts: files exist at the layout above; `codesign --verify --deep --strict --verbose=2` passes; for `MacOS/scrcpy` and `MacOS/adb`: `codesign -dvv` shows `flags=0x10000(runtime)`, `TeamIdentifier=32B45SMMQL`, `Authority=Developer ID Application`, and a `Timestamp=` line; `lipo -info MacOS/scrcpy` contains both arches; `spctl -a -t exec -vv <app>` accepts (after stapling). Re-signing `adb` replaces Google's signature with ours — intended; mixed team IDs inside one bundle are a recurring notarization annoyance.

## Runtime design (Swift API)

All decision logic is in `SefirahCore/Features/Mirroring/` and is pure or injectable. `Process` is touched in exactly two places: `ScrcpyProcessRunner` (long-lived scrcpy) and `ProcessCommandRunner` (short adb commands).

### `BundledTools.swift`
```swift
public struct BundledTools: Sendable, Equatable {
    public var scrcpy: URL      // Contents/MacOS/scrcpy
    public var adb: URL         // Contents/MacOS/adb
    public var server: URL      // Contents/Resources/scrcpy/scrcpy-server
    public var version: String? // Contents/Resources/scrcpy/VERSION, trimmed

    /// nil if any of the three binaries is missing — callers report, never guess.
    public static func locate(in bundle: Bundle = .main, fileManager: FileManager = .default) -> BundledTools?

    /// Pure core used by `locate` and tests.
    static func locate(
        auxiliaryExecutable: (String) -> URL?,   // bundle.url(forAuxiliaryExecutable:)
        resourcesRoot: URL?,                     // bundle.resourceURL
        exists: (URL) -> Bool,
        readVersion: (URL) -> String?
    ) -> BundledTools?
}
```

### `ScrcpyLaunchPlan.swift`
```swift
public enum ScrcpyLaunchError: Error, Equatable, LocalizedError {
    case scrcpyUnavailable                                  // no bundled tools and no override
    case overrideNotFound(tool: String, path: String)       // user set a path that is not an executable file
    case bundledToolMissing(String)                          // bundle damaged: "scrcpy" | "adb" | "scrcpy-server"
    public var errorDescription: String? { … }
}

public struct ScrcpyLaunchPlan: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var adb: URL?                 // what adb the plan uses (nil = let scrcpy search PATH)
    public var usesBundledScrcpy: Bool
}

public enum ScrcpyLaunchPlanner {
    public static func plan(
        general: GeneralSettings,
        device: DeviceSettings,
        bundled: BundledTools?,
        serial: String?,
        package: String? = nil,
        appName: String? = nil,
        baseEnvironment: [String: String],   // ProcessInfo.processInfo.environment at call site
        home: String,                        // NSHomeDirectory() at call site
        isExecutable: (URL) -> Bool          // FileManager.isExecutableFile at call site
    ) throws -> ScrcpyLaunchPlan
}
```
Rules (all unit-tested):
1. **scrcpy**: `general.scrcpyPath` → `device.scrcpyPath` → `bundled.scrcpy`. An override that is set but not executable throws `.overrideNotFound` — never silently fall back to bundled (the user asked for that path). No override and no bundle → `.scrcpyUnavailable`.
2. **adb**: `general.adbPath` → `device.adbPath` → `bundled.adb`, same override rule. `environment["ADB"]` is set to the result. (scrcpy 4.1 has no `--adb` flag; `ADB` is the documented env var.)
3. **server**: `environment["SCRCPY_SERVER_PATH"] = bundled.server` **only when the resolved scrcpy is the bundled one**. A user-supplied scrcpy (Homebrew, self-built) has its own matching server at a compiled-in path; injecting ours would produce a client/server version mismatch. (Candidate 2's "sibling else bundled" rule is wrong for Homebrew installs, whose server is in `share/scrcpy/`, not a sibling.)
4. `environment` starts from `baseEnvironment` (assigning `Process.environment` replaces the inherited env entirely, so it must be complete), then: `HOME` defaulted to `home` if absent (adb keys in `~/.android`), `PATH` defaulted to `/usr/bin:/bin:/usr/sbin:/sbin` if absent. `ANDROID_ADB_SERVER_PORT` is **not** set: sharing the default 5037 daemon means an already-authorised USB device and Android Studio keep working (see Risks).
5. `arguments = ScrcpyArguments.build(settings: device, serial: serial, package: package, appName: appName)` — `ScrcpyArguments` is unchanged.

### `ScrcpyProcessRunner.swift`
```swift
public enum ScrcpyExit: Equatable, Sendable {
    case normal(code: Int32)                       // 0 = success, 2 = SCRCPY_EXIT_DISCONNECTED (device unplugged)
    case failure(code: Int32, stderr: String)      // anything else
    case signaled(Int32, stderr: String)           // SIGKILL (9) typically = code-signature rejection
}

public protocol ScrcpyRunning: AnyObject, Sendable {
    /// Launches; if a process for `key` is already running it is terminated first.
    func launch(_ plan: ScrcpyLaunchPlan, key: String, onExit: @escaping @Sendable (ScrcpyExit) -> Void) throws
    func terminate(key: String)
    func terminateAll()
    var runningKeys: Set<String> { get }
}

public final class ScrcpyProcessRunner: ScrcpyRunning { … }
```
Implementation notes: `standardOutput = FileHandle.nullDevice`; `standardError = Pipe()` drained continuously via `readabilityHandler` into a bounded tail buffer (last 16 KB) — **not** `readDataToEndOfFile()` in the termination handler (Candidate 1): a pipe nobody drains fills at 64 KB and scrcpy then blocks on `write(2)` mid-session, freezing the mirror. State is behind an `NSLock`; `terminationHandler` runs on an arbitrary thread and calls `onExit` after clearing the handler and reading `availableData`. `terminate(key:)` sends SIGTERM (scrcpy cleans up its `adb reverse` tunnel on exit).

### `ScrcpyDiagnostics.swift`
```swift
public enum ScrcpyDiagnostics {
    /// Maps scrcpy/adb stderr to a one-line, actionable hint; nil if unrecognised.
    public static func hint(exit: ScrcpyExit) -> String?
}
```
Patterns: `no devices/emulators found` / `Could not find any ADB device` → "No Android device is visible to adb. Connect it over USB with USB debugging enabled, or enable Wireless debugging."; `unauthorized` → "Accept the USB-debugging prompt on the phone."; `more than one device` → "Several devices are connected; set a device preference or add `-s <serial>` to custom arguments."; `server version` → "scrcpy-server does not match the scrcpy binary (custom scrcpy path?)."; `device offline` → "adb reports the device offline; replug or run `adb reconnect`."; `.signaled(9, …)` → "macOS refused to run the bundled scrcpy (code signature). Reinstall Sefirah.".

### `Adb.swift` (Phase 2)
```swift
public struct AdbDevice: Equatable, Sendable {
    public var serial: String; public var state: String        // device | offline | unauthorized | …
    public var model: String?                                   // "model:Pixel_7" from `devices -l`
    public var isTcp: Bool { serial.contains(":") }
}
public struct CommandResult: Equatable, Sendable { public var exitCode: Int32; public var stdout: String; public var stderr: String }

public protocol CommandRunning: Sendable {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult
}
public struct ProcessCommandRunner: CommandRunning { … }     // Process + Pipes + timeout → terminate

public enum AdbError: Error, Equatable, LocalizedError {
    case spawnFailed(String), timeout(command: String)
    case connectFailed(host: String, message: String)
    case noUsbDeviceForTcpip(model: String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
}

public enum AdbOutput {                                          // pure, tested
    public static func parseDevices(_ stdout: String) -> [AdbDevice]     // skips "List of devices attached" and "* daemon …" lines
    public static func connectSucceeded(_ output: String) -> Bool         // "connected to" | "already connected to"
    public static func modelMatches(adbModel: String?, peerModel: String) -> Bool  // alnum-only, case-insensitive ("Pixel_7" == "Pixel 7")
}

public struct AdbClient: Sendable {
    public init(adb: URL, environment: [String: String], runner: any CommandRunning = ProcessCommandRunner())
    public func devices() async throws -> [AdbDevice]                                // adb devices -l   (5 s)
    public func connect(host: String, port: Int = 5555) async throws -> String        // adb connect      (8 s) → serial
    public func tcpip(serial: String, port: Int = 5555) async throws                  // adb -s S tcpip   (5 s)
    /// Port of legacy TryConnectTcp: connect → else USB device with matching model → tcpip → sleep 200 ms → connect.
    public func tryConnectTcp(host: String, model: String, port: Int = 5555) async throws -> String
}

public enum ScrcpyDeviceSelection {                                // pure, tested; port of legacy DeviceSelection
    /// nil = let scrcpy pick (exactly one device, or none visible — scrcpy reports that itself).
    public static func serial(devices: [AdbDevice], peerModel: String, preference: ScrcpyDevicePreferenceType) -> String?
}
```
Selection: filter `state == "device"`; if ≤1 device → nil; else among model matches pick USB for `.usb`, TCP for `.tcpip`, TCP-then-USB for `.auto`; `.askEverytime` behaves as `.auto` in v1 (no picker UI yet).

### `Sefirah/AppModel.swift`
```swift
struct ToolFailure: Identifiable, Equatable { let id = UUID(); var title: String; var message: String; var detail: String? }

var toolFailure: ToolFailure?                     // drives the single alert in RootView
var mirroringKeys: Set<String> = []               // Mirror button state
var bundledScrcpyVersion: String? { bundledTools?.version }
private let bundledTools = BundledTools.locate()
private let scrcpyRunner: any ScrcpyRunning = ScrcpyProcessRunner()
private let commandRunner: any CommandRunning = ProcessCommandRunner()

func launchScrcpy(package: String? = nil, appName: String? = nil) {
    Task { await launchScrcpyAsync(package: package, appName: appName) }
}

func launchScrcpyAsync(package: String? = nil, appName: String? = nil) async {
    guard let device = selectedDevice else { return }
    let deviceSettings = (try? settings.loadDevice(id: device.id)) ?? DeviceSettings(deviceId: device.id)
    let env = ProcessInfo.processInfo.environment, home = NSHomeDirectory()
    let isExec = { FileManager.default.isExecutableFile(atPath: $0.path) }

    // Resolve tools first with serial nil so tool errors surface before any adb call.
    let base: ScrcpyLaunchPlan
    do { base = try ScrcpyLaunchPlanner.plan(general: general, device: deviceSettings, bundled: bundledTools,
                                            serial: nil, package: package, appName: appName,
                                            baseEnvironment: env, home: home, isExecutable: isExec) }
    catch { toolFailure = .init(title: "Screen mirroring unavailable", message: error.localizedDescription,
                                detail: "Bundled scrcpy: \(bundledScrcpyVersion ?? "missing")"); return }

    // Phase 2: optional Wi‑Fi connect + serial selection.
    var serial: String? = nil
    if let adb = base.adb {
        let client = AdbClient(adb: adb, environment: base.environment, runner: commandRunner)
        if deviceSettings.adbTcpipModeEnabled {
            do { serial = try await client.tryConnectTcp(host: device.address, model: device.model) }
            catch { toolFailure = .init(title: "Could not reach \(device.name) over ADB", message: error.localizedDescription,
                                        detail: "Enable Wireless debugging, or connect once over USB so Sefirah can switch the phone to TCP/IP mode."); return }
        } else if let devices = try? await client.devices() {
            serial = ScrcpyDeviceSelection.serial(devices: devices, peerModel: device.model, preference: deviceSettings.scrcpyDevicePreference)
        }   // adb listing failures are non-fatal here; scrcpy produces its own error which we surface on exit
    }

    let plan = serial == nil ? base : (try? ScrcpyLaunchPlanner.plan(/* same, serial: serial */)) ?? base
    let key = package.map { "\(device.id):\($0)" } ?? device.id
    do {
        try scrcpyRunner.launch(plan, key: key) { [weak self] exit in
            Task { @MainActor in self?.handleScrcpyExit(exit, key: key, plan: plan) }
        }
        mirroringKeys.insert(key)
    } catch {
        toolFailure = .init(title: "Could not start scrcpy", message: error.localizedDescription, detail: plan.executable.path)
    }
}

private func handleScrcpyExit(_ exit: ScrcpyExit, key: String, plan: ScrcpyLaunchPlan) {
    mirroringKeys.remove(key)
    switch exit {
    case .normal: return
    case .failure(let code, let stderr), .signaled(let code, let stderr):
        toolFailure = .init(title: "scrcpy exited (code \(code))",
                            message: ScrcpyDiagnostics.hint(exit: exit) ?? "scrcpy reported an error.",
                            detail: stderr.isEmpty ? plan.executable.path : stderr)
    }
}

func stopMirroring(key: String? = nil) { key.map(scrcpyRunner.terminate) ?? scrcpyRunner.terminateAll() }
```
`execute(_:)` (custom actions) gets the same three-line `do { try process.run() } catch { toolFailure = … }` treatment so the last `try? run()` in the app disappears. `handleURL` is unchanged; errors now show in the alert.

Quit: `AppModel.init` observes `NSApplication.willTerminateNotification` and calls `stopMirroring()` so scrcpy windows don't outlive the app (and don't pin a bundle path that changes on upgrade). **No `adb kill-server` on quit** — it would kill the user's Android Studio/other adb session; a "Restart ADB server" button in Settings covers troubleshooting.

## Error handling & UX

- One alert: `RootView` adds `.alert(item: $model.toolFailure) { Alert(title:message:) }` with the `detail` (path or the last lines of stderr, monospaced) appended below the message. Covers Mirror, app Launch, `sefirah://` deep links and custom actions.
- Failure classes and what the user sees:
  | Situation | Where caught | Message |
  |---|---|---|
  | Bundle damaged / helper missing | `ScrcpyLaunchPlanner` | "Screen mirroring unavailable — bundled scrcpy is missing (adb). Reinstall Sefirah." |
  | Override path wrong | `ScrcpyLaunchPlanner` | "scrcpy path '/opt/x' is not an executable file. Clear it in Settings to use the bundled copy." |
  | Spawn failed (EACCES, killed by Gatekeeper, wrong arch) | `launch` throws / `.signaled(9)` | "Could not start scrcpy" + hint |
  | scrcpy exit ≠ 0/2 | `handleScrcpyExit` | hint from stderr + stderr tail |
  | adb TCP connect failed (opt-in) | `AdbClient` | connect/tcpip error + how to fix |
- Exit 0 and 2 (device disconnected) are silent, matching legacy.
- `DeviceRailView`: "Mirror" becomes "Mirror" / "Stop" based on `mirroringKeys.contains(device.id)`; disabled with a help tooltip when `bundledScrcpyVersion == nil` and no override is set.

## Settings

`Sefirah/Settings/SettingsView.swift`:
- Remove the two bare fields from **General**.
- New `Section("Screen mirroring")`:
  - `LabeledContent("Bundled scrcpy", value: model.bundledScrcpyVersion.map { "v\($0)" } ?? "Not found — reinstall Sefirah")`.
  - `DisclosureGroup("Advanced")`: `TextField("Custom scrcpy path")` and `TextField("Custom adb path")` bound to `model.general.*` with footer "Leave empty to use the bundled copies. A custom scrcpy uses its own scrcpy-server."; optional `Button("Choose…")` via `NSOpenPanel` (10 lines; nice-to-have); `Toggle("Connect over Wi‑Fi (ADB TCP/IP)", isOn: <selected device's adbTcpipModeEnabled>)` (per device, persisted through `settings.saveDevice`); `Button("Restart ADB server")` → `adb kill-server` then `adb start-server` with the bundled/overridden adb, result shown inline.
- **About**: `Link("Third-party notices")` opening `Contents/Resources/scrcpy/NOTICES.md` with `NSWorkspace`.
- `GeneralSettings`/`DeviceSettings` schemas unchanged — no migration; empty path = bundled.

## Tests (`SefirahCoreTests`, XCTest, no network, no device)

| File | Cases |
|---|---|
| `ScrcpyArgumentsTests.swift` (new — nothing pins the builder today) | defaults → `[]`; package+appName → `--start-app=`, `--window-title=`; serial → `-s`; `flexDisplay` + package → `16M`, `--new-display`, `-x --keep-active`; audio modes; `customArguments` splitting. |
| `BundledToolsTests.swift` | all present → URLs + version; any of the three missing → nil; VERSION absent → `version == nil`. Uses the pure `locate(auxiliaryExecutable:resourcesRoot:exists:readVersion:)`. |
| `ScrcpyLaunchPlannerTests.swift` | bundled → `ADB` + `SCRCPY_SERVER_PATH` set, `usesBundledScrcpy`; general override wins over device over bundled; override scrcpy → no `SCRCPY_SERVER_PATH`, `ADB` still bundled; override set but not executable → `.overrideNotFound` (no fallback); nothing → `.scrcpyUnavailable`; base env preserved, `HOME`/`PATH` only defaulted when absent; `arguments == ScrcpyArguments.build(...)`. |
| `ScrcpyProcessRunnerTests.swift` | `/bin/sh -c 'echo boom >&2; exit 3'` → `.failure(3,"boom")`; `exit 2` → `.normal(2)`; 200 KB of stderr then exit 0 → completes (drain test); relaunch same key terminates the first; `terminateAll` on `sleep 30` → exit reported, `runningKeys` empty. |
| `ScrcpyDiagnosticsTests.swift` | each pattern → expected hint; unknown → nil; `.signaled(9)` → reinstall hint. |
| `AdbOutputTests.swift` | `parseDevices` on realistic `devices -l` output incl. `* daemon started successfully`, `unauthorized`, `offline`, TCP serials; `connectSucceeded` for connected / already connected / failed / refused; `modelMatches("Pixel_7", "Pixel 7")`, `("SM_G991B","SM-G991B")`. |
| `AdbClientTests.swift` | `FakeCommandRunner` scripted: connect ok first try; connect fails → USB match → `tcpip` → retry ok; no USB match → `.noUsbDeviceForTcpip`; spawn throws → `.spawnFailed`; timeout. |
| `ScrcpyDeviceSelectionTests.swift` | one device → nil; two devices, model match usb/tcp per preference; no match → nil. |

Not unit-tested (checked by scripts/manual): fetch script, xcodegen wiring, signing (`scripts/verify-bundle.sh`).

## Implementation plan

Branch `feature/bundle-scrcpy` (already checked out). Do not commit or push.

| # | Step | Files |
|---|---|---|
| 1 | Lock + fetch script; run `SCRCPY_FETCH_TMP=…/scratchpad/scrcpy-dl scripts/fetch-scrcpy.sh`; confirm `lipo -info`, `otool -L`, `--version`. | `scripts/scrcpy.lock`, `scripts/fetch-scrcpy.sh` (new, `chmod +x`) |
| 2 | Vendor docs + notices + ignore rules. | `Vendor/scrcpy/README.md`, `Vendor/scrcpy/NOTICES.md` (new), `.gitignore` |
| 3 | xcodegen wiring (sources copyFiles entries, pre-build guard); `xcodegen generate`; Debug build; inspect bundle layout and `codesign -dvv` of nested binaries; run `Contents/MacOS/scrcpy --version` from the built app. | `project.yml`, `Sefirah.xcodeproj` (generated) |
| 4 | Core Phase 1: `BundledTools`, `ScrcpyLaunchPlan`/`Planner`, `ScrcpyProcessRunner`, `ScrcpyDiagnostics`. | `SefirahCore/Features/Mirroring/{BundledTools,ScrcpyLaunchPlan,ScrcpyProcessRunner,ScrcpyDiagnostics}.swift` |
| 5 | Tests for step 4 + `ScrcpyArgumentsTests`. | `SefirahCoreTests/{ScrcpyArgumentsTests,BundledToolsTests,ScrcpyLaunchPlannerTests,ScrcpyProcessRunnerTests,ScrcpyDiagnosticsTests}.swift` |
| 6 | App Phase 1: `toolFailure`, `mirroringKeys`, `launchScrcpyAsync` (serial nil), `handleScrcpyExit`, `stopMirroring`, willTerminate observer, `execute(_:)` do/catch; alert in RootView; Mirror/Stop button. | `Sefirah/AppModel.swift`, `Sefirah/RootView.swift`, `Sefirah/Device/DeviceRailView.swift` |
| 7 | Settings UI: Screen mirroring section, Advanced disclosure, Restart ADB server, notices link. | `Sefirah/Settings/SettingsView.swift` |
| 8 | Build + test: `xcodebuild -project Sefirah.xcodeproj -scheme Sefirah -derivedDataPath build build test -destination 'platform=macOS'`. Manual USB mirror with a phone. | — |
| 9 | Core Phase 2: `CommandRunning`/`ProcessCommandRunner`, `AdbOutput`, `AdbClient`, `ScrcpyDeviceSelection` + tests; wire serial selection and opt-in `tryConnectTcp` into `launchScrcpyAsync`; Wi‑Fi toggle in Settings. | `SefirahCore/Features/Mirroring/Adb.swift`, `SefirahCoreTests/{AdbOutputTests,AdbClientTests,ScrcpyDeviceSelectionTests}.swift`, `Sefirah/AppModel.swift`, `SettingsView.swift` |
| 10 | Release tooling: `scripts/verify-bundle.sh`, `scripts/ExportOptions.plist`; README "Screen mirroring" + developer note. | `scripts/verify-bundle.sh`, `scripts/ExportOptions.plist`, `README.md` |
| 11 | Archive → export → `verify-bundle.sh` → notarize → staple (requires a Developer ID Application cert under `32B45SMMQL`; see Open questions). | — |

Rough size: ~350 lines core (Phase 1 ≈ 200, Phase 2 ≈ 150), ~120 lines app/UI, ~350 lines tests, ~120 lines scripts. App grows by ≈ 40 MB uncompressed (universal scrcpy ≈ 19 MB, adb ≈ 20 MB, server 0.7 MB).

## Verification checklist

Build-time
- [ ] `scripts/fetch-scrcpy.sh` twice: second run prints "already vendored"; `--force` re-vendors.
- [ ] `lipo -info Vendor/scrcpy/scrcpy` → `x86_64 arm64`; `otool -L Vendor/scrcpy/{scrcpy,adb}` has no `@rpath`/`/opt`/`/usr/local`.
- [ ] `xcodegen generate` succeeds; `grep -c CodeSignOnCopy Sefirah.xcodeproj/project.pbxproj` == 2.
- [ ] Debug build: `build/Build/Products/Debug/Sefirah.app/Contents/MacOS/{scrcpy,adb}` and `Contents/Resources/scrcpy/{scrcpy-server,LICENSE,NOTICES.md,VERSION}` exist; `Contents/MacOS/scrcpy --version` prints 4.1.
- [ ] Delete `Vendor/scrcpy/VERSION` → build fails with the "run scripts/fetch-scrcpy.sh" message; restore.
- [ ] `xcodebuild … test` green, including the new suites.

Runtime (Debug)
- [ ] Phone on USB, USB debugging on: Mirror opens scrcpy window; button shows Stop; closing the window returns it to Mirror with no alert; unplugging mid-session (exit 2) shows no alert.
- [ ] No phone: alert with "No Android device is visible to adb…".
- [ ] Phone unauthorized: alert with "Accept the USB-debugging prompt…".
- [ ] Emulator + phone both attached: `ScrcpyDeviceSelection` picks the phone (model match), no "more than one device" error.
- [ ] Settings → custom scrcpy path `/nonexistent`: alert names the path; clearing it restores bundled behaviour. Custom Homebrew scrcpy (if present) launches without `server version mismatch`.
- [ ] Rename `Contents/MacOS/adb` in the built app → alert "bundled scrcpy is missing (adb)"; restore.
- [ ] Wi‑Fi toggle on, phone previously `tcpip 5555`'d: mirror over Wi‑Fi with USB unplugged; with the phone never switched, the error alert explains the USB-once step.
- [ ] Quit Sefirah while mirroring: scrcpy window closes; `pgrep -f Contents/MacOS/scrcpy` empty; `adb devices` still works for other tools (daemon not killed).
- [ ] Apps → Launch and `open sefirah://com.android.settings` both go through the same path and alert.

Release
- [ ] Archive + export; `scripts/verify-bundle.sh build/export/Sefirah.app` passes: nested `scrcpy`/`adb` show `flags=0x10000(runtime)`, `TeamIdentifier=32B45SMMQL`, `Authority=Developer ID Application: …`, `Timestamp=…`; `codesign --verify --deep --strict` OK.
- [ ] `notarytool submit --wait` → Accepted; `stapler staple`; copy to a second Mac (or `xattr -w com.apple.quarantine`), launch from Finder, Mirror works with no Gatekeeper dialog for the nested tools.
- [ ] `spctl -a -t exec -vv Sefirah.app` → accepted, source=Notarized Developer ID.

## Risks & open questions

**Risks**
- *Export re-sign coverage.* Verified that Xcode's Copy Files phase signs nested code in `Contents/MacOS` with `-o runtime`; not yet verified on this machine that `-exportArchive` re-signs them with Developer ID + timestamp (needs the cert). `verify-bundle.sh` makes this a hard gate; fallback is an explicit `codesign --force --options runtime --timestamp --sign "Developer ID Application: …" Contents/MacOS/{scrcpy,adb}` followed by re-signing the app, before notarization.
- *Hardened runtime vs scrcpy features.* scrcpy uses Metal/AVFoundation/GameController/IOKit(libusb for `--otg`/`uhid`). No entitlement needs are known; test `--keyboard=uhid` (`physicalKeyboard`) and audio playback on the signed Release build. TCC prompts, if any, are attributed to Sefirah (responsible process), so any usage-description key would go in Sefirah's `Info.plist`.
- *Shared adb daemon (5037).* If another adb of a different version is running, our first adb call restarts the daemon ("adb server version doesn't match, killing…") — a transient hiccup for Android Studio, not for Sefirah. Opt-in `ANDROID_ADB_SERVER_PORT` isolation is a one-line env addition if reports come in; kept off because isolation forces re-authorisation and a second daemon.
- *TCP auto-connect semantics.* `adb connect ip:5555` works only after a `tcpip 5555` over USB (Android 11+ "Wireless debugging" pairs on a different port and is not supported here). `ConnectedPeer.address` is the Sefirah TLS address, which may differ from the USB-tethering IP. Port 5555 is unauthenticated, so this stays opt-in per device (`adbTcpipModeEnabled`, default false).
- *Model matching.* adb reports `model:Pixel_7` (spaces → underscores); Sefirah's `ConnectedPeer.model` is `Build.MODEL`. `modelMatches` compares alphanumerics only; a phone with an unusual model string simply gets no `-s` and scrcpy's own "more than one device" error, which we surface with a hint.
- *xcodegen validation.* `xcodegen generate` fails without the vendor tree — by design, documented in README and `Vendor/scrcpy/README.md`.
- *Version coupling.* Bundled scrcpy and scrcpy-server always match (same tarball). User overrides never receive our server path. `ScrcpyDiagnostics` catches the mismatch message if a user forces one via `customArguments`.
- *Size.* ≈ 40 MB more on disk. Dropping x86_64 would require `ARCHS=arm64` on the app too; not proposed.
- *Stale daemon after upgrade.* The daemon started from an old bundle path keeps running after an update; adb self-restarts on version mismatch, and "Restart ADB server" in Settings covers the rest.

**Open questions**
1. Is there a *Developer ID Application* certificate under team `32B45SMMQL` yet? The global notes say the old `SK4GFF6AHN` certs are stale; step 11 blocks on this.
2. Keep universal (proposed) or arm64-only to save ≈ 9 MB?
3. `askEverytime` device preference: v1 treats it as `auto`; do we want a picker sheet listing `adb devices -l` results?
4. Should `execute(_:)` (custom actions) share `toolFailure` (proposed yes, 3 lines) or stay silent?
5. Should the "Restart ADB server" button exist in v1 or be deferred until a collision is actually reported?

## Future work (Option B: native mirroring view)

Everything above except the `scrcpy` client binary is reusable for an in-app view: the vendored `adb` and `scrcpy-server`, `AdbClient`, device selection, and the error surface. Option B replaces the `scrcpy` process with a Swift implementation of the scrcpy client protocol (documented in scrcpy's `doc/develop.md`; the wire protocol is versioned and must match the pinned `scrcpy-server` exactly):

1. `adb push scrcpy-server /data/local/tmp/scrcpy-server.jar`, `adb reverse localabstract:scrcpy tcp:<port>` (or `forward`), then `adb shell CLASSPATH=… app_process / com.genymobile.scrcpy.Server <version> [options]`.
2. Accept the video/audio/control sockets; parse the device-name header and codec metadata; feed H.264/H.265/AV1 packets to `VTDecompressionSession`, render `CVPixelBuffer`s in a Metal/`CALayer`-backed SwiftUI view; audio (Opus/AAC/raw) through `AVAudioEngine`.
3. Control socket: inject touch/key/scroll events from the view, clipboard sync, screen-power toggles — the same features `ScrcpyArguments` currently maps to CLI flags become typed options on the server command line.
4. Windowing becomes native (`Window(id: "mirror-\(deviceId)")`), enabling per-app windows with real icons, multiple mirrors, and Sefirah-styled toolbars — removing the SDL window, the extra Dock icon and the dependency on the `scrcpy` binary (and its FFmpeg/SDL/libusb static libs) entirely.

The Phase 1/2 API boundaries are chosen so that Option B swaps `ScrcpyProcessRunner` for a `ScrcpySession` actor behind the same `launch/terminate` shape, while `BundledTools` shrinks to `adb` + `server`.

---

## Appendix A — Candidate assessment (skeptical review)

Scores 1–5 (correctness with hardened runtime + Gatekeeper / simplicity / maintainability / test coverage).

**Candidate 1 (MVP-first): 2 / 5 / 3 / 3**
- Blocking error: `buildPhases:` is not an xcodegen key — silently ignored; the generated project copies nothing. Also `codeSignOnCopy:` is not a key (the mechanism is `attributes: [CodeSignOnCopy]` on a `sources` entry). Verified by generating and building a scratch project.
- Places Mach-Os in `Contents/Resources/scrcpy`; codesign seals them as data (`hash2`), not nested code — works for local runs but is the pattern TN2206 warns against and is the one export re-signing may skip.
- `readDataToEndOfFile()` in the termination handler with nothing draining the pipe during the session: a chatty scrcpy fills the 64 KB pipe and blocks on write, freezing the mirror. Real bug.
- `adb kill-server` on quit kills the user's Android Studio daemon — wrong default.
- `OTHER_CODE_SIGN_FLAGS: --timestamp` in `base`: not fatal (ad-hoc + `--timestamp` is accepted) but pointless; export handles timestamps.
- Pre-build guard cannot help because `xcodegen generate` already fails on the missing path; the candidate doesn't mention the validation.
- `throws(ScrcpyLaunchError)` typed throws: compiles under Swift 6.0, but unnecessary.
- Good: the small pure `plan` function, the "server path only when bundled" rule (correct), explicit `Process.environment` handling, exit-code 2 semantics, modest scope.

**Candidate 2 (robustness-first): 2.5 / 2 / 3 / 5**
- Same blocking `buildPhases:`/`codeSignOnCopy:` error; same `Resources` placement.
- Server rule 3 ("sibling else bundled") is wrong for Homebrew scrcpy (server at `share/scrcpy/scrcpy-server`, not a sibling; falling back to *our* server produces a version mismatch on an otherwise working install).
- `preBuildScripts` declares `outputFiles: Vendor/scrcpy/.stamp` the script never writes while also setting `basedOnDependencyAnalysis: false` — contradictory, harmless.
- `ToolError.wrongArchitecture` reserved but unimplemented; `PATH` prepend is unnecessary; the `ProcessRunning`/`AdbClient.devices()`/`tryConnectTcp`/diagnostics/verify script/Test-setup button/NSOpenPanel set is roughly 3× the code of the MVP for v1.
- Correctly identifies: stderr must be drained with a bounded buffer; no `kill-server` on quit; TCP connect must be opt-in; xcodegen validates missing source paths; `verify-bundle.sh` as a pre-notarization gate; missing `ScrcpyArguments` tests.
- Test plan is thorough and realistic (fake runner, `/bin/sh` process tests, parsers).

**What the synthesis takes**: Candidate 1's small planner + "server only when bundled" rule + single alert; Candidate 2's lock file, drain/ring buffer, `verify-bundle.sh`, opt-in TCP with legacy `TryConnectTcp` port, diagnostics hints, and test breadth (trimmed to what Phase 1/2 actually contain). Corrected in both: the xcodegen syntax, `Contents/MacOS` placement via `url(forAuxiliaryExecutable:)`, no `--timestamp` flag, stable code-signing identifier set in the fetch script, version-drift guard against the lock, and adb model normalisation.
