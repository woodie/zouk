# Delivering a zouk build

There are two ways to ship a build: tag a release, which `.github/
workflows/release.yml` turns into a zipped `.app` on a GitHub Release
(and what the `woodie/homebrew-zouk` cask installs from); or run `make
bundle` (or `make run`) on your own Mac and hand the resulting `.app`
straight to a family member without Xcode. Either way it's the same
unsigned binary -- this doc covers what that actually means and what the
other person needs to do to run it.

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

Depends entirely on how the `.app` travels there, not on anything you do
in Xcode:

- **USB drive, local network copy, `scp`** -- no quarantine flag gets
  attached, so it should just launch normally.
- **AirDrop, Messages, Mail, a browser download, Slack, `brew install
  --cask zouk`, etc.** -- any quarantine-aware transfer flags the file
  (Homebrew Cask quarantines downloads by default), and macOS blocks the
  first launch with "Apple could not verify this app is free of
  malware." `brew install --cask zouk --no-quarantine` skips this.

## Getting past Gatekeeper (no Xcode needed)

If the recipient hits the blocked-launch dialog, the old right-click ->
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

## If we ever need a "no warning at all" install

That requires actually paying for it: a **Developer ID Application**
certificate (Apple Developer Program, $99/year), then signing,
`xcrun notarytool submit`, and `xcrun stapler staple` before
distributing. Worth revisiting if zouk ever goes beyond a handful of
family installs -- overkill for v0.1.0.

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
