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

## Pre-flight checklist for cutting a release

- [ ] Commit and push all changes (`git status` should be clean).
- [ ] `make build && make test` pass on macOS.
- [ ] `make bundle`, smoke-test the resulting `.app` locally.
- [ ] Bump `Resources/Info.plist`'s `CFBundleShortVersionString` to the
      new version -- `make package`'s zip name (and the cask's `url`
      template) is derived from this value, so it has to match the tag
      below or the release workflow ships a zip the cask can't find.
- [ ] Tag the release (annotated, `vX.Y.Z`; see existing tags for style)
      and push the tag -- this triggers `.github/workflows/release.yml`,
      which builds, zips, and attaches the `.app` to a GitHub Release.
- [ ] Once that run finishes, copy the sha256 from its "sha256 for the
      Homebrew cask" step summary into `woodie/homebrew-zouk`'s
      `Casks/zouk.rb` (`version` and `sha256`), commit, and push.
- [ ] For a non-brew hand-off instead: hand off the `.app` directly, and
      if the recipient hits Gatekeeper, point them at the "Getting past
      Gatekeeper" steps above.
