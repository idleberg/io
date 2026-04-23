import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
	let id: AudioDeviceID
	let name: String
	let hasInput: Bool
	let hasOutput: Bool
}
