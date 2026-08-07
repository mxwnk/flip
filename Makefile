APP_NAME  := Flip
BUNDLE_ID := dev.mxwnk.Flip
IDENTITY  := Flip Local Signing
# The latest tag, so a local build does not report a version it is nowhere near
# and a diagnostic report can be believed. The pipeline passes VERSION from the
# tag being released, which overrides this.
VERSION   := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)
# Read rather than repeated: LICENSE is the document that actually grants
# anything, so the year belongs there and nowhere else.
COPYRIGHT := $(shell grep -m1 '^Copyright' LICENSE)

BINARY    := .build/release/$(APP_NAME)
BUNDLE      := build/$(APP_NAME).app
REQUIREMENT := resources/designated-requirement.txt
STAGING   := build/dmg
DMG       := build/$(APP_NAME)-$(VERSION).dmg
INSTALLED := $(HOME)/Applications/$(APP_NAME).app

.PHONY: all cert uncert build bundle sign install run stop restart logs test icon icon-background dmg dmg-layout verify settings login clean

all: install

## cert: create the self-signed signing identity (once, interactive)
cert:
	@scripts/make-cert.sh "$(IDENTITY)"

## uncert: remove the signing identity again, to start over
# Anything already signed with it keeps working; it just cannot be re-signed.
uncert:
	@security delete-identity -c "$(IDENTITY)" \
		$(HOME)/Library/Keychains/login.keychain-db 2>/dev/null && \
		echo "Removed '$(IDENTITY)'." || \
		echo "No identity '$(IDENTITY)' to remove."

## build: compile the executable
build:
	swift build -c release

## bundle: assemble build/Flip.app
bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources \
		$(BUNDLE)/Contents/Library/LaunchAgents
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
		-e 's|@COPYRIGHT@|$(COPYRIGHT)|g' \
		resources/Info.plist > $(BUNDLE)/Contents/Info.plist
	# Registered by the app through SMAppService, not installed by this Makefile,
	# which is why it ships inside the bundle.
	sed -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' resources/LaunchAgent.plist \
		> $(BUNDLE)/Contents/Library/LaunchAgents/$(BUNDLE_ID).login.plist
	cp resources/$(APP_NAME).icns $(BUNDLE)/Contents/Resources/
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo

## test: run the unit tests
# XCTest ships with Xcode, not the Command Line Tools, so the toolchain is
# pointed at Xcode for this one command rather than changing xcode-select.
test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

## icon: redraw resources/Flip.icns and docs/icon.png
# Committed rather than generated during a build: CI has to package the same icon
# without redrawing it, and an .icns is small enough to keep in the repository.
icon:
	@mkdir -p build
	swift scripts/make-icon.swift

## sign: sign the bundle so TCC keeps its grants across rebuilds
# --identifier pins the bundle ID into the signature, which is half of what the
# designated requirement is built from. Drop it and the requirement drifts.
sign: bundle
	@security find-identity -v -p codesigning | grep -qF "$(IDENTITY)" || \
		{ echo "No signing identity '$(IDENTITY)'. Run: make cert" >&2; exit 1; }
	codesign --force --sign "$(IDENTITY)" --identifier "$(BUNDLE_ID)" $(BUNDLE)
	@codesign --verify --verbose=2 $(BUNDLE)

## install: replace the copy in ~/Applications
install: sign stop
	@mkdir -p $(HOME)/Applications
	rm -rf $(INSTALLED)
	cp -R $(BUNDLE) $(INSTALLED)
	@echo "Installed $(INSTALLED)"

## run: install and launch
# Never started straight from the shell: that would make the terminal the
# responsible process for TCC, and the privacy grants would be attributed to it
# rather than to Flip. The login agent is registered by the app, not from here.
run: install
	open -a $(INSTALLED)
	@echo "Started. Follow along with: make logs"

## stop: quit a running instance
# The login job has to go first. Killing the process while launchd still owns it
# only means launchd starts it again — in the middle of replacing the bundle.
stop:
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID).login 2>/dev/null || true
	@killall $(APP_NAME) 2>/dev/null || true

restart: stop run

## logs: follow Flip's log output
logs:
	log stream --level debug --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

## dmg: package build/Flip-<version>.dmg for installing on another Mac
# Read the Gatekeeper caveat in the Readme first. This is signed with the local
# self-signed identity and not notarised, so on any Mac other than the one that
# created the certificate it opens only via right-click > Open.
dmg: sign
	@scripts/make-dmg.sh "$(VERSION)" "$(IDENTITY)"

## dmg-layout: redraw the disk image window and commit how it looks
# Needs a desktop session, so it is never part of a release build. Run it after
# changing the backdrop or the icon positions.
dmg-layout: sign icon-background
	@scripts/make-dmg.sh "$(VERSION)" "$(IDENTITY)" --layout

## icon-background: redraw resources/dmg-background.tiff
icon-background:
	@swift scripts/make-dmg-background.swift

## verify: assert the designated requirement has not drifted
# The whole reason for signing against a certificate. This requirement is what
# TCC keys its grants to, so if it ever changes, every installed copy silently
# loses Accessibility and Screen Recording on the next update. Recorded in the
# repository rather than eyeballed, and checked on every release.
# Depends on sign, not bundle: bundle rebuilds the app unsigned, which would
# destroy the very signature this is meant to inspect.
verify: sign
	@codesign -d -r- $(BUNDLE) 2>&1 | sed -n 's/^designated => //p' > build/requirement.actual
	@if diff -q $(REQUIREMENT) build/requirement.actual >/dev/null; then \
		echo "designated requirement unchanged"; \
	else \
		echo "designated requirement CHANGED — installed copies will lose their grants:"; \
		diff $(REQUIREMENT) build/requirement.actual; \
		exit 1; \
	fi

## settings: open the two privacy panes Flip needs
settings:
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

## login: report whether Flip starts at login
# Registering is the app's job now — SMAppService only accepts it from inside the
# bundle — so this only reports. The switch lives in Settings, General.
login:
	@launchctl print gui/$$(id -u)/$(BUNDLE_ID).login >/dev/null 2>&1 \
		&& echo "Flip starts at login." \
		|| echo "Flip does not start at login. Turn it on in Settings > General."

clean:
	rm -rf .build build
