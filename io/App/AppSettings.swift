import Combine
import Foundation

final class AppSettings: ObservableObject {
	static let shared = AppSettings()

	private enum Keys {
		static let selectedInputDeviceID = "selectedInputDeviceID"
		static let selectedOutputDeviceID = "selectedOutputDeviceID"
		static let gainDB = "gainDB"
		static let launchAtLogin = "launchAtLogin"

		static let all: [String] = [
			selectedInputDeviceID, selectedOutputDeviceID, gainDB, launchAtLogin
		]
	}

	@Published var selectedInputDeviceID: Int {
		didSet { UserDefaults.standard.set(selectedInputDeviceID, forKey: Keys.selectedInputDeviceID) }
	}

	@Published var selectedOutputDeviceID: Int {
		didSet { UserDefaults.standard.set(selectedOutputDeviceID, forKey: Keys.selectedOutputDeviceID) }
	}

	@Published var gainDB: Float {
		didSet { UserDefaults.standard.set(gainDB, forKey: Keys.gainDB) }
	}

	@Published var launchAtLogin: Bool {
		didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
	}

	private init() {
		let defaults = UserDefaults.standard
		self.selectedInputDeviceID = defaults.integer(forKey: Keys.selectedInputDeviceID)
		self.selectedOutputDeviceID = defaults.integer(forKey: Keys.selectedOutputDeviceID)
		self.gainDB = defaults.object(forKey: Keys.gainDB) as? Float ?? 0.0
		self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
	}

	func reset() {
		let defaults = UserDefaults.standard
		Keys.all.forEach { defaults.removeObject(forKey: $0) }

		selectedInputDeviceID = 0
		selectedOutputDeviceID = 0
		gainDB = 0
		launchAtLogin = false
	}
}
