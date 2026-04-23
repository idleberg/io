import Foundation
import ServiceManagement

enum LaunchAtLogin {
	@discardableResult
	static func setEnabled(_ enabled: Bool) -> Bool {
		do {
			if enabled {
				if SMAppService.mainApp.status == .enabled { return true }
				try SMAppService.mainApp.register()
			} else {
				try SMAppService.mainApp.unregister()
			}
			return true
		} catch {
			NSLog("LaunchAtLogin: failed to update status — \(error.localizedDescription)")
			return false
		}
	}
}
