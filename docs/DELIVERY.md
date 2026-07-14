# Delivering a zouk build

There are two ways to ship a build: tag a release, which `.github/
workflows/release.yml` builds, **signs, and notarizes**, then attaches
the zipped `.app` to a GitHub Release (and what the `woodie/homebrew-zouk`
cask installs from); or run `make bundle` (or `make run`) on your own Mac
and hand the resulting `.app` straight to a family member without Xcode.
These are **not** the same binary -- the tagged-release path is signed
with a real Developer ID and notarized by Apple, so it installs with no
Gatekeeper warning at all. A local `make bundle` is unsigned (ad-hoc only)
and still hits Gatekeeper if it travels by a quarantine-aware route. This
doc covers both paths.

## What `make bundle` produces

```
make bundle
```

runs `swift build --configuration release` and copies the resulting
executable into a hand-assembled `.build/zouk.app/Contents/MacOS/zouk`
alongside `Resources/Info.plist`. There is **no `codesign` or
notarization step anywhere in the build** -- check the `Makefile` and
you won't find one.

On Apple Silicon, the linker still stamps the binary with an **ad-hoc
signature** automatically (the OS requires *some* signature just to
execute arm64 code at all). That's not the same thing as a Developer ID
signature, and it carries no weight with Gatekeeper on a different Mac.

## Will it run on someone else's Mac?

Depends on which build you're handing off:

- **`brew install --cask zouk` (or any GitHub Release zip)** -- this is
  the signed + notarized build. It launches with no blocking warning;
  the only thing macOS shows is the routine one-time "downloaded from
  the Internet... Apple checked it for malicious software and none was
  detected" notice, which has a normal Open button. Verify any copy with
  `spctl -a -vv /Applications/zouk.app` -- it should say `accepted`,
  `source=Notarized Developer ID`.
- **A local `make bundle`/`make run` build, handed off directly** -- this
  is unsigned (ad-hoc signature only). Whether it hits Gatekeeper depends
  on how it travels:
  - **USB drive, local network copy, `scp`** -- no quarantine flag gets
    attached, so it should just launch normally.
  - **AirDrop, Messages, Mail, a browser download, Slack, etc.** -- any
    quarantine-aware transfer flags the file, and macOS blocks the first
    launch with "Apple could not verify this app is free of malware."

## Getting past Gatekeeper (no Xcode needed)

This only applies to the unsigned `make bundle` hand-off path above --
the signed/notarized `brew install`/GitHub Release build doesn't hit
this dialog. If the recipient hits the blocked-launch dialog, the old
right-click ->
"Open" trick no longer exists as of macOS Sequoia. The current flow:

