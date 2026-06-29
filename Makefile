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

BUNDLE_DIR=.build/$(PRODUCT_NAME).app
RELEASE_DIR=.build/release

SUDO:=$(shell d="$(PREFIX)/bin"; while [ ! -d "$$d" ] && [ "$$d" != "/" ]; do d=$$(dirname "$$d"); done; test -w "$$d" && echo "" || echo "sudo")

SWIFT_BUILD_FLAGS=--configuration release

.PHONY: all
all: build

.PHONY: build
build:
	$(SWIFT) build $(SWIFT_BUILD_FLAGS)

.PHONY: test
test:
	$(SWIFT) test

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

.PHONY: run
run: bundle
	-killall $(PRODUCT_NAME) 2>/dev/null
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
