# Comments

Rationale, history, and design notes that used to live as multi-line
comments in the source. Organized by file, then by the type, property, or
function each note is attached to. The source itself now carries at most
one short line at any given spot -- anything longer that would previously
have been a `///` doc comment or a multi-line `//` note lives here instead.
When a code location kept its own one-line comment, it's noted below so
this stays a complete map of "why," not a duplicate of what's already
readable in the file.

## Sources/ZoukKit/AppIconImage.swift

### `AppIcon` (enum)
The app's icon artwork, loaded directly from the package bundle so it
renders identically in every run mode (`swift run`, `make run`, Xcode)
instead of depending on the hand-assembled `.app` bundle's Info.plist /
`Contents/Resources/AppIcon.icns` the way `NSApp.applicationIconImage`
would on its own. `public` because `ZoukApp.swift` (the `zouk` executable
target, a separate module) also needs it to set the Dock icon at launch.

### `AppIconImage` (struct)
SwiftUI wrapper around `AppIcon.nsImage`, for dropping the icon into a
view hierarchy -- currently just `HostEntryView`'s connect screen. Clips
to a rounded square -- macOS already auto-masks the Dock/.icns icon into
that same "squircle" shape since Big Sur, so this just matches that
native app-icon look wherever the art shows up inside the UI itself,
where nothing clips it for us. (The native About panel, shown via
`NSApplication.orderFrontStandardAboutPanel` in `ZoukApp.swift`, gets its
icon straight from `NSApp.applicationIconImage` instead.) The corner
radius is computed from whatever size the call site frames this view at
(via `GeometryReader`) rather than a fixed point value, so it stays
proportionally correct at any size used later -- matching the ~22% of
width Apple uses for its own app icon corner radius.

### `AppIconImage.content`, else branch
Kept a one-line comment in place: "AppIcon.png ships with the package;
this is just a defensive fallback." Should never actually trigger --
`Resources/AppIcon.png` ships with the package -- but falls back to an
SF Symbol rather than a blank space if it's ever missing.

## Sources/ZoukKit/AppModel.swift

### `AppModel` (class)
Drives the whole app: remembers the last host the user typed in, opens
the host-entry screen until a connection succeeds, then holds the scan
listing and handles thumbnailing/downloading.

### `AppModel.selectedScanID`
The single scan currently highlighted by a click (Finder-style: click to
select and show details, double-click to download).

### `AppModel.savingMessage`
Transient overlay text shown while `open(_:)` is actively saving a file,
e.g. "Saving 1782420815.pdf...", cleared the moment that finishes
(success or failure) -- it's a quick heads-up mid-save, not the
confirmation. Also reused by `delete(_:)` for a brief "Couldn't delete
..." flash on failure (a successful delete needs no message here -- the
scan just vanishing from the grid is the confirmation).

### `AppModel.savedMessage`
Persistent footer text confirming the *last* file `open(_:)` saved, e.g.
"File 1782420815.pdf saved." Deliberately silent on *where* -- the
destination is whatever the user picked in the Save panel, which they
just saw and chose themselves, so naming it again here isn't useful the
way "...saved to Downloads" was back when Downloads was the only
possible destination. Unlike `savingMessage`, this doesn't auto-clear on
a timer -- it replaces the footer's usual scan-count/selection text and
stays there until the user selects a scan (`toggle`, which swaps it for
that scan's stats) or double-clicks another one (`open`, which clears it
before starting the next save). A capsule that vanished after a second
was too easy to miss; this sticks around until something else clearly
needs the footer instead.

### `AppModel.pendingDelete`
Non-nil while the footer's delete confirmation should be up, for
whichever scan it's about. Only `requestDelete(_:)` (the footer's trash
button) sets this -- the right-click "Move to Trash" item skips
confirmation entirely and calls `delete(_:)` directly, so it never
touches this property. `ScanGridView`'s `.confirmationDialog` binds its
presentation to this being non-nil, and only calls `delete(_:)` once the
user actually taps "Delete" in it.

### `AppModel.minimumConnectingDuration`
`ConnectingView` (the running-dog screen) stays up at least this long
once we've started attempting a connection, even if the network
round-trip itself finishes much faster -- reconnecting to a saved host
over a local network can resolve in a handful of milliseconds, which
would otherwise skip right past it. Real, slower connections just take
however long they take; this only ever adds time, never caps it.

