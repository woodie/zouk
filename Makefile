PRODUCT_NAME=zouk

PREFIX?=/usr/local

CP=/bin/cp -f
MKDIR=/bin/mkdir -p
RM=/bin/rm -rf
SWIFT?=swift
PLISTBUDDY?=/usr/libexec/PlistBuddy
DITTO?=/usr/bin/ditto
CODESIGN?=/usr/bin/codesign

# Must match a "Developer ID Application" certificate's exact name in the
# signing machine's keychain -- `security find-identity -v -p codesigning`
# lists what's available. Overridable so CI can pass the identity it
# imports without editing this file.
#
# Team ID here (754T277KBJ) is the paid Developer Program team -- it's
# DIFFERENT from the free personal team (6R5XSSRC9P) behind the "Apple
# Development" cert Xcode creates automatically. Don't conflate the two;
# NOTARY_TEAM_ID in release.yml's secrets must also be 754T277KBJ.
CODESIGN_IDENTITY?=Developer ID Application: John Woodell (754T277KBJ)

# A separate identity from CODESIGN_IDENTITY above -- pkgbuild --sign
# does not accept a "Developer ID Application" cert, only "Developer ID
# Installer". Same paid Developer Program team (754T277KBJ), different
# cert type. Overridable for the same CI reason as CODESIGN_IDENTITY.
INSTALLER_IDENTITY?=Developer ID Installer: John Woodell (754T277KBJ)

BUNDLE_DIR=.build/$(PRODUCT_NAME).app
RELEASE_DIR=.build/release
# pkgbuild, not productbuild -- productbuild --component is only a thin
# wrapper around pkgbuild for the single-component case and doesn't expose
# --component-plist, which the pkg target below needs to disable
# BundleIsVersionChecked.
PKGBUILD?=/usr/bin/pkgbuild

SUDO:=$(shell d="$(PREFIX)/bin"; while [ ! -d "$$d" ] && [ "$$d" != "/" ]; do d=$$(dirname "$$d"); done; test -w "$$d" && echo "" || echo "sudo")

SWIFT_BUILD_FLAGS=--configuration release

.PHONY: all
all: build

.PHONY: build
build:
	$(SWIFT) build $(SWIFT_BUILD_FLAGS)

.PHONY: test
test:
	$(SWIFT) test | xctidy -fs

# Config lifted from next-caltrain-swift's .swiftlint.yml -- requires the
# swiftlint CLI (`brew install swiftlint`); not wired into CI yet since
# zouk has never been linted and the violation count is unknown.
.PHONY: lint
lint:
	swiftlint

