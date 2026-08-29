#!/usr/bin/env bash
# Post-export signing checks for Sefirah.app (run before notarization).
# Usage: scripts/verify-bundle.sh path/to/Sefirah.app [--debug]
#   --debug relaxes the Developer ID / hardened-runtime / timestamp checks (ad-hoc local builds).
set -euo pipefail
APP="${1:?usage: verify-bundle.sh <Sefirah.app> [--debug]}"
DEBUG="${2:-}"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in Contents/MacOS/Sefirah Contents/MacOS/scrcpy Contents/MacOS/adb \
         Contents/Resources/scrcpy/scrcpy-server Contents/Resources/scrcpy/LICENSE \
         Contents/Resources/scrcpy/NOTICES.md Contents/Resources/scrcpy/VERSION; do
  [[ -e "$APP/$f" ]] || fail "missing $f"
done

codesign --verify --deep --strict --verbose=2 "$APP" || fail "codesign --verify failed"
lipo -info "$APP/Contents/MacOS/scrcpy" | grep -q 'x86_64 arm64' || fail "scrcpy is not universal"
"$APP/Contents/MacOS/scrcpy" --version | head -1

for bin in scrcpy adb; do
  info="$(codesign -dvv "$APP/Contents/MacOS/$bin" 2>&1)"
  if [[ "$DEBUG" != "--debug" ]]; then
    grep -q 'flags=0x10000(runtime)' <<<"$info" || fail "$bin: hardened runtime not set"
    grep -q 'TeamIdentifier=32B45SMMQL' <<<"$info" || fail "$bin: wrong team identifier"
    grep -q 'Authority=Developer ID Application' <<<"$info" || fail "$bin: not Developer ID signed"
    grep -q 'Timestamp=' <<<"$info" || fail "$bin: no secure timestamp"
  fi
  echo "OK: $bin ($(grep -o 'Identifier=[^ ]*' <<<"$info" | head -1))"
done

if [[ "$DEBUG" != "--debug" ]]; then
  spctl -a -t exec -vv "$APP" || echo "note: spctl rejected (expected before notarization + stapling)"
fi
echo "verify-bundle: OK"
