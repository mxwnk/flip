APP_NAME  := Flip
BUNDLE_ID := dev.mxwnk.Flip
IDENTITY  := Flip Local Signing
VERSION   := 0.1.0

BINARY    := .build/release/$(APP_NAME)
BUNDLE    := build/$(APP_NAME).app
INSTALLED := $(HOME)/Applications/$(APP_NAME).app
AGENT     := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

.PHONY: all cert uncert build bundle sign install run stop restart logs verify settings autostart unautostart clean

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
# Launched with `open` rather than directly, so launchd owns the process and TCC
# attributes the grants to Flip instead of to the terminal that started it.
run: install
	open -a $(INSTALLED)
	@echo "Running. Follow along with: make logs"

## stop: quit a running instance
stop:
	@killall $(APP_NAME) 2>/dev/null || true

restart: stop run

## logs: follow Flip's log output
logs:
	log stream --level debug --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

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
		'	<key>KeepAlive</key><true/>' \
		'</dict>' \
		'</plist>' > $(AGENT)
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(AGENT)
	@echo "Flip will start at login."

unautostart:
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null || true
	@rm -f $(AGENT)
	@echo "Login item removed."

clean:
	rm -rf .build build
