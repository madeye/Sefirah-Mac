# Vendored scrcpy

This directory holds the `scrcpy`, `adb` and `scrcpy-server` binaries that are
bundled into `Sefirah.app` so screen mirroring works with zero user setup.

The binaries are **not committed**. They come from the official Genymobile
release tarballs pinned (version + sha256) in `scripts/scrcpy.lock`.

```
scripts/fetch-scrcpy.sh      # populate this directory (idempotent; --force to re-fetch)
xcodegen generate            # xcodegen validates source paths, so fetch first
```

Layout after fetching:

| File | Notes |
|---|---|
| `scrcpy` | universal (arm64 + x86_64), ad-hoc signed; re-signed by Xcode on copy |
| `adb` | universal, from the same tarball; re-signed by Xcode on copy |
| `scrcpy-server` | device-side payload (not Mach-O) |
| `LICENSE` | Apache-2.0 from the tarball |
| `VERSION` | pinned version, checked against the lock by a pre-build script |
| `.stamp` | `<version>:<sha_aarch64>:<sha_x86_64>` used for idempotency |

To upgrade scrcpy, edit the three lines in `scripts/scrcpy.lock`, run the
fetch script and rebuild.
