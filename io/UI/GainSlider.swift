import SwiftUI

struct GainSlider: View {
	@Binding var gainDB: Float

	private let range: ClosedRange<Float> = -40.0...20.0

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text("Gain")
					.font(.footnote)
					.foregroundStyle(.secondary)
				Spacer()
				Text(formattedValue)
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}

			HStack(spacing: 8) {
				Image(systemName: "speaker.fill")
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.accessibilityHidden(true)

				Slider(
					value: Binding(
						get: { gainDB },
						set: { gainDB = (($0 * 2).rounded()) / 2 }
					),
					in: range.lowerBound...range.upperBound
				)
				.controlSize(.small)
				.tint(Color.accentColor)
				.overlay {
					GeometryReader { proxy in
						// Thumb sits ~7pt inside each edge at .controlSize(.small);
						// the track runs between those insets.
						let inset: CGFloat = 7
						let trackWidth = max(0, proxy.size.width - inset * 2)
						let fraction = CGFloat(-range.lowerBound / (range.upperBound - range.lowerBound))
						Rectangle()
							.fill(Color.secondary.opacity(0.5))
							.frame(width: 1, height: 3)
							.position(
								x: inset + trackWidth * fraction,
								y: proxy.size.height - 1.5
							)
					}
					.allowsHitTesting(false)
				}
				.gesture(
					TapGesture(count: 2).onEnded {
						gainDB = 0
					}
				)
				.accessibilityLabel("Input gain")
				.accessibilityValue(formattedValue)

				Image(systemName: "speaker.wave.3.fill")
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.accessibilityHidden(true)
			}
		}
	}

	private var formattedValue: String {
		let rounded = (gainDB * 10).rounded() / 10
		if abs(rounded) < 0.05 { return "0 dB" }
		return String(format: "%+.1f dB", rounded)
	}
}