# swift run execs the binary as a plain child of the shell -- no app
# bundle, no LaunchServices, so the window can appear without ever
# becoming the focused/key app (keystrokes go to the launching terminal
# instead). `make run` instead assembles a minimal zouk.app and opens it
# the normal way, so macOS activates it like any other Mac app.
.PHONY: bundle
bundle:
	$(SWIFT) build $(SWIFT_BUILD_FLAGS)
	$(eval BUILD_DIRECTORY := $(shell $(SWIFT) build --show-bin-path $(SWIFT_BUILD_FLAGS)))
	$(MKDIR) "$(BUNDLE_DIR)/Contents/MacOS"
	$(MKDIR) "$(BUNDLE_DIR)/Contents/Resources"
	$(CP) "$(BUILD_DIRECTORY)/$(PRODUCT_NAME)" "$(BUNDLE_DIR)/Contents/MacOS/$(PRODUCT_NAME)"
	$(CP) Resources/Info.plist "$(BUNDLE_DIR)/Contents/Info.plist"
	$(CP) Resources/AppIcon.icns "$(BUNDLE_DIR)/Contents/Resources/AppIcon.icns"
	# Any SwiftPM target with a `resources:` entry (e.g. ZoukKit) makes
	# swift build emit a *.bundle next to the binary in BUILD_DIRECTORY.
	# This goes into Contents/Resources -- the conventional macOS
	# location, and the *only* one `codesign` permits once the app is
	# actually signed (anything sitting outside Contents/ makes `codesign
	# --sign` fail outright with "unsealed contents present in the bundle
	# root", not just a notarization-time rejection). An earlier fix also
	# copied this to the .app's TOP level, because the SwiftPM-generated
	# Bundle.module accessor never checked resourceURL and that was the
	# only place it looked. That's no longer needed: ZoukKit's
	# ResourceBundle.swift now reads Bundle.main.resourceURL directly
	# (falling back to Bundle.module only for swift run/swift test/Xcode,
	# where Bundle.main isn't a real .app), so Contents/Resources alone is
	# both correct and sign-safe. See docs/COWORK.md's "Packaging gotcha"
	# note for the full history.
	@for b in "$(BUILD_DIRECTORY)"/*.bundle; do \
		test -e "$$b" || continue; \
		name=$$(basename "$$b"); \
		$(RM) "$(BUNDLE_DIR)/Contents/Resources/$$name"; \
		$(CP) -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/$$name"; \
	done
	@for b in "$(BUILD_DIRECTORY)"/*.bundle; do \
		test -e "$$b" || continue; \
		name=$$(basename "$$b"); \
		test -d "$(BUNDLE_DIR)/Contents/Resources/$$name" || { \
			echo "error: $$name missing from $(BUNDLE_DIR)/Contents/Resources -- ResourceBundle.swift's primary lookup (Bundle.main.resourceURL) will fall back to the dev-only Bundle.module without this, which fatalErrors in a packaged app"; \
			exit 1; \
		}; \
	done

.PHONY: sign
# Signing (+ notarization, done separately in CI via xcrun notarytool) is
# what makes Gatekeeper wave the app through with no warning at all.
# --options runtime turns on the hardened runtime and --timestamp embeds a
# secure timestamp -- both are hard requirements for notarization to
# accept the binary. --deep is normally discouraged (Apple wants inner
# binaries signed before outer ones), but zouk has no embedded
# frameworks/helpers to worry about -- one binary, one signature.
sign: bundle
	$(CODESIGN) --force --deep --options runtime --timestamp \
		--sign "$(CODESIGN_IDENTITY)" "$(BUNDLE_DIR)"
	$(CODESIGN) --verify --deep --strict --verbose=2 "$(BUNDLE_DIR)"

.PHONY: package
# Zips zouk.app for a GitHub release / the Homebrew cask's url to point at.
# ditto -c -k (not zip -r) because it's Apple's documented way to archive a
# .app -- preserves resource forks/xattrs that a plain zip can mangle.
# --keepParent puts zouk.app itself at the zip's top level, which is what
# both a manual unzip and the cask's `app "zouk.app"` stanza expect.
# Depends on sign (not bundle) so anything zipped for release is always
# signed -- notarization happens after this, in release.yml.
package: sign
	$(eval VERSION := $(shell $(PLISTBUDDY) -c "Print :CFBundleShortVersionString" Resources/Info.plist))
	$(MKDIR) $(RELEASE_DIR)
	$(RM) "$(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).zip"
	$(DITTO) -c -k --keepParent "$(BUNDLE_DIR)" "$(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).zip"
	@echo "Wrote $(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).zip"

.PHONY: pkg
# A double-click installer as an alternative to the zip -- UX polish for
# non-technical recipients ("Next, Next, Done" vs. "unzip, drag to
# Applications"); the signed/notarized zip already gets a no-warning
# install for everyone, pkg doesn't fix a broken path. Depends on sign
# (not bundle), same reasoning as package: anything shipped for release
# should always be signed first. The .pkg itself is notarized/stapled
# separately in release.yml -- notarytool/stapler both take a .pkg
# directly, no zip-for-upload step needed like the .app requires.
pkg: sign
	$(eval VERSION := $(shell $(PLISTBUDDY) -c "Print :CFBundleShortVersionString" Resources/Info.plist))
	$(eval BUNDLE_ID := $(shell $(PLISTBUDDY) -c "Print :CFBundleIdentifier" Resources/Info.plist))
	$(MKDIR) $(RELEASE_DIR)
	$(RM) "$(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).pkg"
	$(eval PKGROOT := $(RELEASE_DIR)/pkgroot)
	$(eval COMPONENT_PLIST := $(RELEASE_DIR)/component.plist)
	# pkgbuild's --component form (no --root) doesn't accept
	# --component-plist at all -- per its own usage text, only the --root
	# form does. So this stages a destination root
	# (pkgroot/Applications/zouk.app) instead of pointing --component
	# straight at $(BUNDLE_DIR), purely to unlock --component-plist below.
	$(RM) "$(PKGROOT)"
	$(MKDIR) "$(PKGROOT)/Applications"
	/bin/cp -R "$(BUNDLE_DIR)" "$(PKGROOT)/Applications/$(PRODUCT_NAME).app"
	# Hand-written rather than `pkgbuild --analyze --root`, which would
	# otherwise need a second pkgbuild invocation just to generate this --
	# this is the same shape --analyze emits for a single app component,
	# just with BundleIsVersionChecked forced to false: the Installer
	# otherwise compares CFBundleVersion against whatever's already on
	# disk and silently skips the copy (while still reporting overall
	# success) if it isn't strictly newer, and zouk's CFBundleVersion
	# doesn't bump on every build.
	echo '<?xml version="1.0" encoding="UTF-8"?>' > "$(COMPONENT_PLIST)"
	echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$(COMPONENT_PLIST)"
	echo '<plist version="1.0"><array><dict>' >> "$(COMPONENT_PLIST)"
	echo '<key>BundleHasStrictIdentifier</key><true/>' >> "$(COMPONENT_PLIST)"
	echo '<key>BundleIsRelocatable</key><false/>' >> "$(COMPONENT_PLIST)"
	echo '<key>BundleIsVersionChecked</key><false/>' >> "$(COMPONENT_PLIST)"
	echo '<key>BundleOverwriteAction</key><string>upgrade</string>' >> "$(COMPONENT_PLIST)"
	echo '<key>RootRelativeBundlePath</key><string>Applications/$(PRODUCT_NAME).app</string>' >> "$(COMPONENT_PLIST)"
	echo '</dict></array></plist>' >> "$(COMPONENT_PLIST)"
	$(PKGBUILD) --root "$(PKGROOT)" \
		--install-location / \
		--component-plist "$(COMPONENT_PLIST)" \
		--identifier "$(BUNDLE_ID)" \
		--version "$(VERSION)" \
		--sign "$(INSTALLER_IDENTITY)" \
		"$(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).pkg"
	@echo "Wrote $(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).pkg"

.PHONY: run
# killall runs *before* bundle rebuilds the binary, not after: overwriting
# zouk's executable at this path while a previous run of it is still live
# (still mapped/executing) can corrupt the kernel's code-signature
# validation for that file -- the next launch can then get killed with
# EXC_BAD_ACCESS/SIGKILL "Code Signature Invalid" the first time it touches
# an affected page, sometimes well after launch rather than immediately.
# See docs/crash.txt for a real instance of this. Killing first closes the
# window entirely: nothing has the old binary mapped when bundle overwrites it.
run:
	-killall $(PRODUCT_NAME) 2>/dev/null
	$(MAKE) bundle
	open -n "$(BUNDLE_DIR)"

.PHONY: install
install: build
	$(eval BINARY_DIRECTORY := $(PREFIX)/bin)
	$(eval BUILD_DIRECTORY := $(shell $(SWIFT) build --show-bin-path $(SWIFT_BUILD_FLAGS)))
	$(SUDO) $(MKDIR) $(BINARY_DIRECTORY)
	$(SUDO) $(CP) "$(BUILD_DIRECTORY)/$(PRODUCT_NAME)" "$(BINARY_DIRECTORY)"

.PHONY: uninstall
uninstall:
	$(SUDO) $(RM) "$(PREFIX)/bin/$(PRODUCT_NAME)"

.PHONY: clean
clean:
	$(SWIFT) package clean
	$(RM) .build

.PHONY: xcode
xcode:
	open Package.swift
