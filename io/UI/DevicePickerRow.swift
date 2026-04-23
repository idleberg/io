import CoreAudio
import SwiftUI

struct DevicePickerRow: View {
	let label: String
	let icon: String
	let devices: [AudioDevice]
	@Binding var selection: AudioDeviceID

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.footnote)
				.foregroundStyle(.secondary)

			Picker(selection: $selection) {
				ForEach(devices) { device in
					Label(device.name, systemImage: icon)
						.tag(device.id)
				}
			} label: {
				EmptyView()
			}
			.labelsHidden()
			.pickerStyle(.menu)
			.accessibilityLabel("\(label) device")
		}
	}
}
