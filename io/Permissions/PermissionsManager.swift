import AVFoundation
import AppKit
import Combine

final class PermissionsManager: ObservableObject {
	@Published private(set) var status: AVAuthorizationStatus

	init() {
		self.status = AVCaptureDevice.authorizationStatus(for: .audio)
	}

	@discardableResult
	func requestAccess() async -> Bool {
		let granted = await AVCaptureDevice.requestAccess(for: .audio)
		await MainActor.run {
			self.status = AVCaptureDevice.authorizationStatus(for: .audio)
		}
		return granted
	}

	func openSystemSettings() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
			return
		}
		NSWorkspace.shared.open(url)
	}
}
