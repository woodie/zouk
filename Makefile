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
	# The generated Bundle.module accessor's primary lookup path is built
	# from Bundle.main.bundleURL, which for a macOS .app is the bundle's
	# TOP LEVEL (e.g. zouk.app/), not Contents/Resources -- that's the
	# separate resourceURL property, which this accessor never checks. So
	# the bundle has to land at the app's top level to actually be found;
	# copying it into Contents/Resources only (the first attempt at this
	# fix) looks right by macOS convention but doesn't match what the
	# accessor checks, and silently keeps shipping a build that
	# fatalErrors on any machine without the dev's exact .build path. We
	# copy to both locations: top level because the current accessor's
	# primary path depends on it, Contents/Resources for convention and
	# in case a future SwiftPM regenerates the accessor to check
	# resourceURL instead. See docs/COWORK.md's "Packaging gotcha" note.
	@for b in "$(BUILD_DIRECTORY)"/*.bundle; do \
		test -e "$$b" || continue; \
		name=$$(basename "$$b"); \
		$(RM) "$(BUNDLE_DIR)/$$name"; \
		$(CP) -R "$$b" "$(BUNDLE_DIR)/$$name"; \
		$(RM) "$(BUNDLE_DIR)/Contents/Resources/$$name"; \
		$(CP) -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/$$name"; \
	done
	@for b in "$(BUILD_DIRECTORY)"/*.bundle; do \
		test -e "$$b" || continue; \
		name=$$(basename "$$b"); \
		test -d "$(BUNDLE_DIR)/$$name" || { \
			echo "error: $$name missing from $(BUNDLE_DIR) top level -- Bundle.module's primary lookup (Bundle.main.bundleURL) will fatalError at runtime without this"; \
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
