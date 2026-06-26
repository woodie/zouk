# Picking up zouk in a new Cowork session

Context for whoever (human or Claude) opens this repo cold, with none of
the prior conversation history.

## What this is

`zouk` is a minimal SwiftUI macOS app for browsing and downloading scans
from a home scanner/printer. It talks to a stopgap `GET /scans.json` /
`GET /download/:filename` API (currently served by the `scandalous`
repo's web component; see that repo's `docs/adr/0001-remote-family-access.md`
for why). The main screen deliberately mimics Finder's "connect to a
Samba share" icon grid -- that's the whole design language to preserve.

Read `README.md` first for the user-facing description and API
contract. This doc is about *how the project got here* and *how to keep
working on it consistently*.

## Sandbox limitation -- read this before touching Swift code

There is **no Swift toolchain in the Cowork sandbox** (confirmed: Linux
ARM64, no `swift`, no `xcrun`). Every `Sources/ZoukKit` / `Sources/zouk`
edit in this project has been made by inspection only and verified by
the user running `make build` / `make test` / `make run` on their own
Mac. Don't claim a Swift change builds or passes tests without the user
confirming it on macOS -- just make the edit and ask them to run the
Makefile target.

## Current state

- **v1.0.0 is tagged** and CI is green on `main` (GitHub Actions, macOS
  runner, `make build` + `make test`). MIT licensed. README has the
  badge row (Swift/CI/Release/License) plus a real screenshot
  (`docs/window.png`) of the app showing actual scans.
- The release notes used for v1.0.0 on GitHub: first-tagged-release
  bullets covering the Finder-style grid, address-bar host entry, local
  network permission handling, Finder-style download de-dup naming, and
  CI/license. No changelog needed yet -- nothing prior to diff against.
- See `docs/DELIVERY.md` for the release/distribution checklist and
  Gatekeeper notes for handing a build to a family member without Xcode.
- `git status` typically has uncommitted changes after a design pass --
  check before assuming HEAD reflects the latest UI.
- Task #16 on the standing task list (convert `Tests/ZoukKitTests` to
  Quick/Nimble `describe/context/it` style) is still pending and unrelated
  to recent UI work -- pick it up independently if asked.

## Next up (per the user, not yet written)

- README: a line about *why* zouk exists -- downloading files over HTTP
  in a browser is a drag, which is the actual motivation.
- README: a line on *who this is for* -- anyone with an old scanner that
  needs an open relay (i.e. exactly the `scandalous`/`lambada` situation
  this repo was built around, generalized).

## Design conventions established so far (don't regress on these)

The UI has gone through many rounds of "make it match Finder exactly,"
so these choices are deliberate, not arbitrary:

- **Window size**: opens small by default, like Finder's network-share
  window. Requires `idealWidth`/`idealHeight` on `ContentView`'s
  `.frame()`, not just `minWidth`/`minHeight` -- `.windowResizability(.contentSize)`
  only respects the ideal values for initial sizing.
- **Selection model**: matches Finder's icon view exactly -- the
  thumbnail/icon itself stays unstyled, only the filename label gets a
  colored pill (white text on a tinted background). A separate, more
  subtle tinted halo + shadow now also sits behind the thumbnail itself
  (added on top of the filename pill, not instead of it).
- **Selection color**: blue when the window is key/focused, gray
  otherwise, via `@Environment(\.controlActiveState)` -- mirrors native
  macOS active/inactive selection tinting. This logic lives in
  `ScanThumbnailCell.selectionTint` and is reused for both the filename
  pill and the thumbnail halo.
- **No-preview placeholder**: a hand-drawn dog-eared document (white
  page, diagonal-cut top-right corner, small folded triangle, soft drop
  shadow) -- not an SF Symbol -- sized slightly smaller than the cell's
  96x120 footprint via nested `.frame()` calls so it doesn't look
  bulkier than a real PDF thumbnail in the same slot. Square corners
  except the fold cut.
- **Footer**: centered date + size only when a scan is selected (the
  scan's filename is a server-generated timestamp and never meaningful,
  so it's never shown), or a scan count when nothing's selected. Dates
  use `ScanEntry.formattedDate`, a Finder-style relative timestamp
  ("Today at 4:11 PM"). When a connect attempt fails to reach an
  otherwise well-formed host, the footer shows `Can't reach <host>`
  instead, via `AppModel.unreachableHost`.
- **Toolbar (`ScanGridView`, post-connect only)**: browser-address-bar
  style -- a small circular reload button on the left, then a `TextField`
  bound directly to `model.hostInput` that fills the rest of the width
  and reconnects `onSubmit`. There is no separate "edit host" button
  anymore; typing into the bar *is* editing the host. `HostEntryView`
  (the first-launch connect screen) is intentionally untouched by this --
  it still has its own `TextField` + `Connect` button layout.
- **Toolbar button chrome**: `CircularIconButtonStyle` (icon-only,
  circular, darkens on press) is the only custom button style left in
  `ScanGridView.swift`. An earlier wide pill style (`WideToolbarButtonStyle`,
  icon+label together) was fully replaced when the toolbar became a
  single icon + address bar -- don't reintroduce it without a reason.
- **Error view**: centered icon + short error message + a short italic-weight
  "try again" hint line + the "Try Again" button. The error message text
  itself (`ConnectionState.failed`'s string) intentionally does *not*
  also say "try again" anymore, to avoid repeating that across both
  lines.

## macOS quirks worth knowing before debugging "it doesn't connect"

- **Local Network Privacy**: the *first* request to a private/LAN IP
  triggers a system "Allow 'zouk' to find devices on local networks?"
  dialog. The in-flight request usually fails/times out while that
  dialog is pending, regardless of which button gets pressed -- this
  looks like a bug but isn't one. Retrying after the permission is
  granted works. `Info.plist` now sets `NSLocalNetworkUsageDescription`
  so the dialog shows zouk-specific text instead of Apple's generic
  boilerplate.
- **Gatekeeper / signing** (for handing a build to a family member
  without Xcode): Apple Silicon binaries get an automatic ad-hoc
  signature from the linker, which is enough to run -- no paid Developer
  ID account or Xcode signing needed for one-off distribution. The
  quarantine flag only gets attached by quarantine-aware transfer
  methods (AirDrop, Mail, browser download), not USB/local-network copy
  or `scp`. On current macOS, the override path is System Settings →
  Privacy & Security → "Open Anyway" (the old right-click bypass is
  gone). Full notarization is a separate, optional, paid path -- not
  needed here. Details in `docs/DELIVERY.md`.

## Build/test/run

```
make build     # swift build --configuration release
make test      # swift test
make run       # assembles .build/zouk.app and opens it via `open`,
               # so the window becomes key/focused like a real Mac app
               # (swift run alone leaves keystrokes going to the terminal)
make bundle    # what `make run` uses internally; just the .app, no launch
make xcode     # open Package.swift in Xcode directly
```

## Layout

- `Sources/ZoukKit` -- model (`AppModel`), networking (`ScanClient`),
  data (`ScanEntry`), and views (`ContentView`, `HostEntryView`,
  `ScanGridView`). Library target so `Tests/ZoukKitTests` can
  `@testable import` it.
- `Sources/zouk` -- thin `@main` entry point.
- `Tests/ZoukKitTests` -- unit tests for hostname parsing, JSON
  decoding, formatted date/size, and download-path URL resolution.
- `docs/DELIVERY.md` -- how to cut and hand off a build.
- `docs/COWORK.md` -- this file.
- `.github/workflows/CI.yml` -- runs `make build`/`make test` on macOS
  for every push/PR to `main`.
- `LICENSE` -- MIT.
