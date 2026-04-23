import SwiftUI

struct AboutView: View {
	private var versionString: String {
		if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
			version != "development" {
			return "Version \(version)"
		}
		return "Development Version"
	}

	var body: some View {
		VStack(spacing: 12) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 96, height: 96)

			Text("io")
				.font(.title)
				.fontWeight(.bold)

			Text(versionString)

			HStack(spacing: 4) {
				Text("The MIT License")
				Text("·")
				Link(
					"Source Code",
					destination: URL(string: "https://github.com/idleberg/io")!
				)
			}
			.foregroundStyle(.secondary)
		}
		.multilineTextAlignment(.center)
		.padding(24)
		.frame(width: 320)
		.fixedSize()
	}
}
