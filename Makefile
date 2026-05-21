.PHONY: gen build run clean test fmt

# Generate Xcode project from project.yml
gen:
	xcodegen generate

# Build Debug
build: gen
	xcodebuild -project PanBar.xcodeproj -scheme PanBar -configuration Debug build

# Build Release
release: gen
	xcodebuild -project PanBar.xcodeproj -scheme PanBar -configuration Release build

# Run unit tests
test: gen
	xcodebuild -project PanBar.xcodeproj -scheme PanBar -destination 'platform=macOS' test

# Launch the built app
run: build
	@APP_PATH=$$(xcodebuild -project PanBar.xcodeproj -scheme PanBar -showBuildSettings | grep -m1 "BUILT_PRODUCTS_DIR" | awk -F= '{ print $$2 }' | xargs); \
	open "$$APP_PATH/PanBar.app"

# Clean build artifacts
clean:
	xcodebuild -project PanBar.xcodeproj -scheme PanBar clean || true
	rm -rf build/ DerivedData/

# Open in Xcode
open: gen
	open PanBar.xcodeproj
