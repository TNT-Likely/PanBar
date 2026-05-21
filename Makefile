# PanBar Makefile
#
# 本地开发:     make run
# 在 Xcode 打开: make open
# 出包:         make release-build VERSION=0.1.0
# 签名+公证:    make notarize VERSION=0.1.0    (需要 .env 中的凭据,见 docs/RELEASING.md)
# 打 DMG:       make dmg VERSION=0.1.0

SHELL := /bin/bash
PROJECT := PanBar.xcodeproj
SCHEME := PanBar
DERIVED := build/dd
APP_NAME := PanBar
VERSION ?= 0.1.0
BUILD_DIR := build/Release
APP_PATH := $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH := build/$(APP_NAME)-$(VERSION).dmg
ZIP_PATH := build/$(APP_NAME)-$(VERSION).zip

# 签名 / 公证凭据(放 .env,不入库)
-include .env
export

.PHONY: help
help:
	@echo "PanBar build targets:"
	@echo "  make gen              # 重新生成 Xcode 项目"
	@echo "  make build            # Debug 构建"
	@echo "  make run              # 构建并启动"
	@echo "  make open             # 在 Xcode 中打开"
	@echo "  make icons            # 重新生成 AppIcon"
	@echo "  make release-build    # Release 构建"
	@echo "  make sign             # 用 Developer ID 签名(需 .env: DEV_ID)"
	@echo "  make notarize         # 公证(需 .env: NOTARY_KEYCHAIN_PROFILE)"
	@echo "  make dmg              # 打包成 DMG"
	@echo "  make zip              # 打包成 ZIP(给 Sparkle 用)"
	@echo "  make appcast          # 生成 appcast.xml 条目"
	@echo "  make clean            # 清理产物"

.PHONY: gen
gen:
	xcodegen generate

.PHONY: build
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES \
		build

.PHONY: run
run: build
	open $(DERIVED)/Build/Products/Debug/$(APP_NAME).app

.PHONY: open
open: gen
	open $(PROJECT)

.PHONY: icons
icons:
	swift scripts/generate-icons.swift

.PHONY: release-build
release-build: gen
	mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED) \
		-archivePath build/$(APP_NAME).xcarchive \
		MARKETING_VERSION=$(VERSION) \
		CURRENT_PROJECT_VERSION=$(shell date +%s) \
		archive
	xcodebuild \
		-exportArchive \
		-archivePath build/$(APP_NAME).xcarchive \
		-exportOptionsPlist scripts/export-options.plist \
		-exportPath $(BUILD_DIR)
	@echo "✓ Built $(APP_PATH)"

.PHONY: sign
sign:
	@test -n "$(DEV_ID)" || (echo "✗ DEV_ID not set in .env" && exit 1)
	codesign \
		--force \
		--options=runtime \
		--timestamp \
		--sign "$(DEV_ID)" \
		--entitlements PanBar/Resources/PanBar.entitlements \
		--deep \
		$(APP_PATH)
	codesign --verify --deep --strict --verbose=2 $(APP_PATH)
	@echo "✓ Signed"

.PHONY: notarize
notarize: zip
	@test -n "$(NOTARY_KEYCHAIN_PROFILE)" || (echo "✗ NOTARY_KEYCHAIN_PROFILE not set in .env" && exit 1)
	xcrun notarytool submit $(ZIP_PATH) \
		--keychain-profile "$(NOTARY_KEYCHAIN_PROFILE)" \
		--wait
	xcrun stapler staple $(APP_PATH)
	xcrun stapler validate $(APP_PATH)
	@echo "✓ Notarized & stapled"

.PHONY: zip
zip:
	@test -d "$(APP_PATH)" || (echo "✗ $(APP_PATH) not found — run 'make release-build' first" && exit 1)
	cd $(BUILD_DIR) && ditto -c -k --keepParent --sequesterRsrc $(APP_NAME).app ../$(APP_NAME)-$(VERSION).zip
	@echo "✓ ZIP at $(ZIP_PATH)"

.PHONY: dmg
dmg:
	@test -d "$(APP_PATH)" || (echo "✗ $(APP_PATH) not found — run 'make release-build' first" && exit 1)
	@command -v create-dmg >/dev/null || (echo "✗ create-dmg not installed. brew install create-dmg" && exit 1)
	rm -f $(DMG_PATH)
	create-dmg \
		--volname "$(APP_NAME) $(VERSION)" \
		--window-pos 200 120 \
		--window-size 540 380 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 140 190 \
		--app-drop-link 400 190 \
		--no-internet-enable \
		$(DMG_PATH) \
		$(APP_PATH)
	@echo "✓ DMG at $(DMG_PATH)"

.PHONY: appcast
appcast:
	@test -d build/sparkle-tools/Sparkle.app || (echo "Run: make install-sparkle-tools" && exit 1)
	build/sparkle-tools/Sparkle.app/Contents/Resources/generate_appcast build/

.PHONY: install-sparkle-tools
install-sparkle-tools:
	@mkdir -p build/sparkle-tools
	@echo "Download Sparkle release tools from:"
	@echo "  https://github.com/sparkle-project/Sparkle/releases"
	@echo "Extract Sparkle.app to build/sparkle-tools/"

.PHONY: clean
clean:
	rm -rf build/ DerivedData/ $(DERIVED)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
