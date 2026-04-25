.PHONY: install build

install:
	sudo xcodebuild -license accept
	swift package --disable-sandbox lefthook install

build:
	xcodebuild -scheme io \
		-configuration Release \
		-derivedDataPath build

lint:
	swiftlint lint \
		--strict
