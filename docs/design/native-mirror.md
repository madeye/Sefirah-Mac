# Native in-app mirror (Option B) — Design & Plan (final)

Repo: `/Volumes/DATA/workspace/Sefirah-Mac`, branch `feature/native-mirror`. Targets: `Sefirah` (app), `SefirahCore` (framework), `SefirahCoreTests`. Swift 6 strict concurrency, macOS 14+, xcodegen `project.yml`.

## Summary

Sefirah will mirror an Android phone natively: it pushes the bundled `scrcpy-server` (v4.1) with the bundled `adb`, opens an `adb forward` tunnel, connects the video/audio/control sockets itself, decodes H.264/H.265 with VideoToolbox through an `AVSampleBufferDisplayLayer`, renders in a new **Mirror** tab of `MainSplitView`, forwards mouse/keyboard/scroll as scrcpy control messages, plays Opus/AAC/raw audio with `AVAudioConverter` + `AVAudioEngine`, and maps the existing `DeviceSettings` to server arguments. The external-scrcpy launch (Option A) stays as a user-selectable fallback behind the existing `ScrcpyRunning` seam. No third-party dependencies: `kAudioFormatOpus` decoding via AudioToolbox on macOS 14 was verified in this session.

The design merges the two candidates: candidate 1's pure-codec/golden-byte layering and correct handshake ordering, candidate 2's forward-only tunnel, event callback, `ServerProcess` log tail, reconnect policy and UX states. Candidate 2's device-meta ordering bug (reading the 64-byte name before the audio/control sockets are connected — a guaranteed deadlock in forward mode, verified against `DesktopConnection.open` / `Server.java:105-108`) is fixed here. Appendix A has the per-candidate review and scores.

## Goals / Non-goals

**Goals**
- Mirror video (H.264 default, H.265 option) with sub-100 ms glass-to-glass latency on Wi-Fi ADB; handle rotation/resize (session packets) without restarting.
- Full control: touch via mouse, scroll, keyboard (SDK mixed mode; UHID physical-keyboard mode), clipboard sync, toolbar keys (Home/Back/Recents/Power/Volume/Rotate/Notifications), screen-off, virtual display + START_APP (per-app launches from the Apps tab), flex display resize.
- Audio: Opus (default), AAC, raw; `.desktop/.both/.remote` output modes; mic forwarding.
- Map every mirroring-related `DeviceSettings` field to server args or client behaviour; expose them in a settings UI.
- Keep the phone clean: every teardown path (including tests) kills this session's server (`pkill -f "scid=<%08x>"`, so other native/external sessions and the detached `CleanUp` process survive) and removes the forward.
- Pure, `Sendable`, golden-byte-tested protocol code in `SefirahCore`; AppKit/AV glue in the app target.

