# zouk

A minimal macOS client for browsing and downloading the scans your old
scanner/printer relays through `lambada` (and, before that, `scandalous`).
The main screen looks like a Samba share: a Finder-style grid of PDF
thumbnails you click to select, then download to `~/Downloads`.

## Status: stopgap backend

`lambada` doesn't have an HTTP server yet, so zouk currently points at
`scandalous`'s `GET /scans.json` endpoint -- a small JSON API added
specifically as a stopgap so the family can keep pulling scans while zouk
gets built. See `scandalous/docs/adr/0001-remote-family-access.md` for the
full reasoning. Once the client works end-to-end, the plan is to build a
proper Go service in `lambada` to replace `scandalous`'s WEB component,
and point zouk at that instead.

The API contract zouk expects from either backend:

```
GET /scans.json
[{ "name": "1779907271.pdf", "size": 7, "time": "<ISO8601>", "url": "/download/1779907271.pdf" }, ...]

GET /download/:filename
<the PDF bytes>
```

## Using it

On launch, zouk asks for a hostname or IP address (e.g.
`scans.netpress.com` or `10.0.1.111:8080`) and remembers it for next time.
If the server can't be reached, it shows an inline error and lets you
retry or change the server. Once connected, click thumbnails to select
scans and click Download to copy them to `~/Downloads`.

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
