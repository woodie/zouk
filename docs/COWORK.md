# Picking up zouk in a new Cowork session

Context for whoever opens this repo cold, with none of
the prior conversation history. Cross-project conventions (git locks,
sandbox toolchain) are in `~/workspace/woodie/docs/COWORK.md`.

## What this is

`zouk` is a minimal SwiftUI macOS app for browsing and downloading scans
from a home scanner/printer. It talks to a `GET /files.json` /
`GET /download/:filename` API, served by either `lambada-web` (the
current production backend) or `scandalous` (its Ruby predecessor). The
endpoint was `/scans.json` until this session; see "This session" below.
The main screen deliberately mimics Finder's "connect to a
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
  could coincidentally share a size), but `/files.json` doesn't expose
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
- **Real code signing + notarization: done and verified (tasks #24-#31).**
  The user has a paid Apple Developer Program account, which made the "no
  warning at all" path worthwhile -- `docs/DELIVERY.md` had previously
  written this off as "overkill for v0.1.0." Created a `Developer ID
  Application: John Woodell (754T277KBJ)` identity in Keychain via Xcode
  -- note this team ID is **different** from `6R5XSSRC9P`, the free
  personal team behind the pre-existing `Apple Development` cert; don't
  conflate the two. Backed up the cert+key as a password-protected `.p12`
  (Documents, which syncs to iCloud, plus a copy in Google Drive -- fine
  since the file is useless without the export password, which lives
  separately in Apple Passwords). Added a `sign` target to the Makefile
  (`codesign --options runtime --timestamp`, required for notarization)
  and made `package` depend on it. Added six GitHub Actions secrets on
  `woodie/zouk` (`CERTIFICATE_P12_BASE64`, `CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` -- an
  app-specific password from appleid.apple.com, not the real Apple ID
  password -- `NOTARY_TEAM_ID` = `754T277KBJ`). Added cert-import +
  `xcrun notarytool submit --wait` + `xcrun stapler staple` steps to
  `release.yml`, gated behind those secrets.
  Two real failures were hit and fixed while exercising this end-to-end
  on `v1.5.0`: (1) `security import` rejected the first
  `CERTIFICATE_PASSWORD`/`.p12` pair -- likely the classic mix-up between
  the *export* password (protects the `.p12`, what we want) and the *Mac
  login* password (a separate OS prompt during Keychain Access's export
  flow, easy to enter into the wrong place) -- fixed by re-exporting a
  fresh `.p12` with a password set and used immediately, no chance to
  misremember it. Also swapped the workflow's `base64 --decode` for
  `openssl base64 -d -A` while in there, since the bare `base64` CLI's
  decode flag differs between macOS/BSD and GNU and isn't worth the
  ambiguity. (2) Once past that, `codesign --sign --deep` failed outright
  with "unsealed contents present in the bundle root" -- caused by `make
  bundle` copying ZoukKit's resource bundle to the `.app`'s *top level*
  (see "Packaging gotcha" below), which sits outside `Contents/` and
  `codesign` refuses to seal. Fixed at the root: added
  `Sources/ZoukKit/ResourceBundle.swift` so resource lookups go through
  `Bundle.main.resourceURL` (`Contents/Resources`) instead of the
  generated `Bundle.module`, and `make bundle` no longer copies to the
  top level at all.
  A separate, latent bug in `woodie/homebrew-zouk` surfaced once the
  untrusted-tap gate stopped blocking installs first: the cask's single
  `version "1.5"` field was used to build both the git tag (wrong --
  produced `v1.5`, but the real tag is `v1.5.0`) and the zip filename
  (right -- `zouk-1.5.zip`), 404ing on download. Fixed with Homebrew's
  compound-version syntax: `version "1.5.0,1.5"` plus
  `version.before_comma`/`.after_comma` in the cask's `url` (task #31;
  see that repo's README for the pattern going forward).
  **Verified end-to-end**: `v1.5.0` tagged, `release.yml` green
  (signs -> notarizes -> staples -> publishes), `brew install --cask
  zouk` succeeded, first launch showed only the routine "downloaded from
  the Internet... none detected" notice (not the blocking malware
  dialog), and `spctl -a -vv /Applications/zouk.app` confirmed `accepted`
  / `source=Notarized Developer ID` / `origin=Developer ID Application:
  John Woodell (754T277KBJ)`. The Gatekeeper-warning / `--no-quarantine`
  language in `docs/DELIVERY.md`, `README.md`, and the cask's `caveats`
  block has been updated to match (task #28).

## This session: `/files.json` + `url`→`path` field rename (breaking API change)

woodie noticed the JSON field was never a URL -- `/download/<name>` is a
server-relative path, not a URL -- so `ScanEntry.url`/`json:"url"` is
renamed to `path`/`json:"path"` throughout `ScanEntry.swift`,
`ScanClient.swift` (the `cachedFile(for:in:)` call site that resolves it
against `baseURL`), and every test fixture (`ScanEntrySpec.swift`,
`ScanClientSpec.swift`, `AppModelSpec.swift`). The endpoint itself moved
from `/scans.json` to `/files.json` (woodie's reasoning: the API just
shares files, and "scans" was an unnecessary narrowing given he wants
room to expand the API later) -- only `ScanClient.fetchScans()`'s
*implementation* changed which path it requests; the method name itself
was deliberately left alone, matching the same "don't rename
methods/functions" constraint applied on the `scandalous`/`lambada-web`
side of this same change (see lambada's `docs/COWORK.md`).

This is a breaking wire-format change shared across three repos
(`scandalous`, `lambada-web`, `zouk`), done together in one session so
none of them are left half-migrated -- an old `zouk` build pointed at a
freshly-renamed server would 404 on `/scans.json`, and a new `zouk` build
pointed at an unmigrated server would fail to decode a listing missing
the `path` key it now expects. Made by inspection only per the sandbox
limitation above, then **confirmed on real hardware**: `swift test` --
22/22 passing. Went further than the unit suite too -- woodie ran `make
run` against the actual production Pi (already on `lambada-web` 2.0.0)
and confirmed the listing renders and downloads work end to end, *and*
separately confirmed the pre-rename Homebrew-installed `zouk` fails
gracefully (not a crash) against the renamed server, matching the
breaking-change caveat in the release notes.

Committed as `0d1337c` ("Rename /scans.json to /files.json; rename url
field to path"). `Resources/Info.plist`'s `CFBundleShortVersionString`
bumped `1.5` -> `1.6` (`CFBundleVersion` `5` -> `6`) in a separate commit,
tagged `v1.6.0` -- matching the `scandalous`/`lambada-web` side, which
bumped to `0.3.0`/`2.0.0` for the same change.

### A worse version of the `.git` lock gotcha (see lambada's `docs/COWORK.md` for the milder original)

Every git *write* run from the Cowork sandbox against this repo --
`git add`, `git commit`, even one that completes successfully -- leaves
behind a `.git/index.lock` (sometimes `HEAD.lock`, `maintenance.lock`,
`objects/tmp_obj_*`) that the sandbox cannot unlink
(`Operation not permitted`). That part was already known. What's new
here: the stuck lock isn't a sandbox-side illusion that clears once you
look from the Mac -- it's a real file on the real disk, and it blocks
**woodie's own native Terminal** too, not just the next sandboxed
command. `rm`-ing it from the Mac clears it, but only until the next
sandboxed git write recreates one. Mid-session this caused a tag
(`v1.6.0`) to land on the wrong commit: a `git add` that staged the
version bump successfully still left a lock behind that silently ate the
following `git commit`, so `git tag` tagged the rename commit instead of
the bump commit one step later. Fixed by deleting and re-creating the tag
once the bump commit actually existed.

**Working rule going forward, established this session**: once a lock
fight starts on a given repo, stop running *any* further git commands
against it from the sandbox -- hand the rest of the sequence to woodie's
own terminal entirely. Mixing sandboxed and native git commands on the
same repo in the same stretch is what causes the wrong-commit-tagged
problem above; an unbroken run from one side or the other doesn't.

## This session: evaluating a `productbuild` `.pkg` installer (issue #1)

[GitHub issue #1](https://github.com/woodie/zouk/issues/1), "Distrobution
with productbuild," proposed a `.pkg` installer for people who don't have
Homebrew. This was a planning/decision session only -- **no code, no git
commits, nothing exported or added to GitHub yet.**

Context that shaped the decision: woodie's actual hands-on experience
distributing to family was that Homebrew (which drags in Xcode CLT) was
overkill, and he ended up using a USB thumb drive with the unsigned
`make bundle` output instead (USB copy doesn't attach the quarantine
flag, so it just launches -- see "Gatekeeper / signing" below). A `.pkg`
doesn't fix a broken path -- the signed/notarized GitHub Release zip
already gets non-Homebrew users a no-warning install -- it's UX polish:
double-click -> Next -> Next -> Done reads as more familiar to
non-technical recipients than "unzip, drag to Applications." Decided
it's worth doing anyway, partly *because* it doubles as a dry run for a
second signing identity and a documented template for future projects
(same framing as the original code-signing work below).

Plan agreed on:
- New `make pkg` target: `productbuild --component .build/zouk.app
  /Applications --sign "Developer ID Installer: ..."`.
- A parallel notarize+staple step in `release.yml` for the `.pkg`
  (`notarytool` and `stapler` both take `.pkg` directly, same as the
  zip), with the signed installer attached to the GitHub Release
  alongside the existing zip -- so a tagged release ships both
  automatically.
- A **new Developer ID Installer certificate** -- a separate identity
  from the existing `Developer ID Application: John Woodell
  (754T277KBJ)` cert used for app signing; `productbuild --sign` doesn't
  accept the Application identity. New GitHub secrets
  (`INSTALLER_CERTIFICATE_P12_BASE64`, `INSTALLER_CERTIFICATE_PASSWORD`),
  reusing the existing `KEYCHAIN_PASSWORD`/`NOTARY_*` secrets since those
  are tied to the Apple ID, not the cert.
- Work happens on a branch (`1-productbuild-pkg`, so GitHub auto-links it
  to issue #1), not directly on `main` -- not because secrets are
  branch-scoped (they aren't; they're repo-wide regardless of which
  branch a workflow runs from), but because `release.yml` changes are
  exactly the kind of thing that only fails for real on a pushed tag, per
  the two real failures hit getting the *first* signing identity working
  on `v1.5.0` (see "Current state" above). A pre-release tag (e.g.
  `v1.7.0-rc1`) pushed from the branch can exercise the real
  sign/notarize/staple flow without touching the live Homebrew cask.
  Per the `.git` lock gotcha above, the actual branch/commit/tag commands
  should run from woodie's own terminal, not the sandbox.

**Status: done.** The cert-creation checklist above was completed and the
whole plan landed in a later session that never got a matching entry
here -- this paragraph is the belated write-up, reconstructed from the
actual state of the repo rather than from a session transcript, so
treat it as a correction to the stale "stopped before it started" note
that used to sit here. The Developer ID Installer cert exists, both
`INSTALLER_CERTIFICATE_P12_BASE64`/`INSTALLER_CERTIFICATE_PASSWORD`
secrets are on `woodie/zouk`, and `release.yml` imports both the
Application and Installer `.p12`s into the same CI keychain (plus
Apple's intermediate certs, needed because `pkgbuild --sign` -- unlike
`codesign` -- refuses to pick an identity unless its full chain
verifies locally). One real deviation from the plan above: the `make
pkg` target ended up using `pkgbuild --root ... --component-plist`
rather than `productbuild --component`, because the latter doesn't
expose `--component-plist`, which turned out to be required to force
`BundleIsVersionChecked` off (otherwise the Installer compares
`CFBundleVersion` against whatever's already on disk and silently
no-ops the copy if it isn't strictly newer -- see the `pkg` target's
comment in the `Makefile`). `release.yml` notarizes and staples the
`.pkg` directly (no zip-for-upload step needed, unlike the `.app`) and
`gh release create` attaches both the zip and the `.pkg` to the same
tagged release. README's "Direct download" section already documents
the `.pkg` as an alternative to Homebrew. Confirmed working for real on
`v1.8.0`: `release.yml` built, signed, and notarized both artifacts, and
its step summary printed valid sha256 checksums for both
`zouk-1.8.zip` and `zouk-1.8.pkg`.

`docs/in-progress.txt` (the raw chat transcript backup mentioned in an
earlier draft of this section) no longer exists -- already deleted once
this section was confirmed to cover the same ground.

## This session: delete support, a real code-signing crash fixed, and the wrong-commit-tag bug happening a second time

Three unrelated threads, tagged together as `v1.7.0`:

**Delete, matching a parity change made the same session on `lambada-web`/`scandalous`.** Both of those gained a RESTful `DELETE /download/:filename` (same resource path as the existing GET download, not a separate `/delete/:filename` route) plus a trash icon + `confirm()` on their web listings; zouk got the native equivalent. `ScanClient.delete(_:)` sends a real `DELETE` to `scan.path`. `ScanHTTPClient` grew a third method, `data(for request: URLRequest)`, since `delete(_:)` needs to set a method other than GET -- `FakeHTTPClient` picked up a matching `requestHandler`. `AppModel.delete(_:)` removes the scan from `scans` on success (no separate "deleted" message -- the scan vanishing from the grid *is* the confirmation, same as Finder) and flashes "Couldn't delete ..." via the existing `savingMessage` capsule on failure, deliberately not through `state` (which would swap the whole grid for the connectivity-error screen). `ScanGridView`'s footer grew a trash button (visible only when a scan is selected) wired to a native `.confirmationDialog`, worded to match the web listing's own confirm() text exactly on request: "Delete this scan from `<timeAgo>` ago?" -- which needed a new `ScanEntry.timeAgo` (`RelativeDateTimeFormatter`-based, trailing " ago" stripped so callers control it, mirroring lambada-web's own `timeAgo` template func).

**A real crash, root-caused and fixed**: `docs/crash.txt` is an actual `EXC_BAD_ACCESS`/`SIGKILL` "Code Signature Invalid" crash, hit ~60 seconds after launch inside AppKit's reopen-AppleEvent handling (the Dock-icon-click path). The tell: `codeSigningTeamID` in the report showed the real paid Developer ID team (`754T277KBJ`) even though `make run`/`make bundle` never invoke `codesign` at all -- meaning that exact `.build/zouk.app` path had previously held a properly-signed build (from an earlier `make sign`/`make package`), and a later `make run` overwrote the binary in place, quite possibly while a previous run of it was still live/mapped, corrupting the kernel's per-file code-signature validation for that vnode. Fixed in the `Makefile`: `run`'s `killall` now happens *before* `bundle` rebuilds the binary, not after, closing the window where a live process still has the old file mapped while it gets overwritten.

**The wrong-commit-tag bug (see "A worse version of the `.git` lock gotcha" above) happened again, for a different reason.** `v1.7.0` was first tagged and pushed from a local `main` that hadn't yet pulled the just-merged PR, so the tag landed on the pre-merge commit instead of the merge commit -- confirmed on GitHub's Actions list, which showed the triggered release run's commit as the old pre-merge SHA, not the merge commit. Manually re-running that Actions run would **not** have fixed it -- a re-run rebuilds from whatever commit originally triggered it, not whatever `main` currently points to. Fixed the same way as the `v1.6.0` incident: delete the GitHub Release, delete the tag (local and remote), `git pull` to make sure `main` is actually current, re-tag, re-push. Given this is now a repeat (different root cause than the lock issue last time, same symptom), `docs/DELIVERY.md`'s pre-flight checklist has an explicit `git log -1` verification step now -- see there.

## This session: `timeAgo` sub-30-second parity bug, and a right-click context menu (issue #4)

**`timeAgo` bucketing bug, found via woodie's own use**: deleting a scan seconds after it arrived showed "Delete this scan from 15 seconds ago?" in zouk, where scandalous/lambada-web both show "less than a minute ago?" for the same age. Root cause: `RelativeDateTimeFormatter` has no "less than a minute" bucket of its own -- it reports literal seconds for anything under a minute, unlike Rails' `time_ago_in_words` (without `include_seconds:`, sub-30-second durations collapse to one "less than a minute" bucket) or `justincampbell/timeago`'s own `seconds < 30` cutoff. Fixed with an explicit `< 30` second clamp in `ScanEntry.timeAgo`, and split `timeAgo` into a computed property (real clock) plus a `timeAgo(relativeTo:)` method so a spec can pin a fixed `now` -- see `ScanEntrySpec`'s `#timeAgo(relativeTo:)` block (15s clamped, 29s boundary clamped, 30s no longer clamped). `scandalous`/`lambada-web` picked up their own fix alongside this: neither suite had actually proved the delete-confirmation *dialog* text before, only the listing's `<span>`, since the real confirm() sentence was assembled by client-side JS their test suites never execute -- both templates now build the full sentence server-side so the exact dialog text is directly assertable.

**Right-click context menu (issue #4)**: reintroduces right-click on `ScanThumbnailCell` with four items -- Download and Open (`AppModel.open(_:)`, same as double-click), Download to… (new `downloadWithoutOpening(_:)`, same Save panel minus the NSWorkspace hand-off), Fast Download (new `fastDownload(_:)`, no panel at all, always lands in ~/Downloads under the scan's own name, silently overwriting same as the panel path already does), and Move to Trash (hands the scan to `ScanGridView`'s existing `confirmingDelete` dialog via a new `requestDelete` closure rather than duplicating that wiring). `open(_:)`'s old body split into `saveViaPanel(_:thenOpen:)` / `save(_:to:thenOpen:)`, shared by all three download paths. This reverses the "Single gesture, no context menu" call from earlier in this doc (see "Design conventions" below) -- that call was right for the problem at the time (a right-click Save-As duplicating double-click exactly), but issue #4 asks for a genuinely different set of actions, so the old reasoning doesn't actually apply here. Not unit-tested at the `AppModel` level, consistent with `open(_:)`/`delete(_:)` never having been: the new methods either need a live `NSSavePanel.runModal()` or a way to inject a fake `client` into `AppModel` that doesn't exist today -- the actual file-write logic they all call through (`ScanClient.save(_:to:cacheDirectory:)`) is already covered by `ScanClientSpec`. Made by inspection only per the sandbox limitation above -- confirmed via `make test`/`make run` on woodie's Mac (29/29 specs), plus manually right-clicking a scan, which caught two things inspection alone missed: the menu items needed explicit `Label(_:systemImage:)` icons (a plain `Button("title")` renders text-only in a context menu -- `arrow.up.right.square` / `icloud.and.arrow.down` / `arrow.down.circle.fill` / `trash`), and setting `confirmingDelete` synchronously from the "Move to Trash" action never presented the dialog -- the NSMenu-backed context menu is still tearing down at that point, so the state change needs to go through `Task { @MainActor in ... }` to land a beat later once that's done. The footer's own trash button doesn't need this since it was never inside a context menu to begin with.

## This session: comment retrofit, `ScanFetching` test seam, and `justBeforeEach`

**Comments moved out of source, into `docs/COMMENTS.md`.** Every
`Sources/ZoukKit` and `Tests/ZoukKitTests` file was stripped of
multi-line/rationale comments, cataloged in a new `docs/COMMENTS.md`
(organized by file, then by symbol), with at most one self-contained
line left in source where a real gotcha still needed a pointer right
there (e.g. `ScanEntry.timeAgo(relativeTo:)`'s `// Emulate
DateHelper.time_ago_in_words()`). None of those one-liners say "see
docs/COMMENTS.md" -- that file is treated as expected reading, the same
way this one already is. See "Comment convention" below for the rule
going forward.

**Four test gaps found and filled**, by cross-referencing
`docs/COMMENTS.md` against the existing specs for logic/workarounds
that had rationale documented but no test proving it:
- `ScanEntry.timeAgo(relativeTo:)`'s future-date branch (`ScanEntrySpec`,
  "one day earlier" -- asserts `"in 1 day"`, not a stripped `" ago"`
  that was never there).
- `ScanClient.uniqueDestination(for:in:)` (`ScanClientSpec`, three
  nested contexts: name free, name taken once, taken twice).
- `ExtensionEnforcingPanelDelegate` (new
  `ExtensionEnforcingPanelDelegateSpec.swift`) -- required dropping
  `private` off the `final class` declaration in `AppModel.swift` so
  `@testable import ZoukKit` can reach it; still not exported (no
  `public`).
- `AppModel.delete(_:)` -- needed an actual test seam since `AppModel`
  is `final` (no subclassing) and `ScanClient` is a concrete `actor`
  (nothing to fake without an abstraction one layer up, mirroring how
  `ScanHTTPClient` already abstracts `URLSession` for `ScanClient`'s own
  tests). Added `protocol ScanFetching: Sendable` (the four methods
  `AppModel` actually calls), `extension ScanClient: ScanFetching {}`,
  and a new `Tests/ZoukKitTests/FakeScanClient.swift`. `AppModel.client`
  is now `(any ScanFetching)?` instead of `ScanClient?`. The public
  initializer became a `convenience init` delegating to a new internal
  designated `init(..., client: (any ScanFetching)?)` -- `client`
  deliberately has no default value, since a defaulted one would make
  `AppModel()` ambiguous between the two initializers.

**`justBeforeEach` adopted for shared "act" steps.** Quick's
`justBeforeEach` (guaranteed to run after every `beforeEach` at any
nesting depth, immediately before the `it`) is the closest equivalent
Quick has to RSpec's `subject {}` -- there's no per-example lazy
re-evaluation the way RSpec gets from Ruby's dynamic per-context
subclassing, but for a single shared action call this gets the same DRY
effect. Applied wherever the exact same action line was duplicated
across sibling `beforeEach`/`it` blocks, differing only in what a
`context` set up beforehand: `ExtensionEnforcingPanelDelegateSpec`'s
`#panel(_:userEnteredFilename:confirmed:)`, `AppModelSpec`'s
`#delete(_:)`, and `ScanClientSpec`'s `#uniqueDestination(for:in:)` /
`#cachedFile(for:in:)` / `#save(_:to:cacheDirectory:)`. Each `context`'s
own `beforeEach` now sets up only what varies (a handler, a
pre-existing file, an input value); every `it` is a bare assertion.

Made by inspection only per the sandbox limitation above; confirmed via
a real `make test` on woodie's Mac -- 42/42 specs pass.

## This session: adopted `humane-swift`, dropping the hand-rolled `humanSize`/`timeAgo`

`ScanEntry.humanSize` and `timeAgo(relativeTo:)` had been directly wrapping
`ByteCountFormatter`/`RelativeDateTimeFormatter` in this file, including a
manually bolted-on `< 30`-second "less than a minute ago" clamp and (added
this same session, before this entry) an "about"-prefix prototype for
hour-plus buckets. Both are now `github.com/woodie/humane-swift`'s job:
`ScanEntry.humanSize` calls `Humane.SizeFormatter().string(fromByteCount:)`,
`timeAgo(relativeTo:)` calls `Humane.TimeFormatter(approximate:
true).string(for:relativeTo:)`. This incidentally fixes a real drift bug --
the hand-rolled clamp used 30 seconds, `humane`/`humane-ruby`'s actual
default (and `humane-swift`'s `includeSeconds: false`) is 60 -- so anything
30-59 seconds old now reads "less than a minute ago" instead of showing
exact seconds, matching the other two languages for the first time.

`Package.swift` points at `humane-swift` via `.package(path: "../humane-swift")`
-- a local sibling-directory dependency, not a version pin, since
`humane-swift` is tested (28/28 on real hardware) but its `v0.1.0` tag
hasn't been pushed yet. Switch to `.package(url:
"https://github.com/woodie/humane-swift.git", from: "0.1.0")` once it has --
see `humane-swift/docs/COWORK.md` for that repo's own state. No
`ScanEntrySpec.swift` changes were needed: none of its existing fixtures
land in the 30-59-second gap the threshold fix affects.

Made by inspection only per the sandbox limitation above; confirmed via a
real `make test` on woodie's Mac -- 46/46 specs pass. Not exercised via
`make run` against a live `lambada` server this round -- deliberately
scoped to the automated suite; revisit with a live pass if `humane-swift`
behavior is ever in question beyond what the specs cover.

## Next up

`humane-swift` integration confirmed (46/46, see above). Once `humane-swift`'s
`v0.1.0` is tagged and pushed (its own `docs/COWORK.md` has the status),
switch `Package.swift`'s dependency from `path:` to a `from: "0.1.0"` version
pin.

Otherwise nothing else pending as of `v1.8.0`. This section used to list
three items -- a README line on *why* zouk exists, a README line on *who
it's for*, and resuming the Developer ID Installer cert walkthrough -- all
three turned out to already be done (README's intro paragraph covers the
first two almost verbatim; the Installer cert/`.pkg` work is covered in
"This session: evaluating a `productbuild` `.pkg` installer" above), just
never recorded here at the time. Cleaned up rather than left stale.

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
- **Click/double-click, plus a right-click menu (superseded, see issue
  #4 below)**: single-click (select) and double-click (`open(_:)`)
  remain on `ScanThumbnailCell`, given explicit precedence with
  `TapGesture(count: 2).exclusively(before: TapGesture(count: 1))`
  rather than two independent `onTapGesture` modifiers. This project
  previously removed a right-click/long-press Save-As variant
  (`AppModel.saveAs(_:)` + `ScanGridView.RightClickCatcher`) once
  double-click absorbed the same panel-then-open behavior, reasoning
  that a second gesture for the identical action cut against
  "simplify." Issue #4 reintroduced right-click anyway, but with a
  genuinely different set of actions (not a duplicate) -- see "This
  session" below.

## macOS quirks worth knowing before debugging "it doesn't connect"

- **Local Network Privacy**: the *first* request to a private/LAN IP
  triggers a system "Allow 'zouk' to find devices on local networks?"
  dialog. The in-flight request usually fails/times out while that
  dialog is pending, regardless of which button gets pressed -- this
  looks like a bug but isn't one. Retrying after the permission is
  granted works. `Info.plist` now sets `NSLocalNetworkUsageDescription`
  so the dialog shows zouk-specific text instead of Apple's generic
  boilerplate.
- **Gatekeeper / signing**: the release path (`brew install --cask
  zouk` / GitHub Release zip) is signed with a real Developer ID and
  notarized -- no Gatekeeper warning at all, verified via `spctl -a -vv`
  (see "Current state" above). A local `make bundle` hand-off to a
  family member without Xcode is still unsigned (Apple Silicon's
  automatic ad-hoc linker signature only) -- the quarantine flag only
  gets attached by quarantine-aware transfer methods (AirDrop, Mail,
  browser download), not USB/local-network copy or `scp`. On current
  macOS, the override path for that unsigned case is System Settings →
  Privacy & Security → "Open Anyway" (the old right-click bypass is
  gone). Details in `docs/DELIVERY.md`.

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

## Comment convention (established this session)

Explanatory comments -- anything that would otherwise be a multi-line
`///` doc comment or a multi-line `//` note -- live in `docs/COMMENTS.md`
instead, organized by file and then by the type/property/function they're
about. Source keeps at most one short line at any given spot, and only
where the code genuinely needs a pointer right there (a real gotcha, not
general documentation); that line doesn't need to say "see
docs/COMMENTS.md" -- treat that file as expected reading alongside the
code, the same way `docs/COWORK.md` itself already is. Don't reintroduce
multi-line comment blocks in Swift files going forward: a one-liner in
code if it's truly needed, anything longer goes in `docs/COMMENTS.md`
under a heading for the relevant file/symbol.

## Layout

- `Sources/ZoukKit` -- model (`AppModel`), networking (`ScanClient`),
  data (`ScanEntry`), and views (`ContentView`, `HostEntryView`,
  `ScanGridView`). Library target so `Tests/ZoukKitTests` can
  `@testable import` it.
- `Sources/zouk` -- thin `@main` entry point.
- `Tests/ZoukKitTests` -- Quick/Nimble specs organized by public method
  rather than by scenario: `ScanEntrySpec` (`Decodable`, `#formattedSize`,
  `#downloadedAt`/`#formattedDate`, `#timeAgo(relativeTo:)`),
  `ScanClientSpec` (`#fetchScans()`, `#cachedFile(for:in:)`,
  `#delete(_:)`, `#save(_:to:cacheDirectory:)`,
  `#uniqueDestination(for:in:)`, via the fake `ScanHTTPClient` in
  `FakeHTTPClient.swift` instead of the real network), `AppModelSpec`
  (`.baseURL(fromHostInput:)`, `#toggle(_:)`, `#changeServer()`,
  `#requestDelete(_:)`, `#delete(_:)`, via the fake `ScanFetching` in
  `FakeScanClient.swift` instead of a real `ScanClient`), and
  `ExtensionEnforcingPanelDelegateSpec`
  (`#panel(_:userEnteredFilename:confirmed:)`). Deliberately no tests for
  the SwiftUI views (`ContentView`, `HostEntryView`, `ScanGridView`,
  `ConnectingView`, `RunningDogView`) -- this is a small, single-developer
  app and the model/networking/data-layer coverage above is judged
  sufficient; view regressions get caught by eye via `make run`, not by
  an automated suite. Revisit (e.g. snapshot testing or ViewInspector)
  only if that stops being true.
- `docs/DELIVERY.md` -- how to cut and hand off a build.
- `docs/COMMENTS.md` -- rationale/history extracted from source comments;
  see "Comment convention" above.
- `docs/COWORK.md` -- this file.
- `.github/workflows/CI.yml` -- runs `make build`/`make test` on macOS
  for every push/PR to `main`.
- `LICENSE` -- MIT.
