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
