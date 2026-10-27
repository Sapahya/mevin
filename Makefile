PROJECT := Mevin.xcodeproj
SCHEME := Mevin
DERIVED := build/DerivedData
DEBUG_APP := $(DERIVED)/Build/Products/Debug/Mevin.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Mevin.app

# V11 Change 1: one signing identity for every build, so macOS keeps Mevin's
# Accessibility permission across rebuilds. Until the certificate exists in the
# login keychain, builds stay ad hoc ("-") as before.
SIGN_NAME := Mevin Local Signing
SIGN_FLAGS := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"$(SIGN_NAME)"' && echo 'CODE_SIGN_IDENTITY="$(SIGN_NAME)" CODE_SIGN_STYLE=Manual')

SMOKE_SRCS := \
	Mevin/Models/Models.swift \
	Mevin/Models/ProfileColor.swift \
	Mevin/Models/MevinConfig.swift \
	Mevin/Persistence/JSONProfileStore.swift \
	Mevin/Services/LaunchService.swift \
	Mevin/Services/WindowClassifier.swift \
	Mevin/Services/AccessibilityWindowControl.swift \
	Mevin/Services/WindowService.swift \
	Mevin/Services/RoleTeardown.swift \
	Mevin/Services/TerminalStartupService.swift \
	Mevin/Services/TerminalTabMatcher.swift \
	Mevin/Services/TerminalCommandFingerprint.swift \
	Mevin/Services/ChromeService.swift \
	Mevin/Services/ChromeWindowService.swift \
	Mevin/Services/ChromeProfileOCR.swift \
	Mevin/Services/ChromeProfileAccessibilityReader.swift \
	Mevin/Services/ClaudeService.swift \
	Mevin/Services/FigmaService.swift \
	Mevin/Services/AppMatcher.swift \
	Mevin/Services/AIProvider.swift \
	Mevin/Services/SwitchPlan.swift \
	Mevin/Services/SlackService.swift \
	Mevin/Services/SessionCapture.swift \
	Mevin/Services/SessionClock.swift \
	Mevin/Services/RoleUsageStats.swift \
	Mevin/Services/KeepOpenPanelHelper.swift \
	Tests/StoreSmokeTest.swift

.PHONY: build release run install smoke clean spike-chrome-detect spike-chrome-reuse

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) $(SIGN_FLAGS) build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED) $(SIGN_FLAGS) build

run: build
	open $(DEBUG_APP)

install: release
	rm -rf /Applications/Mevin.app
	cp -R $(RELEASE_APP) /Applications/Mevin.app
	open /Applications/Mevin.app

smoke:
	@mkdir -p build
	xcrun swiftc -parse-as-library -o build/smoke $(SMOKE_SRCS) \
		-framework AppKit -framework Vision -framework ApplicationServices -framework ScreenCaptureKit
	./build/smoke

spike-chrome-detect:
	@mkdir -p build
	xcrun swiftc -o build/spike-chrome-detect \
		Mevin/Models/Models.swift \
		Mevin/Models/ProfileColor.swift \
		Mevin/Models/MevinConfig.swift \
		Mevin/Services/LaunchService.swift \
		Mevin/Services/WindowClassifier.swift \
		Mevin/Services/AccessibilityWindowControl.swift \
		Mevin/Services/ChromeService.swift \
		Mevin/Services/ChromeProfileOCR.swift \
		Mevin/Services/ChromeProfileAccessibilityReader.swift \
		Mevin/Services/ChromeWindowService.swift \
		Mevin/Services/ClaudeService.swift \
		Mevin/Services/FigmaService.swift \
		Mevin/Services/SlackService.swift \
		Mevin/Services/RoleUsageStats.swift \
		Tests/ChromeProfileDetectSpike.swift \
		-framework AppKit -framework Vision -framework ApplicationServices -framework ScreenCaptureKit
	./build/spike-chrome-detect

spike-chrome-reuse:
	@mkdir -p build
	xcrun swiftc -o build/spike-chrome-reuse \
		Mevin/Models/Models.swift \
		Mevin/Models/ProfileColor.swift \
		Mevin/Models/MevinConfig.swift \
		Mevin/Services/LaunchService.swift \
		Mevin/Services/WindowClassifier.swift \
		Mevin/Services/AccessibilityWindowControl.swift \
		Mevin/Services/ChromeService.swift \
		Mevin/Services/ChromeWindowService.swift \
		Mevin/Services/ClaudeService.swift \
		Mevin/Services/FigmaService.swift \
		Mevin/Services/SlackService.swift \
		Mevin/Services/RoleUsageStats.swift \
		Tests/ChromeProfileReuseSpike.swift \
		-framework AppKit -framework ApplicationServices
	./build/spike-chrome-reuse

clean:
	rm -rf build
