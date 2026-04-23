import SwiftUI

struct LevelMeterView: View {
	@ObservedObject var meter: LevelMeter
	let isActive: Bool
	let onToggle: () -> Void

	var body: some View {
		HStack(spacing: 6) {
			LevelBar(
				level: channelLevel(0),
				peak: channelPeak(0),
				direction: .rightToLeft,
				isActive: isActive
			)
			.frame(height: 22)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Left channel level")
			.accessibilityValue(accessibilityValue(for: channelLevel(0)))

			ListenButton(isActive: isActive, action: onToggle)

			LevelBar(
				level: channelLevel(1),
				peak: channelPeak(1),
				direction: .leftToRight,
				isActive: isActive
			)
			.frame(height: 22)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Right channel level")
			.accessibilityValue(accessibilityValue(for: channelLevel(1)))
		}
	}

	private func channelLevel(_ index: Int) -> Float {
		if meter.displayLevels.isEmpty { return LevelMeter.minDB }
		if index >= meter.displayLevels.count {
			return meter.displayLevels[0]
		}
		return meter.displayLevels[index]
	}

	private func channelPeak(_ index: Int) -> Float {
		if meter.peakLevels.isEmpty { return LevelMeter.minDB }
		if index >= meter.peakLevels.count {
			return meter.peakLevels[0]
		}
		return meter.peakLevels[index]
	}

	private func accessibilityValue(for level: Float) -> String {
		guard isActive else { return "Inactive" }
		return String(format: "%.0f dB", level)
	}
}

// MARK: - Listen button

private struct ListenButton: View {
	let isActive: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text("Listen")
				.font(.callout.weight(.semibold))
				.lineLimit(1)
				.fixedSize(horizontal: true, vertical: false)
				.foregroundStyle(isActive ? Color.white : Color.primary)
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.background(
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.fill(isActive ? Color.green : Color(nsColor: .controlBackgroundColor))
				)
				.overlay(
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.stroke(
							isActive ? Color.green.opacity(0.4) : Color(nsColor: .separatorColor),
							lineWidth: 0.5
						)
				)
				.shadow(color: isActive ? .green.opacity(0.4) : .clear, radius: 4)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(isActive ? "Stop listening" : "Start listening")
		.accessibilityHint("Routes audio from the selected input to the selected output")
	}
}

// MARK: - Level bar

enum MeterDirection {
	case leftToRight
	case rightToLeft
}

private struct LevelBar: View {
	let level: Float
	let peak: Float
	let direction: MeterDirection
	let isActive: Bool

	private let segmentCount = 18
	private let segmentSpacing: CGFloat = 2

	var body: some View {
		GeometryReader { proxy in
			let segmentWidth = max(1, (proxy.size.width - segmentSpacing * CGFloat(segmentCount - 1)) / CGFloat(segmentCount))
			let litCount = litSegmentCount
			let peakIndex = peakSegmentIndex

			HStack(spacing: segmentSpacing) {
				ForEach(orderedIndices, id: \.self) { index in
					let isLit = isActive && index < litCount
					let isPeak = isActive && index == peakIndex && peak > LevelMeter.minDB
					RoundedRectangle(cornerRadius: segmentWidth / 2.5, style: .continuous)
						.fill(color(for: index, lit: isLit, peak: isPeak))
						.frame(width: segmentWidth)
				}
			}
			.frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
		}
	}

	private var orderedIndices: [Int] {
		switch direction {
		case .leftToRight:
			return Array(0..<segmentCount)
		case .rightToLeft:
			return (0..<segmentCount).reversed()
		}
	}

	private var litSegmentCount: Int {
		guard isActive else { return 0 }
		let clamped = max(LevelMeter.minDB, min(LevelMeter.maxDB, level))
		let normalized = (clamped - LevelMeter.minDB) / (LevelMeter.maxDB - LevelMeter.minDB)
		return Int((normalized * Float(segmentCount)).rounded())
	}

	private var peakSegmentIndex: Int {
		guard isActive else { return -1 }
		let clamped = max(LevelMeter.minDB, min(LevelMeter.maxDB, peak))
		let normalized = (clamped - LevelMeter.minDB) / (LevelMeter.maxDB - LevelMeter.minDB)
		let index = Int((normalized * Float(segmentCount)).rounded()) - 1
		return max(-1, min(segmentCount - 1, index))
	}

	private func color(for index: Int, lit: Bool, peak: Bool) -> Color {
		let zoneColor = zoneColor(for: index)

		if peak {
			return zoneColor.opacity(1.0)
		}
		if lit {
			return zoneColor.opacity(0.95)
		}
		return Color(nsColor: .quaternaryLabelColor)
	}

	private func zoneColor(for index: Int) -> Color {
		let normalized = Float(index + 1) / Float(segmentCount)
		let dbValue = LevelMeter.minDB + normalized * (LevelMeter.maxDB - LevelMeter.minDB)

		if dbValue >= -3 { return .red }
		if dbValue >= -12 { return .orange }
		return .green
	}
}