### `AppModel.connect()`, catch block
Any failure to connect -- whether this is the very first attempt or a
reload from an already-open grid -- just bounces back to `HostEntryView`
rather than showing an error in place, so there's only ever one
"something's wrong" screen.

### `AppModel.toggle(_:)`
Single click: select/deselect for the info footer. Clicking the
already-selected scan again deselects it. Selecting also clears any
lingering "saved" footer message from a previous `open(_:)` -- the
footer can only show one thing at a time, and a fresh selection is the
more useful thing to show.

### `AppModel.open(_:)`
Double-click, and the right-click "Download and Open" item (issue #4):
Save panel, then hands the result to `NSWorkspace`.

### `AppModel.downloadWithoutOpening(_:)`
Right-click "Download to..." (issue #4): same Save panel as `open(_:)`,
but never hands the result to `NSWorkspace` afterward.

### `AppModel.fastDownload(_:)`
Right-click "Fast Download" (issue #4): no panel at all, always lands in
~/Downloads, no open. Unlike the panel-based paths (which get a "replace
this file?" alert from `NSSavePanel` itself), there's no panel here to
ask that question, so this goes through `ScanClient.uniqueDestination(for:in:)`
for the same Finder-style de-dup naming used elsewhere: "scan.pdf" a
second time lands at "scan (1).pdf" instead of silently overwriting the
first one.

### `AppModel.saveViaPanel(_:thenOpen:)`
Shows a Save panel pre-filled with `scan.name` and ~/Downloads,
selecting the scan unconditionally first so a cancelled panel still
leaves it selected rather than clearing the footer for nothing. The
saved copy always keeps the scan's own extension -- enforced by
`ExtensionEnforcingPanelDelegate` rather than `panel.allowedContentTypes`,
which *appends* its required extension instead of replacing a
mismatched one ("foobar.zip" would become "foobar.zip.pdf", not
"foobar.pdf").

Kept a one-line comment on `extensionDelegate`: "Held here because
NSSavePanel.delegate is weak; a local strong ref keeps it alive through
runModal()."

### `AppModel.save(_:to:thenOpen:)`
Shared save step for all three download paths: shows `savingMessage`
while in flight, then swaps that for the persistent `savedMessage` once
the file's on disk (and handed to `NSWorkspace`, when `thenOpen`).

### `AppModel.requestDelete(_:)`
Selects `scan` and arms the delete confirmation (`pendingDelete`) for it.
Only the footer's trash button calls this -- the right-click "Move to
Trash" item deliberately skips confirmation entirely and calls
`delete(_:)` straight away (see `ScanThumbnailCell`): picking an item
from an explicit context menu is already the deliberate action Finder's
own confirmation dialogs exist to guard against for a stray click, so a
second gate here would just be friction. The footer's single-click trash
icon doesn't have that same "I clearly meant to do this" quality, so it
keeps the confirmation.

### `AppModel.delete(_:)`
Deletes `scan` from the server (DELETE on the same path GET uses to
download it -- see `ScanClient.delete(_:)`) and, on success, removes it
from `scans`, clearing the selection if it was the one selected. The
scan vanishing from the grid *is* the confirmation, the same way Finder
just removes a deleted item rather than popping a separate "deleted"
toast. On failure, this reuses the `savingMessage` overlay capsule for a
brief "Couldn't delete ..." flash rather than routing through `state`:
`state = .failed(...)` would swap the whole grid for the
connectivity-error screen (see `ScanGridView.content`), which isn't the
right response to a delete that failed on an otherwise-working
connection. Called two ways: directly from the right-click "Move to
Trash" item (no confirmation), or from `ScanGridView`'s confirmation
dialog once the user taps "Delete" there (footer trash button path) --
see `requestDelete(_:)` above.

### `AppModel.baseURL(fromHostInput:)`
Pure, `nonisolated` so it's easy to unit test: prepends "http://" when
the user didn't type a scheme, trims whitespace, rejects empty input.

### `ExtensionEnforcingPanelDelegate` (class)
Forces whatever filename ends up confirmed in an `NSSavePanel` to always
end in `requiredExtension`, by stripping any extension the user actually
typed (if any) and appending the required one in its place -- once,
never twice. Exists because `NSSavePanel.allowedContentTypes` doesn't do
this on its own: when the typed extension doesn't match, it appends its
required extension to the end rather than replacing the mismatched one,
so "foobar.zip" becomes "foobar.zip.pdf" instead of "foobar.pdf".

### `ExtensionEnforcingPanelDelegate.panel(_:userEnteredFilename:confirmed:)`
Kept a one-line comment in place: "okFlag is false while typing; only
rewrite once the user has actually committed to this name."

## Sources/ZoukKit/ConnectingView.swift

### `ConnectingView` (struct)
Shown while `AppModel.connect()` is in flight -- the automatic reconnect
attempt on launch and a manual retry both pass through here -- so
there's something more alive on screen than a static form while we wait
on the network.

## Sources/ZoukKit/ContentView.swift

### `ContentView.model`
Property-initializer form (not a default argument on a custom init) so
`AppModel()`, a `@MainActor` type, is constructed the same way every
other SwiftUI `@StateObject` view model is -- the pattern Swift's
actor-isolation checker is tuned to accept without a custom init having
to itself be `@MainActor`.

### `ContentView.body`, connecting branch
Checked before `hasEverConnected` so the running-dog screen covers every
in-flight `connect()` call -- the initial attempt, a reload of the
current host, and switching to a brand-new host typed into
`ScanGridView`'s address bar -- not just the very first connection
before anything has ever succeeded.

### `ContentView.body`, `.frame` modifier
Open small like Finder does for a network share with a handful of items
in it -- `idealWidth`/`idealHeight` (not just min) is what
`.windowResizability(.contentSize)` actually uses to size the window on
first launch, so without them the window defaults to something much
larger than the content needs.

## Sources/ZoukKit/HostEntryView.swift

### `HostEntryView` (struct)
First screen the user sees, and the one they come back to whenever a
connect attempt fails (`ContentView` routes there any time `AppModel`
isn't connected and isn't actively connecting -- see `ConnectingView`
for the in-flight state). Remembers the last host: `AppModel` persists
it to `UserDefaults` on successful connect and prefills it here next
launch.

## Sources/ZoukKit/ResourceBundle.swift

### `ZoukResources` (enum)
Kept a one-line comment in place: "Looks in Contents/Resources first
(required once signed); falls back to Bundle.module for swift
run/test/Xcode."

Full history: resolves ZoukKit's resource bundle (icon art, the
running-dog GIF). Looks in `Contents/Resources` first, via
`Bundle.main.resourceURL` -- the conventional macOS location, and the
*only* one `codesign` permits once the app is actually signed. Putting
anything outside `Contents/` (which an earlier fix did, to work around
the SwiftPM-generated `Bundle.module` accessor never checking
`resourceURL`) makes `codesign --sign` fail outright with "unsealed
contents present in the bundle root" -- not just a notarization-time
rejection, a hard signing error. Falls back to `Bundle.module` for
`swift run`/`swift test`/Xcode, where `Bundle.main` isn't a real `.app`
and `resourceURL` won't point anywhere useful -- that's the one context
where touching the generated accessor is still safe (and necessary).

## Sources/ZoukKit/RunningDogView.swift

### `RunningDogAnimation` (enum)
Frame-by-frame playback of `RunningDog.gif` (an 8-frame run cycle,
already flipped to face left). ImageIO decodes the GIF directly so we
don't need to ship a separate PNG per frame or pull in a third-party
GIF-rendering dependency just to animate eight small images.

### `RunningDogAnimation.frameInterval`
Matches the source GIF's 100ms-per-frame timing rather than reading it
back out of the file's per-frame metadata -- all eight frames share the
same duration, so there's nothing per-frame to preserve.

### `RunningDogView` (struct)
Loops `RunningDogAnimation.frames` on a timer. Falls back to the plain
(static) app icon if the GIF somehow failed to decode, so
`ConnectingView` always has something to show.

## Sources/ZoukKit/ScanClient.swift

### `ScanHTTPClient` (protocol)
Just the three `URLSession` calls `ScanClient` needs, as a protocol so
tests can inject a fake instead of hitting the real network (see
`FakeHTTPClient` in ZoukKitTests). `data(for:)` is the odd one out -- it
takes a `URLRequest` rather than a bare `URL`, since `delete(_:)` needs
to set an HTTP method other than GET.

### `extension URLSession: ScanHTTPClient`
Kept a one-line comment in place: "Forwards explicitly -- a default
`delegate:` param doesn't satisfy a protocol requirement that omits it."

Full history: `URLSession`'s own `data(from:)`/`download(from:)`/
`data(for:)` all take a trailing `delegate:` parameter with a default
value -- a default value doesn't make a method's signature match a
protocol requirement that omits the parameter outright, so these forward
explicitly instead of conforming "for free".

### `ScanClient` (actor)
Talks to lambada-web's (or scandalous's) HTTP API: GET /files.json for
the listing, GET /download/:filename for the bytes. Downloaded files are
cached on disk by name (server-generated, supposedly immutable and never
reused -- see `ScanEntry`) so a file fetched once to build a thumbnail
is never fetched twice when the user then clicks Download.
`cachedFile(for:in:)` double-checks that assumption against `scan.size`
rather than trusting it blindly -- see that method's note below.

### `ScanClient.init(baseURL:session:)`
`session` defaults to `.shared` for real use; tests inject a fake
`ScanHTTPClient` (see `FakeHTTPClient` in ZoukKitTests) so
`fetchScans()`/`cachedFile(for:in:)` can be called directly without
touching the real network.

### `ScanClient.cachedFile(for:in:)`
Kept a one-line comment in place: "Compares the cached file's size
against scan.size to avoid serving stale bytes under a reused name."

Full history: returns a local file URL for `scan`, downloading into
`cacheDirectory` only if it isn't already there *and matching
`scan.size`*. The cache is keyed purely by `scan.name`, on the
assumption (documented on `ScanEntry`) that the server never reuses a
name. That assumption isn't actually enforced anywhere -- a server bug,
or a name collision from outside zouk entirely (as happened during
testing: a same-named file dropped directly into the server's
directory), would otherwise make this silently and permanently serve the
*old* file's bytes under the new entry's name, with nothing on screen to
suggest anything's wrong beyond a thumbnail that looks like the wrong
file. Comparing the cached file's actual size on disk to the size the
server just reported for this name catches that case and re-downloads
instead of trusting stale bytes. It's not foolproof (two genuinely
different files could happen to be the same size), but the listing API
doesn't give us anything stronger than size/time to check against, and
this is already a strict improvement over no check at all.

### `ScanClient.save(_:to:cacheDirectory:)`
Copies the (possibly already-cached) file straight to `destination`,
whatever name and folder the caller chose for it -- in practice, an
`NSSavePanel` the caller already ran. No Finder-style de-dup naming here:
the panel already resolved any "replace this file?" question before
this is ever called, so this just writes to exactly the URL it's given.

### `ScanClient.delete(_:)`
Kept a one-line comment in place: "DELETE on the same path GET uses to
download; lambada-web shares one route for both verbs."

Full history: deletes `scan` from the server: DELETE on the exact same
server-relative path (`scan.path`) GET already uses to download it.
lambada-web registers both verbs on the same "/download/:filename"
resource rather than a separate "/delete/:filename" route, so this only
changes the HTTP method, not the URL. Doesn't touch the local cache or
`AppModel`'s `scans` array -- `AppModel.delete(_:)` does that on
success.

### `ScanClient.uniqueDestination(for:in:)`
Kept a one-line comment in place: "Finder-style de-dup naming:
'scan.pdf' becomes 'scan (1).pdf' instead of overwriting."

Full history: Finder-style de-duplication: downloading "scan.pdf" a
second time produces "scan (1).pdf", then "scan (2).pdf", and so on,
instead of silently overwriting the file already in Downloads.

### `ScanClient.cachedSizeMatches(_:at:)`
Kept a one-line comment in place: "Unreadable attributes count as a
mismatch; safer to re-download than trust an unverifiable size."

Full history: whether the file already sitting at `local` is plausibly
still *this* scan's bytes, not a leftover from some earlier, unrelated
file that happened to land under the same name.

## Sources/ZoukKit/ScanEntry.swift

### `ScanEntry` (struct)
Kept a one-line comment in place: "name is a server-generated,
assumed-unique timestamp filename; path is server-relative (renamed
from url)."

Full history: mirrors one entry from the `/files.json` endpoint served
by lambada-web (or scandalous, its Ruby predecessor). `name` is a
server-generated Unix-timestamp filename like "1779907271.pdf" -- never
user input -- so it's safe to use directly as a local file/cache name
with no sanitization. `path` is a server-relative download path (e.g.
"/download/1779907271.pdf"), not a URL -- it was misnamed `url` until
this field (and the endpoint itself, previously `/scans.json`) were
renamed for accuracy.

### `ScanEntry.formattedDate`
Finder-style relative timestamp ("Today at 4:11 PM", "Yesterday at 9:02
AM", or a plain date once it's further back) instead of a bare calendar
date -- matches how Finder's list view shows Date Modified.

### `ScanEntry.timeAgo`
"6 days ago"/"less than a minute ago"-style relative age, without the
"ago" suffix -- matches lambada-web/scandalous's own timeAgo/
time_ago_in_words wording (both ultimately Rails'
distance_of_time_in_words), used so the delete confirmation dialog
(`ScanGridView`) reads the same way the web listing's own delete confirm
does: "Delete this scan from &lt;timeAgo&gt; ago?". Uses the real
current time -- see `timeAgo(relativeTo:)` for a version tests can pin
to a fixed clock.

### `ScanEntry.timeAgo(relativeTo:)`
Same as `timeAgo`, but takes an explicit "now" instead of reading the
real clock, so a test can assert exact wording (e.g. "15 seconds before
now" -> "less than a minute") deterministically.

Kept a one-line comment in place (sub-30-second clamp): "Sub-30-second
durations are clamped to 'less than a minute', matching
scandalous/lambada-web."

Kept a one-line comment in place (trailing " ago" strip): "Strips
trailing ' ago' so callers control placement, matching lambada-web's
template func."

## Sources/ZoukKit/ScanGridView.swift

### `ScanGridView` (struct)
Finder/Samba-share-style icon grid: PDF thumbnail above, filename below.
Click selects a scan and shows its date/size in the footer; double-click
selects it and opens a native Save panel -- pre-filled with the scan's
name and ~/Downloads already selected, so confirming as-is reproduces
the old "just go to Downloads" behavior, but renaming or picking a
different folder is just as easy -- then hands the saved file to
whatever app handles PDFs, the same way double-clicking a file on a
mounted network share would open it. While the save is in flight, a
plain text capsule reads "Saving ..." (no spinner, no animation); once
it lands, the footer itself reads "File ... saved." and stays that way
-- replacing the usual scan-count/selection text -- until a new
selection or another save needs the footer for something else. That
persistence is the point: a capsule that vanishes on its own timer is
too easy to miss, especially for someone expecting Finder/Samba-share
behavior. Right-click adds Download and Open / Download to... / Fast
Download / Move to Trash (issue #4) -- see `ScanThumbnailCell`. Move to
Trash from that menu deletes immediately with no confirmation; only the
footer's own trash button (below) asks "are you sure" first -- see
`AppModel.requestDelete(_:)`.

### `ScanGridView.body`, address bar `HStack`
Browser-style: reload on the left, an address bar you can just type
into stretching the rest of the way to the window's edge -- no separate
"click to edit" step.

### `ScanGridView.body`, `.confirmationDialog` modifier
Kept a one-line comment in place: "presenting uses pendingDelete, not
selectedScan; title mirrors the web listing's confirm() text."

Full history: `presenting` hands the exact scan `requestDelete(_:)`
armed to the actions closure below, rather than reading back
`model.selectedScan` (which `model.pendingDelete` deliberately doesn't
depend on -- see that property's note above). The title itself is built
from `pendingDelete` directly (this modifier's title parameter isn't a
closure) to word-for-word match the web listing's own delete `confirm()`
-- "Delete this scan from &lt;timeAgo&gt; ago?" -- rather than a
separate title/message pair with size and date, which is what this used
to say before parity with the web prompt was requested.

### `ScanGridView.footer`
Finder-style status bar. Priority, highest first: `savedMessage` (the
persistent "File ... saved." confirmation from the most recent
`open(_:)`, if nothing's cleared it since); else the clicked scan's date
and size, plus a trash button that opens the delete confirmation dialog
above; else the total scan count when nothing's selected. Centered
either way. (A failed reload bounces back to `HostEntryView` instead of
landing here, so there's no "can't reach host" case to show in this
footer.)

### `CircularIconButtonStyle` (struct)
Circular icon-only toolbar button (the address bar's reload button),
subtle fill at rest, darker while pressed.

### `DogEaredDocumentIcon` (struct)
Generic "no preview yet" document icon: a white page with the top-right
corner folded down and a soft drop shadow, the same idea as the default
icon Finder shows for a file it hasn't generated a thumbnail for yet.

### `DogEaredDocumentIcon.PageShape`
Page outline with a diagonal cut out of the top-right corner (where the
fold sits) and square corners everywhere else -- a plain sheet of paper,
not a rounded card.

### `DogEaredDocumentIcon.FoldShape`
The little triangular flap at the top-right, as if that corner were
folded down over the page.

### `ScanThumbnailCell.controlActiveState`
Kept a one-line comment in place: "Selection tint follows window key
state, like Finder."

Full history: mirrors Finder: the icon itself stays plain, only the
filename label gets the selection highlight, and that highlight is blue
while this window is key and dims to gray once it isn't (matches the
system's own active/inactive selection tint instead of always being
blue).

### `ScanThumbnailCell.body`, no-thumbnail branch
Kept a one-line comment in place: "Drawn, not clipped, so the dog-ear
fold and shadow render like Finder's unpreviewed-file placeholder."

Full history: drawn (not a clipped background) so the dog-ear fold and
drop shadow read as a generic document icon, like the placeholder
Finder shows for an unpreviewed file on a mounted share. Sized a bit
smaller than the cell itself so it doesn't look bulkier than an actual
scan thumbnail sitting in the same spot.

### `ScanThumbnailCell.body`, `.padding(6)` modifier
Kept a one-line comment in place: "Padding stays constant so selection
only toggles tint/shadow, not layout."

Full history: padding is unconditional so the cell doesn't resize/jitter
on select; only the tint and shadow turn on, as a halo around the
thumbnail that echoes the filename's selection color.

### `ScanThumbnailCell.body`, `.gesture` modifier
Kept a one-line comment in place: "exclusively(before:) gives
double-tap explicit precedence over single-tap."

Full history: explicit precedence with `exclusively(before:)` rather
than two independent `onTapGesture` modifiers: double only wins if a
second tap lands before the single-tap window closes, otherwise it falls
through to select/deselect.

### `ScanThumbnailCell.body`, `.contextMenu` modifier
Kept a one-line comment in place: "Right-click menu reintroduced for
issue #4; see docs/COMMENTS.md for why that's not a design reversal."

Full history: reintroduces right-click (issue #4) with more options than
the Save-As-only gesture removed earlier -- see `docs/COWORK.md`'s
"Design conventions" section for why that's not a contradiction.

### `ScanThumbnailCell.body`, "Move to Trash" button
Kept a one-line comment in place: "Skips confirmation deliberately; see
AppModel.requestDelete(_:)."

Full history: deliberately skips the footer trash button's confirmation
dialog -- see `AppModel.requestDelete(_:)`'s note above for why picking
this from an explicit context menu doesn't get a second "are you sure"
gate.

## Sources/zouk/ZoukApp.swift

### `ZoukApp.body`, `CommandGroup(replacing: .appInfo)`
Kept a one-line comment in place: "Replaces the default About item so
it shows our full name + credits, not the raw CFBundleName."

Full history: replaces the default "About zouk" item (which would
otherwise show the bundle's literal `CFBundleName`, "zouk") with one
that calls the same native panel, just with our full display name and a
copyright credits line -- no separate custom About window/sheet to
build or maintain.

### `AppDelegate` (class)
`swift run` launches zouk as a bare process with no `.app` bundle, so
macOS doesn't hand it keyboard focus/the menu bar the way it would an
app double-clicked from Finder: the window appears (you can even drag
it) but it never becomes the active app, so it can't receive keystrokes.
Forcing activation on launch fixes that.

### `AppDelegate.applicationDidFinishLaunching(_:)`
Kept a one-line comment in place: "Also sets the Dock icon for swift
run/dev launches, not just the bundled .app."

## Tests/ZoukKitTests/AppModelSpec.swift

### `AppModelSpec.spec()`, before "with a connected model showing one scan"
Kept a one-line comment in place: "AsyncSpec (not QuickSpec) is needed
since AppModel is @MainActor; see Quick's AsyncAwait.md."

Full history: `AppModel` is `@MainActor`, so the specs below need
Quick's async DSL -- plain `QuickSpec`'s `it` only accepts a synchronous
closure (Quick 7 gates async/await support behind the `AsyncSpec` base
class this file uses instead; see `Quick/Documentation/en-us/AsyncAwait.md`).
`beforeEach`/`it` hop to the main actor via `await MainActor.run { ... }`,
the pattern that doc recommends for running synchronous, MainActor-bound
code from an otherwise-async example -- mirrors the `@MainActor func
test...()` isolation the old XCTest cases used, just expressed as an
explicit hop instead of a function attribute.

### `context("with a connected model showing one scan")`, `nonisolated(unsafe)` vars
Kept a one-line comment in place: "nonisolated(unsafe): Quick serializes
beforeEach/it so there's no real race, but the compiler can't see that."

Full history: `beforeEach`/`it` each hop onto the main actor
independently, so these two vars are written and read from a series of
separate `MainActor.run` closures rather than one continuous isolated
scope. Quick never runs more than one of those closures at a time for a
given example -- `beforeEach` always finishes before its `it` starts --
so there's no actual race, but the compiler has no way to know that
about a third-party library's execution order. `nonisolated(unsafe)`
says exactly that: the isolation checker can't verify this is safe, but
it is.

### `describe("#toggle(_:)")` -> `it("selects then deselects the same scan")`
Click-to-select / click-again-to-deselect, and that `selectedScan` looks
the selected id back up in the current scan list.

### `context("with a savedMessage lingering from a previous open(_:)")`
The footer can only show one thing at a time: a fresh selection should
take over from a lingering "saved to Downloads" message, not show both.

### `describe("#requestDelete(_:)")`
Kept a one-line comment in place: "Only the footer trash button calls
this; right-click 'Move to Trash' skips confirmation entirely."

Full history: the footer's trash button is the only caller of this --
it's what arms `ScanGridView`'s `.confirmationDialog`. The right-click
"Move to Trash" item deliberately skips this and calls `delete(_:)`
directly with no confirmation, so it's out of scope here; see
`AppModel.requestDelete(_:)`'s note above for why the two trash triggers
behave differently on purpose.

## Tests/ZoukKitTests/FakeHTTPClient.swift

### `FakeHTTPClient` (class)
Kept a one-line comment in place: "@unchecked Sendable: each test owns
its own instance before handing it to one ScanClient actor."

Full history: fake `ScanHTTPClient` for `ScanClientSpec` -- lets tests
call `fetchScans()`/`cachedFile(for:in:)`/`delete(_:)` directly without
touching the real network. Set `dataHandler`/`downloadHandler`/
`requestHandler` per test; an unset handler throws, same as a real
network failure would. `@unchecked Sendable` because each test builds
and configures its own instance before handing it to a single
`ScanClient` actor, so there's no shared mutable state across
concurrency domains in practice.

## Tests/ZoukKitTests/ScanClientSpec.swift

### `context("when the file is already cached and its size matches scan.size")`
Kept a one-line comment in place: "Matches scan.size (7) so cachedFile
trusts the cache; see the mismatch context below."

### same context, `downloadHandler` tripwire
Kept a one-line comment in place: "Tripwire: a call here would throw
and fail the test if the short-circuit logic ever regressed."

### `context("when a same-named file is cached but its size doesn't match scan.size")`
Kept a one-line comment in place: "Regression test for the stale-cache
bug; see docs/COMMENTS.md (ScanClient.cachedFile(for:in:))."

Full history: a file landing under a name that's already in zouk's
local cache (whether from a server bug or, as found during manual
testing, someone dropping a same-named file directly into the server's
directory) used to be served from the stale cache forever -- e.g. a
grid cell silently showing the old file's thumbnail for the new entry.
`cachedFile` now notices the size mismatch and re-downloads instead.

## Tests/ZoukKitTests/ScanEntrySpec.swift

### `describe("#timeAgo")` -> `it("is non-nil and doesn't include a trailing \" ago\"")`
The delete confirmation dialog (`ScanGridView`) appends " ago?" itself
-- matching lambada-web/scandalous's `timeAgo` template func, which
returns just the duration for the same reason.

### `describe("#timeAgo(relativeTo:)")`
Kept a one-line comment in place: "Regression spec for the 2026-07-02
sub-30-second clamping bug; see docs/COMMENTS.md."

Full history: regression spec for the bug woodie caught 2026-07-02:
deleting a scan seconds after it arrived showed "Delete this scan from
15 seconds ago" in zouk, while scandalous/lambada-web both showed "less
than a minute ago" for the same age. Deterministic (fixed `now` passed
in) rather than depending on the real clock, unlike the `#timeAgo` spec
above.
