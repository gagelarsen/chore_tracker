SCHEME := Chorez
# Override on the command line: `make test DESTINATION="platform=iOS Simulator,name=iPhone 16"`
DESTINATION ?= platform=iOS Simulator,name=iPhone 17
RESULT_BUNDLE := build/Chorez.xcresult

.PHONY: project build test lint clean help

help:
	@echo "Targets:"
	@echo "  make project   Generate Chorez.xcodeproj from project.yml"
	@echo "  make build     Build the app (regenerates project first)"
	@echo "  make test      Run unit + UI tests (regenerates project first)"
	@echo "  make lint      Run SwiftLint over the sources"
	@echo "  make clean     Remove build artifacts and the generated project"

project:
	xcodegen generate

build: project
	xcodebuild build \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		CODE_SIGNING_ALLOWED=NO

test: project
	mkdir -p build
	rm -rf $(RESULT_BUNDLE)
	xcodebuild test \
		-scheme $(SCHEME) \
		-destination "$(DESTINATION)" \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO

lint:
	swiftlint --strict

clean:
	rm -rf build/ .build/ .swiftpm/
	rm -rf Chorez.xcodeproj Chorez.xcworkspace
	rm -f Package.resolved
