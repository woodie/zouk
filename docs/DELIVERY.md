# Delivering a zouk build

zouk has no CI/release pipeline yet -- "shipping" a build today means
running `make bundle` (or `make run`) on your own Mac and handing the
resulting `.app` to a family member without Xcode. This doc covers what
that binary actually is and what the other person needs to do to run it.

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
- **AirDrop, Messages, Mail, a browser download, Slack, etc.** -- any
  quarantine-aware transfer flags the file, and macOS blocks the first
  launch with "Apple could not verify this app is free of malware."

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
- [ ] Tag the release (no tags exist yet -- `v0.1.0` would be the first).
- [ ] Hand off the `.app` and, if the recipient hits Gatekeeper, point
      them at the "Getting past Gatekeeper" steps above.
