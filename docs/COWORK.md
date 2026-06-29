# Picking up zouk in a new Cowork session

Context for whoever opens this repo cold, with none of
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
  Quick/Nimble `describe/context/it` style) is done: `AppModelTests.swift`,
  `ScanClientTests.swift`, and `ScanEntryTests.swift` were replaced 1:1 by
  `AppModelSpec.swift`, `ScanClientSpec.swift`, and `ScanEntrySpec.swift`,
  matching xctidy/next-caltrain-swift's spec style (`final class FooSpec:
  QuickSpec`, `override class func spec()`, `describe`/`context`/`it`).
  `AppModel` is `@MainActor`, which next-caltrain-swift's specs never had
  to deal with -- each affected `it` hops over via `await MainActor.run { ... }`
  rather than marking the whole spec class `@MainActor`, since Quick's
  `it`/`beforeEach` closures aren't isolated by default. Made by inspection
  only per the sandbox limitation above; confirmed via a real `make test`
  on the user's Mac -- all 13 specs pass.
- A real `make test | xctidy` run against this repo's output also caught
  an unrelated bug in `xctidy` itself: its comma-disambiguation
  dictionary came back empty for any project laid out the way SwiftPM
  expects (`Tests/<ModuleName>Tests/*.swift`, one level below the
  directory `xctidy` is told to scan), so descriptions with a bare prose
  comma rendered as spurious extra nesting. At the time, three `it`
  descriptions here were reworded to avoid commas entirely as a
  workaround (`"decodes the name size time and url fields"`, `"is nil
  along with downloadedAt"` in `ScanEntrySpec.swift`, `"...baseURL by
  replacing the whole path"` in `ScanClientSpec.swift`). Now that
  `xctidy` is fixed upstream (tagged `v0.2.1`; see that repo's own
  `docs/COWORK.md` for the root cause), the workaround is gone -- all
  three are back to their natural prose-comma phrasing
  (`"decodes the name, size, time, and url fields"`, `"is nil, along
  with downloadedAt"`, `"...baseURL, replacing the whole path"`) and
  render correctly as long as `xctidy` is rebuilt/reinstalled at
  `v0.2.1` or later.
- Zouk's methods tested, not internals: `Tests/ZoukKitTests` specs are
  now organized around each type's actual public methods/properties
  (`.method(_:)` for static, `#method(_:)` for instance -- matching
  xctidy/next-caltrain-swift's `GoodTimesSpec.swift` convention), with
  shared fixtures declared once and set up via `beforeEach` so an outer
  `context`'s state cascades down to nested ones, instead of constructing
  things fresh inline inside each `it`. `ScanClientSpec.swift` in
  particular dropped two tests that only exercised raw Foundation
  (`URL(string:relativeTo:)`, `.appendingPathComponent`) without ever
  calling `ScanClient`, and filled in the `#cachedFile(for:in:)`/
  `#save(_:to:cacheDirectory:)` placeholders (previously just
  `expect(true).to(beTrue())`) with real coverage against
  `FakeHTTPClient` and real temp directories. Made by inspection only per
  the sandbox limitation above; confirmed via a real `make test` on the
  user's Mac -- all 20 specs pass. Sharing a `@MainActor` `AppModel`
  across separate `beforeEach`/`it` calls to `MainActor.run { ... }` in
  `AppModelSpec.swift` did initially raise `#SendableClosureCaptures`
  warnings on the shared `model`/`scan` vars (an error under the Swift 6
  language mode, not yet under the mode this project actually compiles
  in) -- the compiler can't see that Quick always finishes a `beforeEach`
  before starting its `it` and never runs either concurrently, so it
  can't prove the cross-isolation sharing is safe. Silenced with
  `nonisolated(unsafe)` on both vars rather than restructuring around it,
  since the assumption it's asserting (no concurrent access) is actually
  true here -- see the comment at that declaration.
  Deliberate scope decision made alongside this: no tests for the SwiftUI
  views -- see the `Tests/ZoukKitTests` entry under Layout below.
- **Stale-cache bug found and fixed**: `ScanClient.cachedFile(for:in:)`
  keys its on-disk cache purely by `scan.name`, trusting the doc-commented
  assumption on `ScanEntry` that the server never reuses a name. Found by
  the user manually dropping a same-named file into the server's
  directory to test the "no preview" placeholder -- instead, the grid
  cell silently showed the *previous* file's thumbnail (a stale local
  cache entry from earlier testing under that same name), with nothing
  on screen suggesting anything was wrong. Fixed by comparing the cached
  file's actual size on disk against `scan.size` before trusting it,
  re-downloading on a mismatch instead of serving stale bytes forever --
  see `ScanClient.cachedSizeMatches`. Not foolproof (two different files
  could coincidentally share a size), but `/scans.json` doesn't expose
  anything stronger than size/time to check against. Covered by a new
  `ScanClientSpec` context ("when a same-named file is cached but its
  size doesn't match scan.size"); the existing "already cached" context's
  fixture bytes were also corrected to actually be 7 bytes long, matching
  the shared `scan.size` -- they weren't before, which the old
  (size-blind) implementation never noticed.

- **Release automation shipped and exercised for real; v1.4.0 is live**:
  `v1.0.0`-`v1.3.0` were all tagged and released by hand, with no GitHub
  Actions release workflow. Added `.github/workflows/release.yml`
  (triggers on a pushed `vX.Y.Z` tag, runs `make build`/`make test`/
  `make package` on `macos-latest`, computes the release zip's sha256
  into `$GITHUB_STEP_SUMMARY` under "sha256 for the Homebrew cask", and
  publishes a GitHub Release via `gh release create ... --generate-notes`),
  a retroactive `docs/releases/v1.3.0.md`, and `docs/DELIVERY.md`/
  `README.md` updates documenting the tag -> release -> cask-update flow
  end to end. `Resources/Info.plist`'s `CFBundleShortVersionString` was
  bumped to `1.4`, `v1.4.0` tagged and pushed, and `release.yml`'s first
  real run succeeded (Run #1, "Bump version to 1.4", Success, 1m 27s,
  zip `zouk-1.4.zip`, sha256
  `1c26621995e3cba88897d78d9c6a950572330800ae6af99e7d9e61758779f2d3`).
  Release is live at `github.com/woodie/zouk/releases/tag/v1.4.0`.
- **`woodie/homebrew-zouk` is wired up and live**: filled `Casks/zouk.rb`
  with `version "1.4"` and the real sha256 above. The repo itself didn't
  exist on GitHub yet either, which made this messier than it should
  have been: created the GitHub repo with a LICENSE pre-added (rather
  than fully empty), so the local `git init`-based history and the
  remote's history were unrelated and needed
  `git pull origin main --allow-unrelated-histories --no-rebase` plus a
  manual merge-commit message in vim to reconcile -- a plain `git clone`
  of an empty remote would have avoided this entirely, worth remembering
  next time a new tap/repo needs creating. Separately, the first `git
  add`/`commit` only staged `Casks/zouk.rb` and missed `README.md`
  entirely (an oversight, not a tooling problem), so the repo briefly had
  no README on GitHub (correctly flagged by GitHub's own "Add a README"
  banner) until a follow-up commit added it. Both are pushed now.
  `brew tap woodie/zouk` also hit Homebrew 6.0's new (June 2026)
  untrusted-tap gate ("Refusing to load cask ... from untrusted tap") --
  resolved with `brew trust woodie/zouk`, since it's a personal tap.
  Outstanding nit: `Casks/zouk.rb`'s `depends_on macos: ">= :ventura"`
  triggers a deprecation warning (string-comparison form) -- should
  become `depends_on macos: :ventura`, not yet fixed.
- **Real code signing + notarization, in progress (tasks #24-#30).** The
  user has a paid Apple Developer Program account, which changes the
  calculus on the "no warning at all" path `docs/DELIVERY.md` previously
  wrote off as "overkill for v0.1.0." Done so far: created a `Developer
  ID Application: John Woodell (754T277KBJ)` identity in Keychain via
  Xcode -- note this team ID is **different** from `6R5XSSRC9P`, the free
  personal team behind the pre-existing `Apple Development` cert; don't
  conflate the two. Backed up the cert+key as a password-protected
  `.p12` (Documents, which syncs to iCloud, plus a copy in Google Drive --
  fine since the file is useless without the export password, which
  lives separately in Apple Passwords). Added a `sign` target to the
  Makefile (`codesign --options runtime --timestamp`, required for
  notarization) and made `package` depend on it. Added six GitHub Actions
  secrets on `woodie/zouk` (`CERTIFICATE_P12_BASE64`,
  `CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`,
  `NOTARY_PASSWORD` -- an app-specific password from appleid.apple.com,
  not the real Apple ID password -- `NOTARY_TEAM_ID` = `754T277KBJ`).
  Added cert-import + `xcrun notarytool submit --wait` +
  `xcrun stapler staple` steps to `release.yml`, gated behind those
  secrets.
  Two real failures hit and fixed while exercising this end-to-end on a
  real `v1.5.0` tag: (1) `security import` rejected the first
  `CERTIFICATE_PASSWORD`/`.p12` pair -- likely the classic mix-up between
  the *export* password (protects the `.p12`, what we want) and the *Mac
  login* password (a separate OS prompt during Keychain Access's export
  flow, easy to enter into the wrong place) -- fixed by re-exporting a
  fresh `.p12` with a password set and used immediately, no chance to
  misremember it. Also swapped the workflow's `base64 --decode` for
  `openssl base64 -d` while in there, since the bare `base64` CLI's
  decode flag differs between macOS/BSD and GNU and isn't worth the
  ambiguity. (2) Once past that, `codesign --sign --deep` failed outright
  with "unsealed contents present in the bundle root" -- caused by `make
  bundle` copying ZoukKit's resource bundle to the `.app`'s *top level*
  (see "Packaging gotcha" below), which sits outside `Contents/` and
  `codesign` refuses to seal. Fixed at the root: added
  `Sources/ZoukKit/ResourceBundle.swift` so resource lookups go through
  `Bundle.main.resourceURL` (`Contents/Resources`) instead of the
  generated `Bundle.module`, and `make bundle` no longer copies to the
  top level at all. Not yet re-verified end-to-end -- next tag push is
  the real test.
  Once a `brew install --cask zouk` actually launches with zero Gatekeeper
  warning: strip the Gatekeeper-warning language and `--no-quarantine`
  workaround from `docs/DELIVERY.md`, `README.md`, and the cask's
  `caveats` block (task #28).

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
- **Double-click behavior**: selects the scan, then always shows a native
  `NSSavePanel` (`AppModel.open(_:)`) pre-filled with `scan.name` and
  `panel.directoryURL` set to `~/Downloads` -- confirming as-is reproduces
  the old silent "just go to Downloads" behavior exactly, but renaming or
  picking a different folder is just as easy. Whatever destination comes
  back, `ScanClient.save(_:to:cacheDirectory:)` copies the cached file
  there (overwriting if it already exists -- the panel's own "replace
  this file?" alert already asked), then `NSWorkspace.shared.open(destination)`
  opens it. Cancelling the panel leaves the scan selected and does
  nothing else -- no save, no open. The saved file always keeps
  `scan.name`'s own extension (not a hardcoded ".pdf" -- scanners that
  hand back e.g. ".jpg" are covered the same way), enforced via
  `ExtensionEnforcingPanelDelegate` rather than `panel.allowedContentTypes`:
  that property's own auto-correction *appends* its required extension
  to a mismatched one instead of replacing it (typing "foobar.zip" would
  save as "foobar.zip.pdf", not "foobar.pdf"), so this delegate
  intercepts `panel(_:userEnteredFilename:confirmed:)` directly and
  rewrites the name itself -- strip whatever's there, append the
  original extension, once. Skipped when the scan name has no extension
  at all, since there'd be nothing to enforce. The delegate instance is
  held in a local `let` for the duration of `runModal()`, since
  `NSSavePanel.delegate` is a weak reference.

  This replaced an earlier two-gesture design: double-click silently
  downloaded straight to Downloads (added from real feedback -- an adult
  son kept double-clicking scans expecting them to open, not just
  download), and a separate right-click/long-press gesture popped the
  Save panel but skipped opening the file afterward. Merged into one
  gesture per later feedback: the user always moved saved scans
  elsewhere anyway, so silently dumping into Downloads was friction, not
  convenience -- the panel removes that extra manual move step, and
  opening the file afterward was explicitly called out as worth keeping
  regardless of where the picker pointed. Right-click/long-press and the
  `RightClickCatcher` AppKit bridge were removed outright rather than
  kept as a redundant duplicate trigger.
- **No busy indicator while opening**: tried a `RunningDogView` overlay
  (`ScanGridView.OpeningScanOverlay`) plus a minimum-duration pad
  (`AppModel.openingScanName`/`waitOutMinimum`) so it wouldn't flash by
  too fast to see, but the user asked to drop both rather than fix them
  up. `RunningDogView` itself is untouched and still only appears in
  `ConnectingView`.
- **Saving/saved messaging**: `open(_:)` selects the scan and clears any
  leftover `savedMessage` up front, then -- once the panel resolves --
  shows `AppModel.savingMessage` ("Saving `<name>`…") in the same
  text-only capsule overlay the old "Opened ..." status used, then swaps
  that for `AppModel.savedMessage` ("File `<name>` saved.") once the
  file's on disk and handed to NSWorkspace. The footer text deliberately
  doesn't name the destination anymore -- it used to say "...saved to
  Downloads" back when Downloads was the only possible destination, but
  now the user just picked the destination themselves in the panel, so
  repeating it back isn't useful. `savedMessage` isn't on a timer -- it
  takes over the footer (ahead of the selected-scan stats/scan-count
  text `ScanGridView.footer` normally shows) and stays there until
  `toggle(_:)` (a new selection) or another `open(_:)` clears it.
  Replaced an earlier version of this same idea that used a
  `RunningDogView`/spinner overlay during the save -- the user wanted
  the save itself silent and the confirmation to be what's hard to
  miss, not the wait.
- **Single gesture, no context menu**: only single-click (select) and
  double-click (`open(_:)`) remain on `ScanThumbnailCell`, given
  explicit precedence with `TapGesture(count: 2).exclusively(before:
  TapGesture(count: 1))` rather than two independent `onTapGesture`
  modifiers. A right-click/long-press variant of the Save panel
  (`AppModel.saveAs(_:)`, plus a `ScanGridView.RightClickCatcher`
  AppKit bridge for secondary-click) existed briefly but was removed
  once double-click absorbed the same panel-then-open behavior --
  keeping it around afterward would've just been a second gesture for
  the identical action, which cuts against the "simplify" framing that
  prompted the merge in the first place.

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
- The top-level copy came back to bite us once real code signing entered
  the picture (see "Current state" above): `codesign
  --sign --deep` on a `.build/zouk.app` with a `.bundle` sitting at the
  top level (alongside `Contents/`, not inside it) fails outright with
  "unsealed contents present in the bundle root" -- a hard signing error,
  not just something notarization would object to later. Top-level
  placement and a signed app turned out to be mutually exclusive.
  Fixed properly this time instead of patching around it again: added
  `Sources/ZoukKit/ResourceBundle.swift`, which checks
  `Bundle.main.resourceURL` (i.e. `Contents/Resources`) directly and only
  falls back to the generated `Bundle.module` for `swift run`/`swift
  test`/Xcode, where `Bundle.main` isn't a real `.app`. `AppIconImage.swift`
  and `RunningDogView.swift` now go through `ZoukResources.bundle`
  instead of `Bundle.module` directly. `make bundle` copies `*.bundle`
  into `Contents/Resources` only now -- the top-level copy is gone for
  good, since nothing reads it anymore and it's actively harmful once
  signed.

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
- `Tests/ZoukKitTests` -- Quick/Nimble specs organized by public method
  rather than by scenario: `ScanEntrySpec` (`Decodable`, `#formattedSize`,
  `#downloadedAt`/`#formattedDate`), `ScanClientSpec` (`#fetchScans()`,
  `#cachedFile(for:in:)`, `#save(_:to:cacheDirectory:)`, via the fake
  `ScanHTTPClient` in `FakeHTTPClient.swift` instead of the real
  network), and `AppModelSpec` (`.baseURL(fromHostInput:)`,
  `#toggle(_:)`, `#changeServer()`). Deliberately no tests for the
  SwiftUI views (`ContentView`, `HostEntryView`, `ScanGridView`,
  `ConnectingView`, `RunningDogView`) -- this is a small, single-developer
  app and the model/networking/data-layer coverage above is judged
  sufficient; view regressions get caught by eye via `make run`, not by
  an automated suite. Revisit (e.g. snapshot testing or ViewInspector)
  only if that stops being true.
- `docs/DELIVERY.md` -- how to cut and hand off a build.
- `docs/COWORK.md` -- this file.
- `.github/workflows/CI.yml` -- runs `make build`/`make test` on macOS
  for every push/PR to `main`.
- `LICENSE` -- MIT.
