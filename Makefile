# Build and package whisky-yaagl.
#
#   make build   compile the Release app with xcodebuild
#   make app     assemble build/whisky-yaagl.app
#   make dmg     wrap the app in a drag-to-Applications DMG
#   make notarize submit the DMG to Apple's notary service
#   make run     build and launch the app
#   make clean   remove build artifacts
#
# If a Developer ID Application identity is installed in the keychain (or
# SIGN_IDENTITY is set), builds are signed with it and keep TCC permissions
# across updates; otherwise they fall back to an ad-hoc signature. The DMG is
# written to build/whisky-yaagl-<version>.dmg, where <version> is read from the
# built app's Info.plist (MARKETING_VERSION in the Xcode project).

CONFIGURATION ?= Release
DERIVED_DATA  := build/DerivedData
APP           := build/whisky-yaagl.app

# Let `make dmg` sign the disk image with the same identity that
# Scripts/build_app.sh used for the app. An explicit environment value wins.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
export SIGN_IDENTITY

.PHONY: build app dmg notarize run clean

build:
	Scripts/build_app.sh \
		--configuration "$(CONFIGURATION)" \
		--derived-data "$(DERIVED_DATA)" \
		--build-only

app:
	Scripts/build_app.sh \
		--configuration "$(CONFIGURATION)" \
		--derived-data "$(DERIVED_DATA)" \
		--output "$(APP)"

dmg: app
	@VERSION="$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' '$(APP)/Contents/Info.plist')"; \
	echo "==> Packaging $(APP) ($(CONFIGURATION) $${VERSION})"; \
	Scripts/make_dmg.sh "$(APP)" "$$VERSION"; \
	if [ -n "$${SIGN_IDENTITY:-}" ]; then \
		echo "==> Signing build/whisky-yaagl-$${VERSION}.dmg"; \
		/usr/bin/codesign --force --timestamp --sign "$${SIGN_IDENTITY}" "build/whisky-yaagl-$${VERSION}.dmg"; \
	fi

notarize: dmg
	@VERSION="$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' '$(APP)/Contents/Info.plist')"; \
	Scripts/notarize.sh "build/whisky-yaagl-$${VERSION}.dmg"

run: app
	open "$(APP)"

clean:
	rm -rf build
