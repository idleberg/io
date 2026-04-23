import AVFoundation
import SwiftUI

struct ContentView: View {
	@ObservedObject var deviceManager: AudioDeviceManager
	@ObservedObject var routingEngine: AudioRoutingEngine
	@ObservedObject var permissions: PermissionsManager
	@ObservedObject var displayName: DisplayName

	var body: some View {
		VStack(spacing: 0) {
			header

			Divider()

			if permissions.status == .denied || permissions.status == .restricted {
				permissionContent
			} else {
				mainContent
			}
		}
		.frame(width: 288)
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 8) {
			(Text("io").font(.headline)
				+ Text(" – \(displayName.current)")
				.font(.subheadline)
				.foregroundColor(.secondary))
				.contentTransition(.opacity)
				.animation(.easeInOut(duration: 0.2), value: displayName.current)
			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
	}

	// MARK: - Main content

	private var mainContent: some View {
		VStack(spacing: 14) {
			DevicePickerRow(
				label: "Input",
				icon: "mic",
				devices: deviceManager.inputDevices,
				selection: Binding(
					get: { routingEngine.selectedInputID },
					set: { routingEngine.selectedInputID = $0 }
				)
			)

			DevicePickerRow(
				label: "Output",
				icon: "speaker.wave.2",
				devices: deviceManager.outputDevices,
				selection: Binding(
					get: { routingEngine.selectedOutputID },
					set: { routingEngine.selectedOutputID = $0 }
				)
			)

			GainSlider(
				gainDB: Binding(
					get: { routingEngine.gainDB },
					set: { routingEngine.gainDB = $0 }
				))

			LevelMeterView(
				meter: routingEngine.levelMeter,
				isActive: routingEngine.isActive,
				onToggle: togglePassThru
			)

			if let message = routingEngine.lastError {
				Text(message)
					.font(.caption)
					.foregroundStyle(.red)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}

	private func togglePassThru() {
		if routingEngine.isActive {
			routingEngine.setActive(false)
			return
		}

		switch permissions.status {
		case .authorized:
			routingEngine.setActive(true)
		case .notDetermined:
			Task {
				let granted = await permissions.requestAccess()
				if granted { routingEngine.setActive(true) }
			}
		case .denied, .restricted:
			permissions.openSystemSettings()
		@unknown default:
			permissions.openSystemSettings()
		}
	}

	// MARK: - Permission view

	private var permissionContent: some View {
		VStack(spacing: 12) {
			Image(systemName: "mic.slash")
				.font(.system(size: 28, weight: .regular))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			Text("Microphone Access Required")
				.font(.headline)
				.multilineTextAlignment(.center)

			Text("io needs microphone access to route audio from an input device to an output device.")
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)

			Button("Open System Settings") {
				permissions.openSystemSettings()
			}
			.controlSize(.regular)
			.buttonStyle(.borderedProminent)
			.accessibilityHint("Opens the Microphone privacy pane in System Settings")
		}
		.padding(20)
	}
}
