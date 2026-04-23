.PHONY: install build

install:
	sudo xcodebuild -license accept

build:
	xcodebuild -scheme io \
		-configuration Release \
		-derivedDataPath build

fix-lint:
	swiftlint lint \
		--fix

lint:
	swiftlint lint \
		--strict
