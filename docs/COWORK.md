# Picking up zouk in a new Cowork session

Context for whoever opens this repo cold. Cross-project conventions (git
locks, sandbox toolchain, comments, code style) are in
`~/workspace/woodie/docs/COWORK.md`. Read `README.md` first for the
user-facing description and API contract; for building from source and
the release/signing process, see `docs/DEVELOPER.md`/`docs/DELIVERY.md`.

## What this is

zouk is a minimal SwiftUI macOS app for browsing and downloading scans
from a home scanner/printer, talking to `GET /files.json` /
`GET /download/:filename` served by `lambada-web` (current production
backend) or `scandalous` (its Ruby predecessor). The main screen
deliberately mimics Finder's "connect to a Samba share" icon grid --
that's the whole design language to preserve.

## Sandbox limitation -- read this before touching Swift code

There is no Swift toolchain in the Cowork sandbox (Linux ARM64, no
`swift`/`xcrun`). Every `Sources/ZoukKit`/`Sources/zouk` edit is made by
inspection only and verified by the user running `make build`/
`make test`/`make run` on their own Mac -- don't claim a change builds or
passes without that confirmation.

## Gotchas worth knowing

- **Git writes from the sandbox leave stuck lock files**
  (`.git/index.lock`, `HEAD.lock`, etc.) that block even the user's own
  native Terminal until removed via `allow_cowork_file_delete`. Once a
  lock fight starts on a repo, stop running further git commands against
  it from the sandbox for that session -- hand the rest to the user's own
  terminal rather than mixing sandboxed and native git commands in the
  same stretch.
- **Signing identities & secrets** (referenced from `docs/DELIVERY.md`): a
  paid **Developer ID Application** cert (`John Woodell`, team
  `754T277KBJ` -- distinct from `6R5XSSRC9P`, the free personal-team cert
  Xcode creates automatically; don't conflate the two) signs the `.app`,
  and a separate **Developer ID Installer** cert signs the `.pkg`
  (`productbuild`/`pkgbuild --sign` don't accept the Application
  identity). Eight GitHub Actions secrets on `woodie/zouk`:
  `CERTIFICATE_P12_BASE64`, `CERTIFICATE_PASSWORD`,
  `INSTALLER_CERTIFICATE_P12_BASE64`, `INSTALLER_CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` (an
  app-specific password, not the real Apple ID password),
  `NOTARY_TEAM_ID`. Both `.p12`s are backed up (password-protected)
  outside the repo.
- **SwiftPM resource bundles + `Bundle.module`**: `ZoukKit`'s generated
  `Bundle.module` accessor only looks in the `.app`'s *top level* or a
  hardcoded absolute `.build` path -- not `Contents/Resources`, despite
  that being the conventional location. `Sources/ZoukKit/ResourceBundle.swift`
  works around this by checking `Bundle.main.resourceURL`
  (`Contents/Resources`) directly first, falling back to `Bundle.module`
  only for `swift run`/`swift test`/Xcode where `Bundle.main` isn't a real
  `.app`. `AppIconImage.swift`/`RunningDogView.swift` go through this, not
  `Bundle.module` directly. Also: a `.bundle` sitting at the app's top
  level (outside `Contents/`) fails `codesign --deep` outright ("unsealed
  contents present in the bundle root") -- `make bundle` only copies into
  `Contents/Resources` now, never the top level.
- **Local Network Privacy**: the first request to a private/LAN IP
  triggers a system "Allow 'zouk' to find devices on local networks?"
  dialog, and the in-flight request typically fails/times out while it's
  pending regardless of which button gets pressed -- this looks like a
  bug but isn't; retrying after granting permission works.
- **Homebrew's untrusted-tap gate** (introduced in Homebrew 6.0) blocks
  `brew tap woodie/zouk`/cask installs from a personal tap by default --
  resolved with `brew trust woodie/zouk`.

## Design conventions (don't regress on these)

The UI mimics Finder's icon-grid view closely and deliberately:

- **Window size**: opens small like Finder's network-share window --
  needs `idealWidth`/`idealHeight` on `.frame()`, not just
  `minWidth`/`minHeight` (`.windowResizability(.contentSize)` only
  respects the ideal values for initial sizing).
- **Selection**: the thumbnail stays unstyled except for a subtle tinted
  halo/shadow; the filename gets a colored pill (white text, tinted
  background). Blue when the window is key/focused, gray otherwise
  (`@Environment(\.controlActiveState)`), via
  `ScanThumbnailCell.selectionTint`, matching native macOS
  active/inactive tinting.
- **No-preview placeholder**: a hand-drawn dog-eared document shape (not
  an SF Symbol), sized slightly smaller than the cell's 96x120 footprint
  so it doesn't look bulkier than a real thumbnail.
- **Footer**: centered date + size when a scan is selected, or a scan
  count otherwise (the filename itself is a server-generated timestamp,
  never shown). `Can't reach <host>` replaces this when a connect attempt
  fails.
- **Toolbar**: browser-address-bar style -- a circular reload button,
  then a `TextField` bound to `model.hostInput` that reconnects
  `onSubmit`. No separate "edit host" button; typing into the bar *is*
  editing the host.
- **Double-click**: always opens a native `NSSavePanel` pre-filled with
  `scan.name`, `directoryURL` set to `~/Downloads`; confirming as-is
  reproduces the old silent behavior, but renaming/relocating is just as
  easy. The saved file always keeps `scan.name`'s own extension, enforced
  via `ExtensionEnforcingPanelDelegate` rather than `allowedContentTypes`
  (whose auto-correction *appends* a mismatched extension instead of
  replacing it). The delegate is held in a local `let` for the duration
  of `runModal()` since `NSSavePanel.delegate` is a weak reference.
- **Right-click menu** (`ScanThumbnailCell`): Download and Open, Download
  to…, Fast Download, Move to Trash -- menu items need explicit
  `Label(_:systemImage:)` icons (a plain `Button("title")` renders
  text-only in a context menu). Setting `confirmingDelete` synchronously
  from "Move to Trash" doesn't present the dialog -- the NSMenu is still
  tearing down, so the state change needs `Task { @MainActor in ... }` to
  land a beat later.

## Not yet done

- `Casks/zouk.rb`'s `depends_on macos: ">= :ventura"` triggers a Homebrew
  deprecation warning (string-comparison form) -- should become
  `depends_on macos: :ventura`.