**Non-goals (v1)**
- AV1/VP8/VP9 decoding (AV1 only offered when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`; not tested in v1).
- Camera source, gamepads, UHID mouse (relative-mouse mode), OTG mode, recording, screenshots.
- `adb reverse` tunnel (forward-only; reverse fails over Wi-Fi ADB anyway).
- `videoBuffer` jitter buffering (frames display immediately; a timebase mode is a Stage 3 stretch).
- Unlock-before-launch commands (Stage 3 small hook, not blocking).

## Background (current state)

- `SefirahCore/Features/Mirroring/Adb.swift`: `AdbClient` (value type, `Sendable`) over the `CommandRunning` seam (`ProcessCommandRunner`, fakes in tests), `AdbError`, `AdbOutput` parsers, `ScrcpyDeviceSelection`. Only `tcpip` threads `-s serial` today.
- `BundledTools.swift`: locates `Contents/MacOS/{scrcpy,adb}` and `Contents/Resources/scrcpy/scrcpy-server`; returns `nil` unless all three exist.
- `ScrcpyLaunchPlan.swift`, `ScrcpyProcessRunner.swift` (`ScrcpyRunning` protocol: `launch(_:key:onExit:)`, `terminate(key:)`, `terminateAll()`, `runningKeys`), `ScrcpyDiagnostics.swift`, `SefirahCore/Features/ScrcpyArguments.swift` (DeviceSettings → scrcpy CLI flags; `videoCodec`/`audioCodec`/`displayOrientation`/`rotationAngle` unused).
- `Sefirah/AppModel.swift`: `mirroringKeys`, `pendingMirrorKeys`, `toolFailure`, `bundledTools`/`scrcpyRunner`/`commandRunner` injection points (:45-47), `launchScrcpyAsync` (:278-344), `stopMirroring` (:363), `isMirroring/isMirrorPending/canMirror` (:371-381), `handleURL` (:487), `willTerminateNotification` observer calling `terminateAll()` (:136-139), device `.disconnected` handler (:513).
- UI: `Sefirah/Main/MainSplitView.swift` (`private enum MainTab { calls, messages, apps, settings }` at :49), `Sefirah/Device/DeviceRailView.swift` (Mirror button :38-49), `Sefirah/Apps/AppsView.swift` (Launch :26-27), `Sefirah/Settings/SettingsView.swift` (Screen mirroring section :26-50), `Sefirah/SefirahApp.swift` (`Window("Sefirah", id:"main")`, `Window("Incoming Call", id:"call")`), `RootView.swift` (`.alert(item: $model.toolFailure)`).
- Settings: `SefirahCore/Settings/DeviceSettings.swift` (fields listed in §Settings mapping), `GeneralSettings.swift` (`startupOption, theme, scrcpyPath, adbPath, …`), `SettingsStore` (JSON files, `NSLock`).
- Conventions: no actors exist yet; shared state is `final class … @unchecked Sendable` + `NSLock`; `AppModel` is the only `@MainActor` type; background → main via `Task { @MainActor in … }`. Tests: hand-rolled fakes (`FakeCommandRunner` in `AdbClientTests.swift`), pure-function goldens.
- Vendored: `Vendor/scrcpy/{scrcpy,adb,scrcpy-server,VERSION}`, `scripts/scrcpy.lock` (`SCRCPY_VERSION=4.1`), pre-build check in `project.yml`. Design doc for Option A: `docs/design/bundle-scrcpy.md`.
- Verified in this session on the Xiaomi 14 Ultra (`192.168.0.103:5555`): `adb forward tcp:0 localabstract:NAME` prints the assigned port on stdout as `62990\n`; `forward --list` shows `192.168.0.103:5555 tcp:62990 localabstract:NAME`; no scrcpy processes are left on the phone.

## Protocol summary (scrcpy 4.1, implementation-grade)

All integers big-endian. Source refs: `S/` = `server/src/main/java/com/genymobile/scrcpy/`, `A/` = `app/src/` in the v4.1 checkout at `scratchpad/scrcpy-src`.

### Server launch

```
adb -s <serial> push <bundled scrcpy-server> /data/local/tmp/scrcpy-server.jar
adb -s <serial> forward tcp:0 localabstract:scrcpy_<scid %08x>          → stdout "<port>\n"
adb -s <serial> shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 4.1 key=value ...
```
- `args[0]` must equal `"4.1"` (`S/Options.java:328-332`), else the server exits 1 with `[server] ERROR: The server version (4.1) does not match the client (...)`.
- Every other arg is `key=value`; unknown keys warn only. Values pass through the device `sh`: reject any value containing one of `" ;'\"*$?&`#\\|<>[]{}()!~\r\n"` (space, `;`, `'`, `"`, `*`, `$`, `?`, `&`, backtick, `#`, `\`, `|`, `<`, `>`, `[`, `]`, `{`, `}`, `(`, `)`, `!`, `~`, CR, LF) (`A/server.c:193-206`).
- Server log lines: `[server] LEVEL: message` on stdout/stderr; first INFO line is `Device: [<manuf>] <brand> <model> (Android <release>)`. Exit status 1 on any Throwable. The server unlinks the jar on exit (`cleanup=true`), so push before every launch.

Server options emitted by Sefirah (server default in parentheses; only non-defaults are sent):

| key | format | default | notes |
|---|---|---|---|
| `scid` | hex, 31-bit, `%08x` | -1 | socket `scrcpy_%08x` |
| `log_level` | `verbose\|debug\|info\|warn\|error` | debug | send `info` |
| `tunnel_forward` | bool | false | always `true` here |
| `video`, `audio`, `control` | bool | true | |
| `video_codec` | `h264\|h265\|av1` | h264 | |
| `audio_codec` | `opus\|aac\|raw` | opus | (`flac` exists; not offered) |
| `audio_source` | `output\|mic\|playback\|…` | output | `playback` needs Android ≥13 |
| `audio_dup` | bool | false | with `audio_source=playback` |
| `max_size` | int px | 0 | larger dimension, aligned down |
| `video_bit_rate`, `audio_bit_rate` | int bps | 8000000, 128000 | |
| `max_fps` | float | 0 | |
| `angle` | float deg | 0 | |
| `crop` | `w:h:x:y` | none | rejected with flex display |
| `display_id` | int | 0 | must be 0 when `new_display` set |
| `clipboard_autosync` | bool | true | |
| `new_display` | `""`, `WxH`, `WxH/dpi`, `/dpi` | none | Android ≥10 |
| `flex_display` | bool | false | enables RESIZE_DISPLAY |
| `keep_active` | bool | false | |
| `capture_orientation` | `[@][0\|90\|180\|270\|flip0…]` | unlocked 0 | v1: unused (open question) |
| `power_on` | bool | true | |
| `stay_awake`, `show_touches`, `screen_off_timeout`(ms), `power_off_on_close` | | | via `customArguments` only |

### Socket setup (forward mode)

1. Client connects TCP to `127.0.0.1:<port>` → adb forwards to `localabstract:scrcpy_<scid>`. adb accepts the TCP connection even when nothing listens on the device; the server writes **one dummy byte `0x00` on the first enabled socket immediately after accepting it** (`S/device/DesktopConnection.java:66-72`). Client: read 1 byte; on EOF/reset close, wait 100 ms, reconnect; ≤100 attempts.
2. Client then connects the remaining enabled sockets in order **video, audio, control** (no dummy byte on them). The server `accept()`s them sequentially.
3. **Only after all sockets are accepted** does the server write the 64-byte device meta on the first enabled socket (`S/Server.java:105-108`). Therefore: connect all sockets first, then read the name — never in between.
4. `TCP_NODELAY` on the control socket. Remove the forward (`adb forward --remove tcp:<port>`) once all sockets are up.

Device meta: 64 bytes, UTF-8 `Build.MODEL` NUL-padded (force `buf[63]=0`). Observed: `24031PN0DC`.

### Stream headers

First 4 bytes of the video socket and of the audio socket: `u32 codec_id`.

| stream | id | hex |
|---|---|---|
| h264 | `"h264"` | `0x68323634` |
| h265 | `"h265"` | `0x68323635` |
| av1 | `"\0av1"` | `0x00617631` |
| vp8 / vp9 | | `0x00767038` / `0x00767039` (never offered) |
| opus | `"opus"` | `0x6f707573` |
| aac | `"\0aac"` | `0x00616163` |
| flac | `"flac"` | `0x666c6163` (unsupported) |
| raw | `"\0raw"` | `0x00726177` |
| **disabled** | | `0x00000000` — audio only: device cannot capture (Android <11, playback on <13, capture failure); continue without audio |
| **config error** | | `0x00000001` — fatal |

### Video session packet (video only; first packet after the codec id, and on every encoder reset)

| off | size | value |
|---|---|---|
| 0 | u32 | flags: bit31 (byte0 & 0x80) = session marker; bit0 (byte3 & 0x01) = `client_resized` |
| 4 | u32 | width |
| 8 | u32 | height |

Observed: `80 00 00 00 | 00 00 02 40 | 00 00 05 00` (576×1280 for `max_size=1280`). Fail if the first 12-byte header is not a session packet or has 0 width/height. Any later 12-byte header with `byte0 & 0x80` is a session packet; a config packet follows.

### Media packet header (video and audio, 12 bytes)

| off | size | value |
|---|---|---|
| 0 | u64 | `pts_and_flags`: bit63 = 0 for media (1 = session, video only); bit62 = CONFIG; bit61 = KEY_FRAME; bits0–60 = PTS µs (`SystemClock`-based, not zero-based). Config packets: exactly `1<<62`. |
| 8 | u32 | payload size (>0) |
| 12 | … | payload |

(`S/device/Streamer.java:17-19,107-124`; `A/demuxer.c:14-17,127-137`.)

Config payloads: H.264 = Annex-B SPS+PPS (`00000001 67…`, `00000001 68…`); H.265 = Annex-B VPS+SPS+PPS (`…40 01…`, `…42 01…`, `…44 01…`); media packets are Annex-B access units (no B-frames; keyframes flagged by bit61). Opus config = 19-byte `OpusHead` (`"OpusHead" 01 02 <preskip u16le> <48000 u32le> <gain i16le> 00`); AAC config = 2-byte AudioSpecificConfig `11 90` (AAC-LC 48 kHz stereo); media = raw AAC access units, no ADTS; raw = no config, packets of s16le stereo 48 kHz, ≤4096 bytes (1024 frames). Audio is always 48 kHz stereo.

### Control messages (client → server; 1-byte type + payload, no length framing)

| id | name | payload after type | total |
|---|---|---|---|
| 0 | INJECT_KEYCODE | `u8 action` (0 down/1 up), `i32 keycode`, `u32 repeat`, `i32 metastate` | 14 |
| 1 | INJECT_TEXT | `u32 len` + UTF-8 (≤300 bytes) | 5+len |
| 2 | INJECT_TOUCH_EVENT | `u8 action`, `u64 pointer_id`, `i32 x`, `i32 y`, `u16 screen_w`, `u16 screen_h`, `u16 pressure` (u16fp), `i32 action_button`, `i32 buttons` | 32 |
| 3 | INJECT_SCROLL_EVENT | `i32 x`, `i32 y`, `u16 screen_w`, `u16 screen_h`, `i16 hscroll`, `i16 vscroll` (i16fp of value/16), `i32 buttons` | 21 |
| 4 | BACK_OR_SCREEN_ON | `u8 action` | 2 |
| 5 / 6 / 7 | EXPAND_NOTIFICATION_PANEL / EXPAND_SETTINGS_PANEL / COLLAPSE_PANELS | – | 1 |
| 8 | GET_CLIPBOARD | `u8 copy_key` (0 none, 1 copy, 2 cut) | 2 |
| 9 | SET_CLIPBOARD | `u64 sequence`, `u8 paste`, `u32 len` + UTF-8 (≤262130 bytes) | 14+len |
| 10 | SET_DISPLAY_POWER | `u8 on` | 2 |
| 11 | ROTATE_DEVICE | – | 1 |
| 12 | UHID_CREATE | `u16 id`, `u16 vendor_id`, `u16 product_id`, `u8 name_len` + name, `u16 desc_len` + descriptor | var |
| 13 | UHID_INPUT | `u16 id`, `u16 size` + data | 5+size |
| 14 | UHID_DESTROY | `u16 id` | 3 |
| 15 | OPEN_HARD_KEYBOARD_SETTINGS | – | 1 |
| 16 | START_APP | `u8 len` + name (≤255; optional leading `+` = force-stop, then optional `?` = label prefix search) | 2+len |
| 17 | RESET_VIDEO | – | 1 |
| 18 / 19 / 20 | CAMERA_* | camera only — never send | |
| 21 | RESIZE_DISPLAY | `u16 width`, `u16 height` (only with `new_display` + `flex_display=true`) | 5 |
| 22 | SCAN_FILE | `u32 len` + path | 5+len |

Fixed point: `pressure u16 = f == 1.0 ? 0xffff : UInt16(f * 65536)`; server decodes `0xffff → 1.0`. Scroll: caller value in `[-16, 16]` notches; encode `n = clamp(v/16, -1, 1)`, `i16 = n == 1.0 ? 0x7fff : Int16(n * 32768)`; server multiplies back by 16 (`A/control_msg.c:130-136`, `S/control/ControlMessageReader.java:123-125`).

Pointer ids: `0xFFFFFFFFFFFFFFFF` MOUSE, `…FFFE` GENERIC_FINGER, `…FFFD` VIRTUAL_FINGER. Touch semantics (`S/control/Controller.java:512-621`): `x,y` in video-frame pixels; `screen_w/h` must equal the server's current video size or the event is silently dropped. With pointer MOUSE: `action == HOVER_MOVE(7)` or any button other than PRIMARY → injected as a mouse; otherwise a finger touch (buttons forced 0). Client fills `action_button` = button that changed, `buttons` = held mask; motion `action = MOVE(2)` if a button is held else `HOVER_MOVE(7)`; DOWN pressure 1.0, UP 0.0.

Motion actions: DOWN 0, UP 1, MOVE 2, CANCEL 3, HOVER_MOVE 7. Key actions: DOWN 0, UP 1. Buttons: PRIMARY 1, SECONDARY 2, TERTIARY 4, BACK 8, FORWARD 16. Metastate: SHIFT_ON 0x1, ALT_ON 0x2, SYM_ON 0x4, ALT_LEFT 0x10, ALT_RIGHT 0x20, SHIFT_LEFT 0x40, SHIFT_RIGHT 0x80, CTRL_ON 0x1000, CTRL_LEFT 0x2000, CTRL_RIGHT 0x4000, META_ON 0x10000, META_LEFT 0x20000, META_RIGHT 0x40000, CAPS_LOCK 0x100000, NUM_LOCK 0x200000, SCROLL_LOCK 0x400000.

Android keycodes used: HOME 3, BACK 4, `0–9` 7–16, DPAD_UP/DOWN/LEFT/RIGHT 19–22, VOLUME_UP 24, VOLUME_DOWN 25, POWER 26, `A–Z` 29–54, COMMA 55, PERIOD 56, ALT_LEFT 57, ALT_RIGHT 58, SHIFT_LEFT 59, SHIFT_RIGHT 60, TAB 61, SPACE 62, ENTER 66, DEL 67, GRAVE 68, MINUS 69, EQUALS 70, LEFT_BRACKET 71, RIGHT_BRACKET 72, BACKSLASH 73, SEMICOLON 74, APOSTROPHE 75, SLASH 76, MENU 82, PAGE_UP 92, PAGE_DOWN 93, ESCAPE 111, FORWARD_DEL 112, CTRL_LEFT 113, CTRL_RIGHT 114, CAPS_LOCK 115, META_LEFT 117, META_RIGHT 118, MOVE_HOME 122, MOVE_END 123, INSERT 124, F1–F12 131–142, NUM_LOCK 143, NUMPAD_0–9 144–153, NUMPAD_DIVIDE 154, MULTIPLY 155, SUBTRACT 156, ADD 157, DOT 158, NUMPAD_ENTER 160, NUMPAD_EQUALS 161, VOLUME_MUTE 164, APP_SWITCH 187, CUT 277, COPY 278, PASTE 279, ALL_APPS 284.

### Device messages (server → client)

| id | name | payload |
|---|---|---|
| 0 | CLIPBOARD | `u32 len` + UTF-8 |
| 1 | ACK_CLIPBOARD | `u64 sequence` |
| 2 | UHID_OUTPUT | `u16 id`, `u16 size` + data (keyboard LEDs: bit0 NumLock, bit1 CapsLock) |

### UHID keyboard

Id 1, vendor 0, product 0, empty name (server substitutes "scrcpy"). Descriptor (67 bytes):
```
05 01 09 06 A1 01 05 07 19 E0 29 E7 15 00 25 01 75 01 95 08 81 02 75 08 95 01 81 01
05 08 19 01 29 05 75 01 95 05 91 02 75 03 95 01 91 01 05 07 19 00 29 65 15 00 25 65
75 08 95 06 81 00 C0
```
Input report 8 bytes `[mods][00][k1..k6]`; mods: LCtrl 0x01, LShift 0x02, LAlt 0x04, LGui 0x08, RCtrl 0x10, RShift 0x20, RAlt 0x40, RGui 0x80; keys = USB HID usage-page-7 ids; >6 keys → six bytes of 0x01 (phantom). No repeats (Android generates them).

### Golden bytes (unit-test fixtures)

- Touch DOWN at (100,200), frame 576×1280, left button: `02 00 ffffffffffffffff 00000064 000000c8 0240 0500 ffff 00000001 00000001`
- Touch UP same point: `02 01 ffffffffffffffff 00000064 000000c8 0240 0500 0000 00000001 00000000`
- Scroll at (100,200), vscroll +1 notch: `03 00000064 000000c8 0240 0500 0000 0800 00000000`; vscroll −1 → `f800`; +16 → `7fff`; −16 → `8000`
- Keycode HOME down, no meta: `00 00 00000003 00000000 00000000`
- Text "hi": `01 00000002 6869`
- Set clipboard seq 1, no paste, "a": `09 0000000000000001 00 00000001 61`
- Display power off: `0a 00`; back-or-screen-on down: `04 00`; reset video: `11`; start app "com.x": `10 05 636f6d2e78`; resize 800×600: `15 0320 0258`; get clipboard (copy): `08 01`
- UHID create kbd: `0c 0001 0000 0000 00 0043` + 67-byte descriptor; UHID input: `0d 0001 0008` + 8 bytes
- Device: clipboard "hi": `00 00000002 6869`; ack: `01 0000000000000001`; uhid output: `02 0001 0001 03`
- Video: `68323634 | 80000000 00000240 00000500 | 40000000 00000000 0000001a <26 B config> | 20000000 0001e240 0000000n <frame>`; H.264 config observed on the Xiaomi begins `00000001 67 64 00 20 …` / `00000001 68 ee 06 f2 c0`.
- Audio: `6f707573 | 40000000 00000000 00000013 "OpusHead" 01 02 …` then packets; Opus silence packet `fc ff fe` → 960 PCM frames (840 after the 120-frame pre-skip on the first packet).

## Architecture & module layout

```
SefirahCore/Features/Mirroring/
  Adb.swift                        (+ push / forward / forwardRemove / shell helpers, all with -s serial)
  BundledTools.swift               (+ NativeTools: adb + scrcpy-server only)
  ScrcpyLaunchPlan.swift, ScrcpyProcessRunner.swift, ScrcpyDiagnostics.swift   (unchanged; external fallback)
  Native/
    ServerOptions.swift            struct ServerOptions, ServerOptionsBuilder, StartupAction, validate()
    ServerLauncher.swift           push / forward / spawn app_process / killServer; ServerProcess (log tail)
    ByteStream.swift               protocol ByteStream + NWByteStream (NWConnection, readExactly)
    MirrorSession.swift            actor: lifecycle, task group, teardown
    MirrorEvent.swift              MirrorEvent, MirrorState, MirrorError, MirrorStage
    Video/
      MediaPacket.swift            StreamCodecID, MediaPacketHeader.parse, SessionHeader.parse (pure)
      AnnexB.swift                 nalUnits, parameterSets, toAVCC (pure)
      VideoFormat.swift            CMFormatDescription from parameter sets; AV1 capability check
      SampleBufferFactory.swift    CMSampleBuffer (pts µs, DisplayImmediately)
      VideoFrameSink.swift         protocol + DisplayLayerSink (AVSampleBufferVideoRenderer)
    Audio/
      AudioDecoder.swift           AVAudioConverter (opus/aac) / passthrough (raw) → Float32 PCM
      AudioPlayer.swift            AVAudioEngine + AVAudioSourceNode + ring buffer; AudioSink protocol
    Control/
      ControlMessage.swift         enum + encode() (pure)
      DeviceMessage.swift          incremental parser (pure)
      ControlChannel.swift         final class: nonisolated send queue + writer/reader tasks
      AndroidInput.swift           actions, buttons, MetaState, AndroidKeycode
      MacKeyMap.swift              kVK → keycode / HID usage; modifier → metastate; inject decision
      HidKeyboard.swift            descriptor + report builder (pure)
      PointerMapper.swift          view point ↔ frame pixels (pure)
    MirrorDiagnostics.swift        MirrorError → user hint
Sefirah/Mirror/
  MirrorView.swift                 tab body: empty / preparing / streaming / failed states, banners
  MirrorToolbar.swift
  MirrorSurfaceView.swift          NSViewRepresentable
  MirrorNSView.swift               AVSampleBufferDisplayLayer backing layer + NSEvent capture
  MirrorController.swift           @MainActor @Observable per-session VM; input handler; reconnect policy
  MirrorSettingsView.swift         (Stage 3)
SefirahCoreTests/Native/…          (see Tests)
docs/design/native-mirror.md      this document
```

`project.yml`: no target changes (directory globs pick the files up). Frameworks are auto-linked by `import` (AVFoundation, CoreMedia, VideoToolbox, AudioToolbox, Network, AppKit, Carbon.HIToolbox). `SefirahCore` already imports AppKit (`ClipboardApply.swift`), so `NSEvent.ModifierFlags` in `MacKeyMap` is fine. Optional: add `SEFIRAH_TEST_ADB_SERIAL` pass-through to the test scheme's environment for the integration test.

**Concurrency model (Swift 6 strict)**
- `MirrorSession` is an `actor` (first in the codebase; sanctioned by the Option A doc). Reader tasks are children of a `withThrowingTaskGroup` inside `start()`, so cancellation is structured.
- Non-`Sendable` AV/CM objects (`CMSampleBuffer`, `CMFormatDescription`, `AVAudioConverter`, `AVAudioPCMBuffer`) never cross an isolation boundary: they are created and consumed on the same task and handed to sinks through nonisolated synchronous protocol methods (which inherit the caller's isolation — legal). Sinks are `@unchecked Sendable` classes that hold only thread-safe objects (`AVSampleBufferVideoRenderer`, ring buffer + lock). Never `DispatchQueue.main.async { … enqueue(sb) }` — capturing a non-Sendable CM object in a `@Sendable` closure is a Swift 6 error.
- `ControlChannel.send` is nonisolated and lock-protected so the input path has no `await` (an `AsyncStream<Void>` with `.bufferingNewest(1)` wakes the writer task).
- Events reach the app through `@Sendable (MirrorEvent) -> Void` (same shape as `session.eventHandler`); `MirrorController` hops with `Task { @MainActor in … }`.
- `ServerProcess`, `NWByteStream`, `DisplayLayerSink`, `AudioPlayer`, `ControlChannel` follow the existing `final class … @unchecked Sendable` + `NSLock` style.

### Core types

```swift
public struct ServerOptions: Sendable, Equatable {
    public static let serverVersion = "4.1"                      // unit test: equals SCRCPY_VERSION in scripts/scrcpy.lock
    public static let remoteJarPath = "/data/local/tmp/scrcpy-server.jar"
    public enum VideoCodec: String, Sendable { case h264, h265, av1 }
    public enum AudioCodec: String, Sendable { case opus, aac, raw }
    public enum AudioSource: String, Sendable { case output, mic, playback }
    public var scid: UInt32                      // 31-bit
    public var logLevel = "info"
    public var video = true, audio = true, control = true
    public var videoCodec: VideoCodec = .h264
    public var audioCodec: AudioCodec = .opus
    public var audioSource: AudioSource = .output
    public var audioDup = false
    public var maxSize = 0, videoBitRate = 8_000_000, audioBitRate = 128_000, maxFps = 0
    public var angle = 0
    public var crop: String? = nil
    public var displayId = 0
    public var newDisplay: String? = nil
    public var flexDisplay = false, keepActive = false
    public var clipboardAutosync = true
    public var extra: [String: String] = [:]     // from customArguments, validated
    public var socketName: String { String(format: "scrcpy_%08x", scid) }
    /// ["4.1", "scid=0000abcd", "log_level=info", "tunnel_forward=true", <non-defaults in declaration order>, extra sorted by key]
    public func arguments() throws -> [String]
    public static func validate(_ value: String, key: String) throws   // forbidden-char set above
}
public enum ServerOptionsError: Error, Equatable, Sendable {
    case invalidValue(key: String, value: String), invalidBitrate(String), invalidCrop(String),
         invalidDisplayId(String), cropWithFlexDisplay, unsupportedCodec(String)
}
public enum StartupAction: Equatable, Sendable { case displayPower(on: Bool), uhidKeyboard, startApp(String) }
public enum ServerOptionsBuilder {
    public static func build(settings: DeviceSettings, package: String?, scid: UInt32, av1Supported: Bool) throws -> ServerOptions
    public static func startupActions(settings: DeviceSettings, package: String?) -> [StartupAction]
    public static func parseBitrate(_ s: String) -> Int?     // "8M"→8_000_000, "2000K"→2_000_000, "500000", case-insensitive
}
```

```swift
public protocol ByteStream: AnyObject, Sendable {
    func readExactly(_ n: Int) async throws -> Data          // throws StreamError.eof / .cancelled / .network(NWError)
    func write(_ data: Data) async throws
    func close()
}
public final class NWByteStream: ByteStream, @unchecked Sendable {
    public static func connect(port: UInt16, noDelay: Bool, timeout: TimeInterval) async throws -> NWByteStream
}
public protocol StreamConnecting: Sendable { func connect(port: UInt16, noDelay: Bool) async throws -> any ByteStream }
```

```swift
public protocol ServerProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    var logTail: String { get }                               // last 16 KiB of "[server] …" lines
    func terminate()
    func waitForExit(timeout: TimeInterval) async -> Int32?
}
public protocol DetachedProcessSpawning: Sendable {
    func spawn(_ executable: URL, _ arguments: [String], environment: [String: String],
               onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess
}
public struct ServerLauncher: Sendable {
    public var adb: AdbClient, serverJar: URL
    public var spawner: any DetachedProcessSpawning = ProcessDetachedSpawner()
    public func push(serial: String) async throws                                   // adb -s S push <jar> /data/local/tmp/scrcpy-server.jar (20 s)
    public func forward(serial: String, socketName: String) async throws -> UInt16  // adb -s S forward tcp:0 localabstract:<name>; parse first stdout line
    public func removeForward(serial: String, port: UInt16) async                   // best-effort
    public func spawn(serial: String, options: ServerOptions, onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess
    public func killServer(serial: String, scid: UInt32) async                      // adb -s S shell pkill -f "scid=%08x" (3 s, best-effort; only this session's server)
}
```
Spawn argv (exact): `adb -s <serial> shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 4.1 scid=… log_level=info tunnel_forward=true …` — each token a separate argv element; adb joins them on the device.

```swift
public enum MirrorStage: Sendable { case push, tunnel, spawn, dummyByte, deviceMeta, videoHeader, audioHeader }
public enum MirrorError: Error, Equatable, Sendable {
    case toolsMissing, adb(AdbError), serverSpawnFailed(String)
    case serverExited(code: Int32, log: String), versionMismatch(String)
    case handshakeTimeout(MirrorStage), protocolError(String)
    case unsupportedVideoCodec(UInt32), unsupportedAudioCodec(UInt32), videoConfigError, audioConfigError
    case decoderFailed(String), connectionLost, cancelled
}
public enum MirrorState: Equatable, Sendable { case idle, preparing(MirrorStage), connecting, streaming, stopping, failed(MirrorError) }
public enum MirrorEvent: Sendable {
    case state(MirrorState), deviceName(String)
    case videoSize(width: Int, height: Int, clientResized: Bool)
    case audioUnavailable, clipboard(String), clipboardAck(UInt64), uhidOutput(id: UInt16, data: Data)
    case serverLog(String), warning(String)
}
public struct MirrorSessionConfig: Sendable {
    public var key: String, serial: String
    public var options: ServerOptions, actions: [StartupAction]
    public var audioTargetLatencyMs: Int              // DeviceSettings.audioBuffer (default 50)
}
public actor MirrorSession {
    public init(config: MirrorSessionConfig, launcher: ServerLauncher, connector: any StreamConnecting,
                videoSink: any VideoFrameSink, audioSink: (any AudioSink)?, events: @escaping @Sendable (MirrorEvent) -> Void)
    public func start() async                           // returns when streaming ends (stopped or failed); never throws
    public func stop() async                            // idempotent; bounded ≈2 s
    public nonisolated func emergencyStop()             // synchronous: close sockets, terminate adb shell process (app quit)
    public nonisolated let control: ControlChannel      // send() without await
    public nonisolated var currentVideoSize: (Int, Int)? { get }   // lock-protected copy for input stamping
}
```

## Session lifecycle

```
start()
 1  .preparing(.push)     launcher.push(serial)                                   → .adb
 2  .preparing(.tunnel)   scid = UInt32.random & 0x7fff_ffff; port = launcher.forward(serial, socketName)   → .adb
 3  .preparing(.spawn)    proc = launcher.spawn(serial, options, onLine:)         → .serverSpawnFailed
                          onLine: append to tail; "[server] ERROR:" → remember last error;
                          "does not match the client" → mark versionMismatch
 4  .connecting
    a  first = connector.connect(port); read 1 byte (dummy). On EOF/reset: close, sleep 100 ms, reconnect.
       ≤100 attempts and ≤10 s total; before each attempt, if !proc.isRunning → .serverExited(code, tail)
       (or .versionMismatch if flagged). Timeout → .handshakeTimeout(.dummyByte)
    b  for each remaining enabled stream in order video, audio, control: connect(port) (no dummy byte)
       control: noDelay = true
    c  launcher.removeForward(serial, port)                 (best-effort, tunnel no longer needed)
    d  name = first.readExactly(64) (5 s) → trim at first NUL → event .deviceName   → .handshakeTimeout(.deviceMeta)
 5  .streaming — withThrowingTaskGroup:
       runVideo(videoStream)            (if options.video)
       runAudio(audioStream)            (if options.audio)
       control.run(controlStream)       (writer + reader; if options.control)
       monitorProcess()                 (proc exits → throw .serverExited unless stopping)
    after control writer is live, enqueue StartupActions in order:
       .displayPower(false) → setDisplayPower(on: false); .uhidKeyboard → uhidCreate(id 1 …); .startApp(p) → startApp(p)
    first thrown error wins → cancel group → state .failed(error) (or .idle when cancelled by stop())
 6  teardown (always, also on failure):
       close all streams (server exits on EPIPE; its CleanUp restores show_touches/stay_awake/display power)
       proc.waitForExit(1 s) ?? proc.terminate()
       launcher.killServer(serial, scid) (always; 3 s; kills only this session's server)
       launcher.removeForward if still registered
       videoSink.flush(); audioSink?.stop()
```

Notes
- If `video=false`, the "first enabled stream" is audio (or control): the dummy byte and device name are read from it. The session code is written in terms of `firstEnabled`, not `video`.
- Post-`streaming` EOF on any socket → `.connectionLost` (shown as "Device disconnected", not an alert). `MirrorController` auto-retries once after 1 s if the device is still online; never on `.versionMismatch`, `.toolsMissing`, `.unsupportedVideoCodec`, `.videoConfigError`, `.serverSpawnFailed`.
- App quit: `AppModel` calls `emergencyStop()` on every session from the existing `willTerminateNotification` observer (`AppModel.swift:136-139`) — synchronous, no adb round-trip needed because the server dies on broken pipe.
- Sefirah's own `.disconnected` peer event does not stop mirrors (ADB is a separate transport).

## Video pipeline

`runVideo`:
1. `codec = u32` → `StreamCodecID`; `.disabled`/`.configError` → `.videoConfigError`; `.av1` only if `VideoFormat.av1Supported`; vp8/vp9/other → `.unsupportedVideoCodec(raw)`. Timeout 5 s → `.handshakeTimeout(.videoHeader)`.
2. First header (12 bytes) must be a session packet with non-zero size, else `.protocolError`. Emit `.videoSize`.
3. Loop `header = readExactly(12)`:
   - `byte0 & 0x80` → `SessionHeader.parse` → store `currentVideoSize`, `needsKeyFrame = true`, emit `.videoSize` (this also reports `clientResized` for flex).
   - else `MediaPacketHeader.parse` → `payload = readExactly(size)` (size 0 → `.protocolError`).
   - CONFIG: `AnnexB.parameterSets(payload, codec)` → `VideoFormat.make(sets, codec)` (`CMVideoFormatDescriptionCreateFromH264ParameterSets` / `…FromHEVCParameterSets`, `nalUnitHeaderLength: 4`) → `sink.formatChanged(fd, w, h)` (renderer `flush()`, keep last image so rotation doesn't blank); `needsKeyFrame = true`.
   - MEDIA: if `needsKeyFrame && !keyFrame` → drop (count; after 30 consecutive drops send `resetVideo`, rate-limited 1/s); else `AnnexB.toAVCC(payload)` (4-byte BE length per NAL; pass all NALs through — VT tolerates in-band SPS/PPS/SEI/AUD) → `SampleBufferFactory.make(avcc, fd, ptsMicros, keyFrame)` → `sink.enqueue(sb)`; `needsKeyFrame = false`.
   - After each enqueue: `if sink.requiresFlush { sink.flush(); needsKeyFrame = true; send(.resetVideo) }`; `if let e = sink.failure { throw .decoderFailed(e) }`.

`SampleBufferFactory.make`: `CMBlockBufferCreateWithMemoryBlock` backed by the `Data` via a custom deallocator (single copy in `toAVCC`), `CMSampleTimingInfo(duration: .invalid, pts: CMTime(value: Int64(pts), timescale: 1_000_000), dts: .invalid)`, `CMSampleBufferCreateReady`, attachment `kCMSampleAttachmentKey_DisplayImmediately = true` (no timebase; lowest latency; no B-frames so decode order = display order); `kCMSampleAttachmentKey_NotSync = true` for non-keyframes.

`DisplayLayerSink` (`@unchecked Sendable`): holds `AVSampleBufferVideoRenderer` (`layer.sampleBufferRenderer`, macOS 14; `enqueue` is thread-safe), `formatChanged` → `renderer.flush()`, `enqueue` → if `!renderer.isReadyForMoreMediaData` and the sample is not a keyframe drop it, else `renderer.enqueue(sb)`; `requiresFlush` = `renderer.requiresFlushToResumeDecoding`; `failure` = `renderer.status == .failed ? renderer.error : nil`. Also flush + `resetVideo` on `NSApplication.didBecomeActiveNotification` (controller side).

`MirrorNSView`: `wantsLayer = true`, `makeBackingLayer()` returns `AVSampleBufferDisplayLayer` (`videoGravity = .resizeAspect`, black background), `viewDidChangeBackingProperties` sets `contentsScale`, `layerContentsRedrawPolicy = .never`. SwiftUI wraps it with `.aspectRatio(CGFloat(w)/CGFloat(h), contentMode: .fit)` from `.videoSize` so the letterbox math in `PointerMapper` is exact.

AV1 (behind `av1Supported`): format via `CMVideoFormatDescriptionCreate(codecType: kCMVideoCodecType_AV1, extensions: [SampleDescriptionExtensionAtoms: ["av1C": csd0]])`, media packets passed as-is (OBU temporal units). Untested in v1; the settings picker hides AV1 when unsupported.

## Control / input pipeline

`ControlChannel` (`final class`, `@unchecked Sendable`): `send(_ m: ControlMessage)` nonisolated — lock, append to queue (cap 64: when full drop the oldest droppable message; `resizeDisplay` replaces a pending `resizeDisplay`), wake writer. `run(stream:)` starts the writer (`for await _ in wake { drain; try await stream.write(m.encode()) }`) and the reader (`readExactly(1)` type byte → per-type fixed reads / `u32 len` + payload; `DeviceMessage` parsing is exposed as a pure incremental `parse(buffer) -> (DeviceMessage, consumed)?` for tests). Reader delivers `.clipboard/.clipboardAck/.uhidOutput` events. `uhidCreate`/`uhidDestroy` are never dropped.

`MirrorNSView` (AppKit) captures events and forwards raw facts to `MirrorController.input` (`@MainActor`), which uses the pure mappers and calls `session.control.send` (no await):

- **Focus**: `acceptsFirstResponder = true`, `acceptsFirstMouse = true`, `NSTrackingArea(.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited)`.
- **Pointer mapping** (`PointerMapper(viewSize:videoSize:)`): flip y (`bounds.height - p.y`), `scale = min(viewW/videoW, viewH/videoH)`, rect centred; `toFrame(p) -> (Int32, Int32)?` (nil outside the video rect; a drag that started inside is clamped instead). Every touch/scroll is stamped with `session.currentVideoSize` as `screen_w/h`; events while it is nil, or a drag spanning a size change, are dropped/cancelled (the server drops mismatched sizes silently).
- **Mouse**: left `mouseDown/Dragged/Up` → `injectTouch(action .down/.move/.up, pointerId MOUSE, pressure 1.0/1.0/0.0, actionButton PRIMARY on down/up else 0, buttons held mask)` — with only PRIMARY the server injects a finger touch. Right button → `backOrScreenOn(.down/.up)` (scrcpy default). Middle → `injectKeycode(HOME)`. `mouseMoved` → `HOVER_MOVE` with buttons 0 only when the `forwardHover` toggle is on (default off). ⌥+left-drag → virtual-finger pinch (`pointerId VIRTUAL_FINGER` mirrored through the frame centre) — Stage 2 stretch.
- **Scroll**: `scrollWheel` → `injectScroll(x, y, screen, hscroll, vscroll, buttons)`; precise deltas: `scrollingDelta / 10` (points → notches); line deltas: `deltaX/deltaY` as notches; clamp to ±16 (the encoder normalises by /16). Sign: pass macOS `deltaY` sign through (natural scrolling already inverts, matching scrcpy/SDL behaviour); a `Mirror.invertScroll` constant flips it if device testing proves otherwise.
- **Keyboard (SDK, default mixed mode)**: `keyDown/keyUp` → `MacKeyMap.decide(virtualKey:characters:flags:mode:)` → `.keycode(k)` → `injectKeycode(action, k, repeat, metaState)` (`repeat` increments on `isARepeat`), `.text(s)` → `injectText(s)` (UTF-8 chunked ≤300 bytes at character boundaries), `.ignore`. Mixed mode policy: navigation/function/modifier/space/enter/backspace/letters/digits with ⌘ or ⌃ held → keycode; printable characters without ⌘/⌃ → text (layout-independent, handles accents/IME). `flagsChanged` diffs modifier flags and sends the modifier keycode (`kVK_Command→META_LEFT`, `kVK_RightCommand→META_RIGHT`, `kVK_Option→ALT_LEFT`, `kVK_Control→CTRL_LEFT`, `kVK_Shift→SHIFT_LEFT`, right variants, `kVK_CapsLock→CAPS_LOCK`). Metastate: ⌘→`META_ON|META_LEFT`, ⌥→`ALT_ON|ALT_LEFT`, ⌃→`CTRL_ON|CTRL_LEFT`, ⇧→`SHIFT_ON|SHIFT_LEFT`, caps lock → `CAPS_LOCK`.
  `performKeyEquivalent`: ⌘V → `setClipboard(sequence: 0, paste: false, text: pasteboard)` then `injectKeycode(V, CTRL_ON|CTRL_LEFT)` down/up; ⌘⇧V → `injectText(pasteboard)`; ⌘C/⌘X → `getClipboard(copyKey: 1/2)`; ⌘A → V-style Ctrl+A; other ⌘ combos fall through to the menu.
  kVK table (subset, from `Carbon.HIToolbox`): letters `kVK_ANSI_A…Z` → A–Z; `kVK_ANSI_0…9` → 0–9; Return→ENTER, KeypadEnter→NUMPAD_ENTER, Escape→ESCAPE, Delete→DEL, ForwardDelete→FORWARD_DEL, Tab→TAB, Space→SPACE, Home/End→MOVE_HOME/MOVE_END, PageUp/PageDown→PAGE_UP/PAGE_DOWN, arrows→DPAD_*, Help→INSERT, F1–F12→131–142, Grave/Minus/Equal/LeftBracket/RightBracket/Backslash/Semicolon/Quote/Comma/Period/Slash→GRAVE/MINUS/EQUALS/LEFT_BRACKET/RIGHT_BRACKET/BACKSLASH/SEMICOLON/APOSTROPHE/COMMA/PERIOD/SLASH, Keypad0–9→NUMPAD_0–9, KeypadDivide/Multiply/Minus/Plus/Decimal/Equals→NUMPAD_DIVIDE/MULTIPLY/SUBTRACT/ADD/DOT/EQUALS, VolumeUp/VolumeDown/Mute→VOLUME_UP/DOWN/MUTE.
- **Physical keyboard (UHID)** when `physicalKeyboard`: startup `uhidCreate(id 1, vendor 0, product 0, name "", descriptor)`; on every key/modifier change send `uhidInput(id 1, HidKeyboard.report(mods, keys))`; never text, never repeats; `uhidOutput` LED byte updates the controller's caps/num indicator. HID usages: a–z 0x04–0x1d, 1–9 0x1e–0x26, 0 0x27, Enter 0x28, Esc 0x29, Backspace 0x2a, Tab 0x2b, Space 0x2c, `-` 0x2d, `=` 0x2e, `[` 0x2f, `]` 0x30, `\` 0x31, `;` 0x33, `'` 0x34, `` ` `` 0x35, `,` 0x36, `.` 0x37, `/` 0x38, CapsLock 0x39, F1–F12 0x3a–0x45, Insert 0x49, Home 0x4a, PgUp 0x4b, Delete 0x4c, End 0x4d, PgDn 0x4e, →←↓↑ 0x4f–0x52, NumLock 0x53, KP `/ * - +` 0x54–0x57, KP Enter 0x58, KP1–9 0x59–0x61, KP0 0x62, KP`.` 0x63, KP`=` 0x67.
- **Toolbar** → `injectKeycode` HOME/BACK/APP_SWITCH/POWER/VOLUME_UP/VOLUME_DOWN, `rotateDevice`, `expandNotificationPanel`, `setDisplayPower`, `resetVideo`. Menu-bar commands with ⌘-shortcuts (Stage 3).
- **Flex display**: `MirrorNSView.layout` → `controller.viewResized(pixels)` → debounced 100 ms → `resizeDisplay(w, h)` (surface size in backing pixels, larger side capped at `max_size` if set); the resulting session packet has `clientResized = 1` and updates the aspect ratio.
- **Clipboard**: `.clipboard(text)` → `NSPasteboard.general` when `deviceSettings.clipboardReceive`; toast if `showClipboardToast`.

## Audio pipeline

`runAudio`: `codec = u32` → `.disabled` → emit `.audioUnavailable`, return normally; `.configError` → `.audioConfigError`; `.flac`/unknown → `.unsupportedAudioCodec`. Then loop 12-byte headers: CONFIG → `decoder = AudioDecoder(codec, config)` (Opus: ignore `OpusHead`; AAC: ASC as `kAudioConverterDecompressionMagicCookie`; raw: none — raw has no config packet, create the passthrough decoder on the first media packet); MEDIA → `pcm = decoder.decode(packet)` → `audioSink.enqueue(pcm)`. PTS are ignored (arrival-paced).

`AudioDecoder` (`final class`, owned by the audio task): `AVAudioConverter(from: AVAudioFormat(streamDescription: &asbd), to: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))` with `asbd = {mFormatID: kAudioFormatOpus | kAudioFormatMPEG4AAC, mSampleRate: 48000, mChannelsPerFrame: 2, mFramesPerPacket: 960 | 1024}`; per packet an `AVAudioCompressedBuffer(packetCapacity: 1, maximumPacketSize: n)` with `packetDescriptions[0].mDataByteSize = n`, `convert(to:error:withInputFrom:)` producing ≤4096-frame PCM buffers. Verified in this session: `kAudioFormatOpus` is in `kAudioFormatProperty_DecodeFormatIDs`, converter creation succeeds, a silent packet decodes to 840 frames (960 − 120 pre-skip).

`AudioPlayer: AudioSink` (`@unchecked Sendable`): `AVAudioEngine` + `AVAudioSourceNode` rendering from a Float32 interleaved ring buffer guarded by `os_unfair_lock` (short critical sections). Target latency = `audioBuffer` ms (default 50). Drift control (scrcpy `audio_player.c` strategy, simplified): on enqueue, if buffered > 2×target drop the oldest samples down to target; on underrun output silence and mark "underrun" so the next enqueue refills to target/2 before resuming. Mute toggle drops decoded PCM but keeps draining the socket so the server never blocks.

## Settings mapping

`ServerOptionsBuilder.build(settings:package:scid:av1Supported:)` and `startupActions`:

| DeviceSettings | Result |
|---|---|
| `videoResolution` (Int string) | `maxSize` (empty/0 → unset) |
| `videoBitrate` ("8M", "2000K", bps); forced `16M` when `package != nil && flexDisplay` (parity with `ScrcpyArguments`) | `videoBitRate` via `parseBitrate`, else `invalidBitrate` |
| `frameRate > 0` | `maxFps` |
| `crop` non-empty (`^\d+:\d+:\d+:\d+$`) | `crop`; `cropWithFlexDisplay` if flex |
| `display` ≠ "0" and no virtual display | `displayId` (else `invalidDisplayId`) |
| `videoCodec` 0/1/2 | h264/h265/av1; av1 → `unsupportedCodec` unless `av1Supported` |
| `disableVideoForwarding` | `video = false` |
| `audioOutputMode` `.remote` / `.both` / `.desktop` | `audio = false` / `audioSource = .playback, audioDup = true` / default |
| `forwardMicrophone` | `audioSource = .mic` (overrides) |
| `audioBitrate` | `audioBitRate` via `parseBitrate` |
| `audioCodec` 0/1/2 | opus/aac/raw |
| `scrcpyClipboardAutosync` | `clipboardAutosync` |
| `package != nil && isVirtualDisplayEnabled` | `newDisplay = virtualDisplaySize.isEmpty ? "" : virtualDisplaySize`; `flexDisplay` → `flexDisplay = keepActive = true`; `displayId` forced 0 |
| `rotationAngle ≠ 0` | `angle` |
| `displayOrientation` | unused in v1 (open question: legacy semantics) |
| `customArguments` | whitespace-split tokens: `key=value` → `extra` (validated); tokens starting with `--` → `.warning("Ignored scrcpy CLI flag …")` |
| `screenOff` | `StartupAction.displayPower(on: false)` |
| `physicalKeyboard` | `StartupAction.uhidKeyboard` |
| `package` | `StartupAction.startApp(package)` (order: power, uhid, startApp) |
| `audioBuffer` | `MirrorSessionConfig.audioTargetLatencyMs` |
| `videoBuffer`, `audioOutputBuffer` | ignored in v1 (documented) |
| `unlockDeviceBeforeLaunch/unlockCommands` | Stage 3: run via `adb shell` before push |
| always | `scid`, `log_level=info` (`debug` when `GeneralSettings.verboseMirrorLogs`), `tunnel_forward=true` |

New settings: `GeneralSettings.mirrorBackend: MirrorBackend = .native` (`.native | .external`, decoded with `decodeIfPresent` so existing `general.json` loads), `GeneralSettings.verboseMirrorLogs = false`; `DeviceSettings.forwardHover = false` (same `decodeIfPresent` treatment). `ScrcpyArguments` gains the same codec-name mapping (`--video-codec`, `--audio-codec`) so both backends agree (Stage 3).

## UI

- `MainTab` moves to `AppModel.selectedTab` (internal enum, gains `.mirror`); `MainSplitView` picker adds `Text("Mirror").tag(MainTab.mirror)` after Apps and `case .mirror: MirrorView(model: model)`.
- `AppModel` additions: `var mirrors: [String: MirrorController]` (keyed like `mirroringKeys`: `deviceId` or `"deviceId:package"`), `func startMirror(package: String? = nil, appName: String? = nil)` (dispatches to native or `launchScrcpy` per `mirrorBackend`; native path: resolve serial exactly like `launchScrcpyAsync` — `tryConnectTcp` or `ScrcpyDeviceSelection` — then create the controller and switch `selectedTab = .mirror`), `func stopMirror(key:)`, `func stopAllMirrors()`; `isMirroring/isMirrorPending/canMirror` become unions over native controllers and the external runner (`canMirror` native requires `NativeTools.locate()` or a custom `adbPath`). `DeviceRailView` Mirror button and `AppsView` Launch call `startMirror`; `handleURL` routes to it too.
- `MirrorController` (`@MainActor @Observable`): owns one `MirrorSession`, `DisplayLayerSink`, `AudioPlayer`, input handler; publishes `state`, `deviceName`, `videoSize`, `banner`, `isMuted`, `lastLogTail`; implements the reconnect policy; hops events to main.
- `MirrorView` states: *Empty* (device icon, "Mirror <name>" button, "Launch an app…" → Apps tab, caption with codec/resolution, disabled with reason when `!canMirror`/offline) · *Preparing/Connecting* (spinner + stage text "Pushing server…", "Opening tunnel…", "Starting server…", "Connecting…", Cancel) · *Streaming* (toolbar: Back, Home, Recents, Rotate, Screen off, Mute, Notifications, Power, Stop; surface with `.aspectRatio(.fit)` on black; footer "H.265 · 576×1280 · 8 Mbps"; dismissible banners for `audioUnavailable`, warnings, and a static "Input not working?" popover explaining Xiaomi's *USB debugging (Security settings)* requirement) · *Failed* (title, `MirrorDiagnostics.hint`, Retry / "Use external scrcpy instead" / Copy log).
- Multiple sessions (device + per-app virtual display): a segmented selector at the top of the Mirror tab; the rail button stops the device-level session before starting a new one.
- Stage 3: `MirrorSettingsView` (backend, resolution, bitrate, fps, codec, crop, display id, audio mode/codec/bitrate/buffer, screen off, physical keyboard, clipboard autosync, hover, virtual display + size + flex, custom args) embedded in `SettingsView`'s Screen mirroring section; `Window("Mirror", id: "mirror")` pop-out hosting the same controller; menu commands.

## Error handling & UX

- `MirrorDiagnostics.hint(_ error: MirrorError) -> String?` extends `ScrcpyDiagnostics`: `.adb(.commandFailed)` with "unauthorized" → "Accept the USB debugging prompt on the phone"; "device offline"/"not found" → "Reconnect Wi-Fi ADB (Settings ▸ Restart ADB server)"; `.versionMismatch` → "Bundled scrcpy-server does not match — run scripts/fetch-scrcpy.sh"; `.serverExited` whose log contains "Could not find" → "adb shell is blocked on this device"; `.handshakeTimeout(.dummyByte)` → "Server did not start (see log)"; `.videoConfigError` → "Encoder failed — lower resolution/bitrate or switch codec"; `.connectionLost` → "Device disconnected".
- Injection denial (Xiaomi) is **not detectable** from server output at info level (`Device.injectEvent` returns false silently); the static help popover covers it.
- Server log tail (16 KiB) is retained on the controller for "Copy log"; `[server] ERROR` lines are surfaced as `.serverLog` events and shown in the footer while streaming.
- Errors before `streaming` use the Failed state (no modal alert); `toolFailure` alerts are reserved for settings-save failures as today.

## Tests

`SefirahCoreTests/Native/` (pure goldens unless noted):

| File | Covers |
|---|---|
| `ServerOptionsTests` | defaults → `["4.1","scid=0000abcd","log_level=info","tunnel_forward=true"]`; each DeviceSettings mapping row; `parseBitrate`; forbidden chars; crop+flex rejection; `display_id` dropped with `new_display`; av1 gating; customArguments `--` warning; `serverVersion == SCRCPY_VERSION` read from `scripts/scrcpy.lock` (path via `#filePath`); `startupActions` ordering |
| `ControlMessageTests` | all golden byte strings above; fixed-point edges (pressure 1.0→`ffff`, 0.5→`8000`; scroll ±1→`0800/f800`, ±16→`7fff/8000`); text chunking at 300 bytes on character boundaries; `isDroppable` |
| `DeviceMessageTests` | clipboard split across feeds, ack, uhidOutput, unknown type → error, oversize rejection |
| `MediaPacketTests` | session header (flag, `client_resized`), config `1<<62`, keyframe bit61, pts mask, zero size, codec ids, first-packet-not-session |
| `AnnexBTests` | 3-/4-byte start codes, SPS/PPS extraction from the Xiaomi config bytes, HEVC VPS/SPS/PPS (`40 01/42 01/44 01`), `toAVCC` golden |
| `VideoFormatTests` | real `CMFormatDescription` from captured SPS/PPS and HEVC sets; dimensions 576×1280 |
| `SampleBufferFactoryTests` | pts µs, DisplayImmediately/NotSync attachments, block buffer length |
| `AudioDecoderTests` | Opus `fc ff fe` → 840/960 frames; AAC converter with cookie `11 90` initialises; raw 4096 B → 1024 frames |
| `PointerMapperTests` | portrait video in landscape view, y-flip, outside → nil, clamp |
| `MacKeyMapTests` / `HidKeyboardTests` | kVK spot checks, metastate bits, mixed-mode decisions (`a`→keycode, `é`→text, ⌘V handled), descriptor 67 B, phantom fill |
| `ServerLauncherTests` | `FakeCommandRunner`: push argv, forward `tcp:0` → parse `"62990\n"`, spawn argv exact, push failure → `.adb`, `killServer` argv, `removeForward` |
| `ControlChannelTests` | `MemoryByteStream`: queue drop policy keeps `uhidCreate`, resize coalescing, reader dispatch |
| `MirrorSessionTests` | fake launcher/spawner/connector with scripted streams: dummy-byte EOF → reconnect; full handshake (dummy, [connect audio+control], 64-byte name, codec, session, config, frame) → event order; keyframe gating; server exit mid-handshake → `.serverExited`; version-mismatch line → `.versionMismatch`; `stop()` idempotent and always calls `killServer`; `video=false` → name read from audio stream |
| `MirrorIntegrationTests` | `XCTSkipUnless(env["SEFIRAH_TEST_ADB_SERIAL"] != nil)`: real push/forward/spawn, asserts device name, ≥1 session packet, ≥1 keyframe sample created, audio codec id, then teardown; asserts `adb shell pgrep -f scrcpy` empty and `forward --list` empty. Never sends input. |

## Implementation plan

**Stage 1 — Video (read-only mirror in the tab)**
1. `Adb.swift`: `push(serial:local:remote:)`, `forward(serial:socketName:) -> UInt16`, `forwardRemove(serial:port:)`, `shell(serial:_:timeout:)`. `BundledTools.swift`: `NativeTools.locate()` (adb + server).
2. `Native/ServerOptions.swift`, `Native/Video/MediaPacket.swift`, `AnnexB.swift`, `VideoFormat.swift`, `SampleBufferFactory.swift`, `VideoFrameSink.swift` (+ tests for each).
3. `Native/ByteStream.swift` (`NWByteStream`, `MemoryByteStream` in tests), `Native/ServerLauncher.swift` (`ProcessDetachedSpawner`, `ServerProcess` with line splitter + 16 KiB tail).
4. `Native/MirrorEvent.swift`, `Native/MirrorSession.swift` (video task, process monitor, teardown; control channel present but only writes startup actions), `Native/MirrorDiagnostics.swift`.
5. App: `GeneralSettings.mirrorBackend`; `AppModel` (`selectedTab`, `mirrors`, `startMirror/stopMirror/stopAllMirrors`, predicate unions, `emergencyStop` on quit); `Sefirah/Mirror/{MirrorController,MirrorNSView,MirrorSurfaceView,MirrorView}.swift`; `MainSplitView` `.mirror` tab; `DeviceRailView`/`AppsView` → `startMirror`; backend picker in `SettingsView`.
6. Tests: ServerOptions, MediaPacket, AnnexB, VideoFormat, SampleBufferFactory, ServerLauncher, MirrorSession, Integration (skipped by default). Exit criterion: Xiaomi video visible in the tab (H.264 and H.265), rotation handled, Stop leaves no server process or forward.

**Stage 2 — Control**
1. `Native/Control/{AndroidInput,ControlMessage,DeviceMessage,ControlChannel,PointerMapper,MacKeyMap,HidKeyboard}.swift` + tests.
2. `MirrorSession`: reader/writer tasks, startup actions, `currentVideoSize`, `resetVideo` recovery, flex `resizeDisplay`.
3. App: `MirrorNSView` event overrides, input handler in `MirrorController`, `MirrorToolbar.swift`, clipboard bridging (`NSPasteboard`, ⌘V/⌘C), `AppsView` launch with virtual display + START_APP, reconnect policy, `.warning` banners, "Input not working?" popover.
4. Exit criterion: toolbar keys, START_APP + `new_display`, screen off, clipboard phone→Mac, rotate verified on the Xiaomi; touch/keyboard bytes verified by goldens (end-to-end touch needs a device with injection allowed).

**Stage 3 — Audio + polish**
1. `Native/Audio/{AudioDecoder,AudioPlayer}.swift`, audio task in `MirrorSession`, mute toggle, `audioUnavailable` banner; tests.
2. `MirrorSettingsView.swift` embedded in `SettingsView`; `ScrcpyArguments` codec parity; unlock-commands hook; `videoBuffer` timebase mode (optional); pop-out `Window(id: "mirror")` and menu commands in `SefirahApp.swift`; `docs/design/native-mirror.md`.
3. Exit criterion: Opus/AAC/raw audio in sync (<100 ms), `.both` mode, external fallback from the Failed state, `xcodebuild -project Sefirah.xcodeproj -scheme Sefirah -configuration Debug -derivedDataPath build -destination 'platform=macOS' build test` green.

## Implementation status (Stage 3 complete)

All three stages are implemented on `feature/native-mirror`. Stage 3 added:

- `Native/Audio/AudioDecoder.swift` — `AVAudioConverter` for Opus (`kAudioFormatOpus`, 960 frames/packet) and AAC
  (`kAudioFormatMPEG4AAC`, 1024 frames/packet, ASC as `magicCookie`), s16le passthrough for raw. Output is interleaved
  Float32 stereo 48 kHz. One packet per `convert` call; the input block returns `.noDataNow` after the packet (never
  `.endOfStream`, which would finalise the converter).
- `Native/Audio/AudioPlayer.swift` — `AudioSink` (protocol moved here from `MirrorSession.swift`), `PCMRingBuffer`
  (pure, tested: prime at target/2, silence + re-prime on underrun, drop the backlog above 2×target) and the
  `AVAudioEngine` + `AVAudioSourceNode` renderer. **Deviation:** the mixer input bus rejects an interleaved format
  (`-10868 kAudioUnitErr_FormatNotSupported`, seen on the device run), so the source node uses the standard
  deinterleaved format and the render callback splits the interleaved ring output through a preallocated scratch
  buffer. Mute keeps decoding/draining and discards PCM. Decoder/engine problems surface once via `onError` → warning
  banner. Target latency = `DeviceSettings.audioBuffer` (default 50 ms).
- `MirrorEvent.audioCodec`, `MirrorStage.unlock`, `MirrorSessionConfig.unlockCommands/unlockTimeout`.
- Unlock hook: when `unlockDeviceBeforeLaunch`, each `unlockCommands` entry runs as one `adb -s S shell "<command>"`
  before the push (5 s each, `delayMs` honoured); failures are warnings, not fatal. **Deviation:** the legacy app
  prompts for a password and substitutes `%pwd%` (`unlockTimeout` is its password-cache TTL, not a command timeout);
  the Mac port has no prompt yet, so `%pwd%` commands are skipped with a warning and `unlockTimeout` is unused.
- Settings: `GeneralSettings.mirrorFallbackToExternal` (default false; `decodeIfPresent`). `AppModel` opens the
  external scrcpy window when a native session fails before streaming with anything other than
  `.cancelled/.connectionLost/.noDevice/.adb`. `MirrorSettingsView` (embedded in Settings ▸ Screen mirroring) exposes
  every mapped `DeviceSettings` field; `ScrcpyArguments` now emits `--video-codec`/`--audio-codec` for parity.
- Reconnect: `MirrorController` retries once after `.connectionLost`, `.serverExited` or `.handshakeTimeout` that
  follow a streaming session, through `AppModel.startNativeMirrorAsync(reusing:)` so the serial is re-resolved
  (`adb connect` again for Wi-Fi devices). Rotation/resize stays in-session (session packets). App quit calls
  `emergencyStop()` on every controller; teardown always runs `pkill -f "scid=<%08x>"` (this session only) + `forward --remove`.
- Menu: *Mirror* ▸ Start (⌘⇧M), Stop all (⌘⇧.), Mute (⌘⇧U), Rotate (⌘⇧R), Paste clipboard. Not done (deferred):
  pop-out `Window(id: "mirror")`, `videoBuffer` timebase mode, AV1 testing, `displayOrientation` mapping.
- Tests: `AudioTests` (Opus silence 840/960 frames, AAC init, raw, ring buffer, player mute/stop), audio + unlock
  cases in `MirrorSessionTests`, `MirrorSettingsDecodeTests`, codec parity in `ScrcpyArgumentsTests`. The integration
  test now also runs the real `AudioPlayer` and asserts Opus packets decode with the engine running; an opt-in
  `SEFIRAH_TEST_START_APP=<package>` case checks `new_display` + `START_APP` ("New display: 1080x2400/420 (id=23)"
  on the Xiaomi). Pass env vars to xcodebuild tests with the `TEST_RUNNER_` prefix.
- Device run notes (Xiaomi 14 Ultra, Android 16 / HyperOS, Wi-Fi ADB): 20 Opus packets → 19 080 frames
  (840 + 19 × 960: the 120-frame pre-skip is applied by the converter), 0 decode errors, engine running; the server
  flushes a capture backlog at start, so ~6 000 frames are dropped by the 2×target rule in the first second and the
  buffer then settles at the target. In-app footer reads `H.264 · 1080x2400 · 8 Mbps · Opus`.

## Verification checklist

```
ADB=/Volumes/DATA/workspace/Sefirah-Mac/build/Build/Products/Debug/Sefirah.app/Contents/MacOS/adb
SERIAL=192.168.0.103:5555
$ADB -s $SERIAL get-state                       # "device"
```
1. Build + unit tests: `xcodebuild -project Sefirah.xcodeproj -scheme Sefirah -configuration Debug -derivedDataPath build -destination 'platform=macOS' build test`.
2. Integration test: `SEFIRAH_TEST_ADB_SERIAL=$SERIAL xcodebuild … -only-testing:SefirahCoreTests/MirrorIntegrationTests test`; afterwards `$ADB -s $SERIAL shell pgrep -f scrcpy` prints nothing (rc 1) and `$ADB -s $SERIAL forward --list` is empty.
3. Manual, Stage 1: launch `build/Build/Products/Debug/Sefirah.app`, Mirror tab, Start → device name `24031PN0DC`, video appears within ~2 s; rotate the phone (auto-rotate) → session packet, aspect updates, no freeze; switch `videoCodec` to H.265 → VPS/SPS/PPS path works; set `videoResolution` 1280 → 576×1280; Stop → `pgrep` empty.
4. Stage 2: toolbar Home/Back/Recents/Rotate/Notifications act on the phone (keycodes injected by the server's own process are not subject to the Xiaomi restriction — if they are also blocked, note it as expected); Screen off toggles the display (restored on Stop by CleanUp); Apps tab Launch with virtual display → `[server] INFO: New display: …` and the app appears in the mirror; copy text on the phone → appears in the Mac clipboard; ⌘V sends `SET_CLIPBOARD` (verify with a device that allows injection or by log); touch on a non-Xiaomi device when available.
5. Stage 3: audio audible with Opus, AAC, raw; `.both` keeps phone speaker playing; `.remote` opens no audio socket; mute keeps the stream draining (no server stall).
6. Hygiene after every manual run: `$ADB -s $SERIAL shell pkill -f scrcpy; $ADB -s $SERIAL forward --remove-all`. Do not change phone settings, install apps, or run `tcpip`/`reverse` on the test phone.
7. Quit the app while mirroring → server gone within 2 s (`pgrep` empty).

## Risks & open questions

- **Forward-tunnel race**: adb accepts TCP before the server listens; the dummy-byte loop must reconnect (not re-read) on EOF and poll process liveness — covered by `MirrorSessionTests`. Slow phones may take >3 s to start `app_process`; 10 s budget.
- **Handshake ordering**: device meta only arrives after *all* sockets are accepted; reading it earlier deadlocks (candidate 2's mistake). Encoded in the lifecycle and a fake-stream test.
- **Xiaomi injection restriction**: touches silently dropped; not detectable from logs. Static help text; end-to-end touch verification needs another device.
- **`AVSampleBufferDisplayLayer` format switch**: if a GPU/OS combo fails to switch formats mid-stream, fall back to recreating the layer (controller swaps the view on `.failed`). A manual `VTDecompressionSession` path is Plan B, not scheduled.
- **Scroll sign/scale** and **pinch** semantics need device confirmation; both are single constants.
- **Audio drift** over long sessions: the simple drop/refill strategy may need scrcpy's finer compensation; measure with a 10-minute run.
- **Swift 6 strictness**: all CM/AV objects are confined to one task each; sinks are `@unchecked Sendable` wrappers around thread-safe objects. Any future "process on main" idea must copy to `Sendable` value types first.
- **Multiple sessions** double Wi-Fi bandwidth; acceptable, but the rail button stops the device-level session first.
- **Server version lock**: `ServerOptions.serverVersion` is pinned to `scripts/scrcpy.lock` by a unit test so a bump to scrcpy 4.2 fails loudly before protocol drift.
- **Open**: legacy semantics of `DeviceSettings.displayOrientation` (map to `capture_orientation`?) — check the Windows Sefirah source before wiring; whether to keep `adb reverse` as an option for USB users (lower latency? negligible on localhost — deferred); whether `videoBuffer` deserves a timebase mode at all.

## Appendix A — Candidate review & scores

Checked against the v4.1 source (`DesktopConnection.open`, `Server.java:105-108`, `Streamer.java:17-19`, `demuxer.c:127-137`, `control_msg.c:128-136`, `ControlMessageReader.java:115-125`, `binary.h`) and Swift 6 strict-concurrency rules.

**Candidate 1 (layered / testable-first)** — Correctness 8, Simplicity 6, Testability 9, Latency 8, Maintainability 8.
Right: handshake order (all sockets, then meta), packet flag bits, touch/scroll/text goldens, sink boundary reasoning. Issues: reverse-tunnel listener adds a second code path and a stale-`adb reverse` hazard for little gain (reverse fails over Wi-Fi ADB); `ServerProcess.lines: AsyncStream<String>` is single-consumer (log tail vs. UI "copy log" would race); dummy-byte handling placed in the pure demuxer although it needs transport-level reconnects; actor-isolated `send()` puts an `await` on every input event; scroll input clamped to ±1 notch wastes the wire's ±16 range.

**Candidate 2 (UX-first)** — Correctness 6, Simplicity 8, Testability 8, Latency 8, Maintainability 7.
Right: forward-only tunnel, `ServerProcess` bounded `logTail` + `onLine`, reconnect policy, state/UX taxonomy, scroll edge cases (16 → `0x7fff`), `screen_w/h` stamping from the last session packet. Issues: **reads the 64-byte device meta before connecting audio/control — deadlocks in forward mode** (server writes meta only after all `accept()`s); scroll clamped to ±1 in the view; typed `throws(...)` adds noise; `MirrorSession.start()` "returns when streaming" muddles ownership of the task group; AppKit types in Core (acceptable — Core already imports AppKit).

Synthesis takes candidate 1's pure-codec layering, golden fixtures, handshake ordering and sink boundary; candidate 2's forward-only tunnel, event callback, process log tail, reconnect policy, state machine and UI states; adds a nonisolated `ControlChannel.send`, ±16 scroll range, `emergencyStop()` for app quit, `NativeTools`, and the lock-file version test.
