# Developing zouk

Building from source and the project layout. For cutting and signing a
release, see [docs/DELIVERY.md](DELIVERY.md); for context on the
project's history, see [docs/COWORK.md](COWORK.md).

## Building

Requires Xcode/Swift on macOS (this is a Mac-only app; no Linux/iOS
target).

```
swift build      # or: make build
swift run        # or: make run
swift test       # or: make test
```

`make xcode` opens `Package.swift` directly in Xcode.

## Layout

- `Sources/ZoukKit` -- model, networking, and views (a library target so
  `Tests/ZoukKitTests` can `@testable import` it).
- `Sources/zouk` -- the thin `@main` app entry point.
- `Tests/ZoukKitTests` -- unit tests for hostname parsing, JSON decoding,
  and the URL-resolution logic the download path relies on.
- `docs/DELIVERY.md` -- how to cut and hand off a build.
- `docs/COWORK.md` -- context for picking this project back up cold.
- `.github/workflows/CI.yml` -- runs `make build`/`make test` on macOS for
  every push/PR to `main`.
- `.github/workflows/release.yml` -- on a pushed `vX.Y.Z` tag, builds,
  signs, notarizes, and attaches both the zipped `.app` and a signed
  `.pkg` installer to a GitHub Release (see `docs/DELIVERY.md`); the
  zip is what the Homebrew cask installs from.
