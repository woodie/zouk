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

## Packaging gotcha: SwiftPM resource bundles + `Bundle.module`

- `ZoukKit`'s `resources: [.process("Resources")]` (`Package.swift`) makes
  `swift build` emit a `zouk_ZoukKit.bundle` next to the binary, plus a
  generated `Bundle.module` accessor
  (`.build/<triple>/<config>/ZoukKit.build/DerivedSources/resource_bundle_accessor.swift`)
  that looks for it in exactly two places: `<app>.app/zouk_ZoukKit.bundle`
  -- the bundle's *top level*, via `Bundle.main.bundleURL` -- or a
  fallback hardcoded to the *absolute* `.build` path on whichever machine
  compiled it. Note this is **not** `Contents/Resources`: that's the
  separate `resourceURL` property, and this generated accessor never
  checks it, despite that being the conventional macOS location for
  bundled resources. `AppIcon.nsImage` (`AppIconImage.swift`) and the
  running-dog GIF (`RunningDogView.swift`) both go through `Bundle.module`.
- v1.1 added that code (commit `0d1cb45`) without updating `make bundle`'s
  Resources-copying step to also copy the new `.bundle` -- so the
  assembled `.app` only "worked" on the dev machine that built it, since
  the hardcoded `.build` fallback happened to still resolve there. Moving
  the same `.app` to a Mac that never built the project (no matching
  `.build` at that exact path) crashed instantly on launch with
  `EXC_BREAKPOINT` / `_assertionFailure` deep in `NSBundle.module`'s lazy
  initializer. v1.0.0 never hit this -- it predates any `Bundle.module`
  use entirely.
- First fix attempt had `make bundle` copy `*.bundle` into
  `Contents/Resources` only -- the conventional location, and what this
  doc used to (incorrectly) claim `Bundle.module` checked. Confirmed
  wrong empirically, not just by re-reading the generated source: `find`
  on the family Mac showed the bundle present and intact at
  `Contents/Resources/zouk_ZoukKit.bundle`, and the very next launch
  still fatalError'd in `Bundle.module` (`docs/crash_4.txt`, two crash
  reports after the original `Contents/Resources`-only fix). `make
  bundle` now copies `*.bundle` to both the `.app`'s top level (what the
  current accessor's primary lookup actually depends on) and
  `Contents/Resources` (for convention, and in case a future SwiftPM
  regenerates the accessor to check `resourceURL` instead), and verifies
  the top-level copy landed.
- CI now runs `make bundle` too (see `.github/workflows/CI.yml`), so a
  regression here fails the build immediately instead of only surfacing
  on someone's fresh Mac. CI can't catch *this specific* mistake though --
  it only checks that the directory exists, not that it's at the path
  `Bundle.module` actually reads from, which is exactly how the first fix
  passed CI and still crashed on a real machine.
- Separately, `bundle`'s own `swift build` call never passed
  `$(SWIFT_BUILD_FLAGS)` (`--configuration release`), unlike `build` and
  `install` -- so `make bundle` and `make run` (which depends on it)
  silently assembled a **debug** `.app` the entire time, despite
  `docs/DELIVERY.md` already (correctly) documenting `make bundle` as a
  release build. Caught by running `make bundle` directly and noticing
  `swift build`'s own "Building for debugging..." line. Fixed by passing
  `$(SWIFT_BUILD_FLAGS)` to both the build call and the
  `--show-bin-path` lookup, matching how `install` already did it.

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
