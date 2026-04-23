.PHONY: install build

install:
	sudo xcodebuild -license accept

build:
	xcodebuild -scheme Cleansi \
		-configuration Release \
		-derivedDataPath build

fix-lint:
	swiftlint lint \
		--strict \
		--fix

lint:
	swiftlint lint \
		--strict
