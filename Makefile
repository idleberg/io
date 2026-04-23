.PHONY: install build clean lint fix-lint format format-check

install:
	sudo xcodebuild -license accept

build:
	xcodebuild -scheme io \
		-configuration Release \
		-derivedDataPath build

clean:
	rm -rf build DerivedData

lint:
	swiftlint lint \
		--strict

fix-lint:
	swiftlint lint \
		--strict \
		--fix

format:
	swift format --in-place --recursive io

format-check:
	swift format lint --strict --recursive io
