PRODUCT_NAME=zouk

PREFIX?=/usr/local

CP=/bin/cp -f
MKDIR=/bin/mkdir -p
RM=/bin/rm -rf
SWIFT?=swift

BUNDLE_DIR=.build/$(PRODUCT_NAME).app

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

# swift run execs the binary as a plain child of the shell -- no app
# bundle, no LaunchServices, so the window can appear without ever
# becoming the focused/key app (keystrokes go to the launching terminal
# instead). `make run` instead assembles a minimal zouk.app and opens it
# the normal way, so macOS activates it like any other Mac app.
.PHONY: bundle
bundle:
	$(SWIFT) build
	$(eval BUILD_DIRECTORY := $(shell $(SWIFT) build --show-bin-path))
	$(MKDIR) "$(BUNDLE_DIR)/Contents/MacOS"
	$(CP) "$(BUILD_DIRECTORY)/$(PRODUCT_NAME)" "$(BUNDLE_DIR)/Contents/MacOS/$(PRODUCT_NAME)"
	$(CP) Resources/Info.plist "$(BUNDLE_DIR)/Contents/Info.plist"

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