1. Try to open the app once (it'll be blocked).
2. Open **System Settings -> Privacy & Security**, scroll down to the
   blocked-app notice, click **Open Anyway**, and authenticate as an
   admin.
3. That "Open Anyway" option stays available for about an hour after
   step 1 -- if it's gone, just try opening the app again to re-trigger
   it.
4. After that one-time override, the app opens normally on future
   double-clicks.

No Xcode signing is required for this path. It's the right call for
handing a build to one or two family members.

## The "no warning at all" install

Done, as of v1.5.0: a paid **Developer ID Application** certificate
(John Woodell, team `754T277KBJ`) signs the build in CI (`make sign`,
`--options runtime --timestamp`), then `.github/workflows/release.yml`
runs `xcrun notarytool submit --wait` and `xcrun stapler staple` before
the zip is attached to the GitHub Release. Confirmed end-to-end via
`brew install --cask zouk` followed by `spctl -a -vv /Applications/zouk.app`
-> `accepted` / `source=Notarized Developer ID` / `origin=Developer ID
Application: John Woodell (754T277KBJ)`.

The signing identity, six related GitHub secrets
(`CERTIFICATE_P12_BASE64`, `CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`,
`NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID`), and the
`.p12` backup locations are documented in `docs/COWORK.md`.

## The `.pkg` installer

Every tagged release also ships a signed, notarized, stapled `.pkg`
alongside the zip -- `make pkg` (via a separate **Developer ID
Installer** identity, distinct from the Application identity above;
`pkgbuild --sign` doesn't accept the Application cert) plus two more
GitHub secrets (`INSTALLER_CERTIFICATE_P12_BASE64`,
`INSTALLER_CERTIFICATE_PASSWORD`), reusing `KEYCHAIN_PASSWORD`/
`NOTARY_*` since those are tied to the Apple ID, not the cert. This is
UX polish for non-technical recipients, not a Gatekeeper fix -- the
signed/notarized zip already installs with no warning -- double-click ->
Next -> Next -> Done just reads as more familiar than "unzip, drag to
Applications." `release.yml`'s "Compute checksum" step prints a sha256
for both artifacts; only the zip's is what the automated cask bump below
sends on to `woodie/homebrew-zouk`'s `Casks/zouk.rb` -- the `.pkg`'s
checksum is informational only (`gh release create` attaches the `.pkg`
itself directly to the release, nothing else consumes its checksum). See
`docs/COWORK.md`'s "evaluating a `productbuild` `.pkg` installer"
section for how this was built and why `pkgbuild` (not `productbuild`)
ended up being the right call.

## Pre-flight checklist for cutting a release

- [ ] Commit and push all changes (`git status` should be clean).
- [ ] `make build && make test` pass on macOS.
- [ ] `make bundle`, smoke-test the resulting `.app` locally.
- [ ] Bump `Resources/Info.plist`'s `CFBundleShortVersionString` to the
      new version -- `make package`'s zip name (and the cask's `url`
      template) is derived from this value, so it has to match the tag
      below or the release workflow ships a zip the cask can't find.
- [ ] `git checkout main && git pull`, then **`git log -1` right before
      tagging** and actually read the commit it shows. This has bitten a
      release twice now (see `docs/COWORK.md`'s `v1.6.0`/`v1.7.0`
      incidents): tagging from a local `main` that hasn't pulled a
      just-merged PR puts the tag on the pre-merge commit instead, and
      `release.yml` then builds and ships *that* -- silently missing
      whatever the merge added. Re-running the resulting Actions run does
      **not** fix this; a re-run rebuilds from whatever commit originally
      triggered it. The fix, if it happens anyway: delete the GitHub
      Release, delete the tag (local and remote), pull for real, re-tag,
      re-push.
- [ ] Write `docs/releases/vX.Y.Z.md` (see existing files for the
      template) and commit it -- `release.yml`'s "Publish release" step
      reads this file via `--notes-file` instead of auto-generating notes
      from the commit log, the same convention `humane`/`humane-ruby`/
      `humane-swift` already use. It has to exist *before* the tag is
      pushed: tagging triggers the workflow immediately, so there's no
      manual step afterward to attach notes with. If it's missing, the
      "Publish release" step fails outright rather than silently falling
      back to generated notes -- that's on purpose, not a bug to work
      around.
- [ ] Tag the release (annotated, `vX.Y.Z`; see existing tags for style)
      and push the tag -- this triggers `.github/workflows/release.yml`,
      which builds, zips, and attaches the `.app` to a GitHub Release.
- [ ] Once that run finishes, its `trigger-homebrew-bump` job fires a
      `repository_dispatch` to `woodie/homebrew-zouk` carrying the tag,
      short version, and sha256 -- that repo's `bump-cask.yml` workflow
      rewrites `Casks/zouk.rb`, commits, pushes, tags, and publishes a
      release automatically. Nothing to copy by hand; just check that
      `homebrew-zouk`'s Actions tab shows a green "Bump cask" run.
- [ ] For a non-brew hand-off instead: hand off the `.app` directly, and
      if the recipient hits Gatekeeper, point them at the "Getting past
      Gatekeeper" steps above.
