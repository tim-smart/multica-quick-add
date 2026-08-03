PROJECT := MulticaQuickAdd.xcodeproj
SCHEME := MulticaQuickAdd
DERIVED_DATA := .build/DerivedData

.PHONY: bootstrap generate open build test format lint clean

bootstrap: generate

generate:
	xcodegen generate

open: generate
	open "$(PROJECT)"

build: generate
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO build

test: generate
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO test

format:
	xcrun swift-format format --in-place --recursive MulticaQuickAdd MulticaQuickAddTests

lint:
	xcrun swift-format lint --strict --recursive MulticaQuickAdd MulticaQuickAddTests

clean:
	rm -rf "$(DERIVED_DATA)"
