APP_NAME  := Flip
BUNDLE_ID := dev.mxwnk.Flip
IDENTITY  := Flip Local Signing
VERSION   := 0.1.0

BINARY    := .build/release/$(APP_NAME)
BUNDLE    := build/$(APP_NAME).app
STAGING   := build/dmg
DMG       := build/$(APP_NAME)-$(VERSION).dmg
INSTALLED := $(HOME)/Applications/$(APP_NAME).app
AGENT     := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

.PHONY: all cert uncert build bundle sign install run stop restart logs dmg verify settings autostart unautostart clean

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
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
		Resources/Info.plist > $(BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo

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
# rather than to Flip. Once the login agent exists it is the way in, so that
# `make run` does not silently downgrade an autostarting install to a manual one.
run: install
	@if [ -f $(AGENT) ]; then \
		launchctl bootstrap gui/$$(id -u) $(AGENT) && echo "Started via the login agent."; \
	else \
		open -a $(INSTALLED) && echo "Started."; \
	fi
	@echo "Follow along with: make logs"

## stop: quit a running instance
# The login job has to go first. Killing the process while launchd still owns it
# only means launchd starts it again — in the middle of replacing the bundle.
stop:
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null || true
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
	rm -rf $(STAGING)
	mkdir -p $(STAGING)
	cp -R $(BUNDLE) $(STAGING)/
	ln -s /Applications $(STAGING)/Applications
	rm -f $(DMG)
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(STAGING) \
		-format UDZO -quiet $(DMG)
	codesign --force --sign "$(IDENTITY)" $(DMG)
	@rm -rf $(STAGING)
	@echo "Packaged $(DMG)"

## verify: print the designated requirement, which must not change between builds
# This is the acceptance test for step one: run it before and after a rebuild and
# compare. Identical output means TCC will hold on to its grants.
verify:
	@codesign -d -r- $(INSTALLED) 2>&1 | grep '^designated' || \
		echo "Not installed. Run: make install"

## settings: open the two privacy panes Flip needs
settings:
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

## autostart: start Flip at login
autostart: install
	@mkdir -p $(HOME)/Library/LaunchAgents
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>Label</key><string>$(BUNDLE_ID)</string>' \
		'	<key>ProgramArguments</key>' \
		'	<array><string>$(INSTALLED)/Contents/MacOS/$(APP_NAME)</string></array>' \
		'	<key>RunAtLoad</key><true/>' \
		'	<!-- Restart after a crash, but not after a deliberate quit: launchd' \
		'	     resurrecting an app the user just closed is a bug, not a feature.' \
		'	     Plain <true/> here also makes launchd log the job as "constantly' \
		'	     running and inherently inefficient" on every load. -->' \
		'	<key>KeepAlive</key>' \
		'	<dict><key>SuccessfulExit</key><false/></dict>' \
		'</dict>' \
		'</plist>' > $(AGENT)
	launchctl bootstrap gui/$$(id -u) $(AGENT)
	@echo "Flip will start at login."

unautostart:
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null || true
	@rm -f $(AGENT)
	@echo "Login item removed."

clean:
	rm -rf .build build
