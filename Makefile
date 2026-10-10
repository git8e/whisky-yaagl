# Build and package whisky-yaagl.
#
#   make build   compile the Release app with xcodebuild
#   make app     assemble build/whisky-yaagl.app (ad-hoc signed)
#   make dmg     wrap the app in a drag-to-Applications DMG
#   make run     build and launch the app
#   make clean   remove build artifacts
#
# The DMG is written to build/whisky-yaagl-<version>.dmg, where <version> is
# read from the built app's Info.plist (MARKETING_VERSION in the Xcode project).

CONFIGURATION ?= Release
DERIVED_DATA  := build/DerivedData
PRODUCT       := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/whisky-yaagl.app
APP           := build/whisky-yaagl.app

.PHONY: build app dmg run clean

build:
	SKIP_SWIFTLINT=1 xcodebuild \
		-project Whisky.xcodeproj \
		-scheme Whisky \
		-configuration $(CONFIGURATION) \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY="" \
		build

app: build
	rm -rf "$(APP)"
	ditto "$(PRODUCT)" "$(APP)"
	# Ad-hoc sign so macOS will run it after quarantine removal.
	/usr/bin/codesign --force --deep --sign - "$(APP)"
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(APP)"

dmg: app
	@VERSION="$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' '$(APP)/Contents/Info.plist')"; \
	echo "==> Packaging $(APP) ($(CONFIGURATION) $${VERSION})"; \
	Scripts/make_dmg.sh "$(APP)" "$$VERSION"

run: app
	open "$(APP)"

clean:
	rm -rf build
