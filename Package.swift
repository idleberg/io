// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "io-dev-tools",
	dependencies: [
		.package(url: "https://github.com/csjones/lefthook-plugin.git", exact: "2.1.6")
	]
)
