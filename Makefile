APP_NAME := LimitBar
APP_BUNDLE_NAME := Limit Bar
LEGACY_APP_DIR := build/CodexLimitBar.app
ROOT := $(shell /bin/pwd -P)
SPM_BUILD_DIR := $(ROOT)/.spm-build
BUILD_DIR := $(SPM_BUILD_DIR)/release
APP_DIR := build/$(APP_BUNDLE_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
DMG_STAGING := build/dmg-staging
DMG_PATH := build/$(APP_BUNDLE_NAME).dmg
SWIFT_BUILD := CLANG_MODULE_CACHE_PATH="$(SPM_BUILD_DIR)/clang-module-cache" swift build -c release --cache-path "$(SPM_BUILD_DIR)/swiftpm-cache" --scratch-path "$(SPM_BUILD_DIR)" --manifest-cache local --disable-sandbox

.PHONY: build app run dmg clean

build:
	$(SWIFT_BUILD)

app: build
	rm -rf "$(APP_DIR)" "$(LEGACY_APP_DIR)"
	mkdir -p "$(MACOS)" "$(RESOURCES)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS)/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/AppIcon.icns "$(RESOURCES)/AppIcon.icns"
	cp Resources/StatusIcon.png "$(RESOURCES)/StatusIcon.png"
	codesign --force --deep --sign - "$(APP_DIR)"

run: app
	open "$(APP_DIR)"

dmg: app
	rm -rf "$(DMG_STAGING)" "$(DMG_PATH)"
	mkdir -p "$(DMG_STAGING)"
	cp -r "$(APP_DIR)" "$(DMG_STAGING)/"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_BUNDLE_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG_PATH)"
	rm -rf "$(DMG_STAGING)"
	@echo "DMG ready: $(DMG_PATH)"

clean:
	rm -rf build .build .spm-build
