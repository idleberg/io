import AVFoundation
import Combine
import CoreAudio
import Foundation

final class AudioDeviceManager: ObservableObject {
	@Published private(set) var inputDevices: [AudioDevice] = []
	@Published private(set) var outputDevices: [AudioDevice] = []
	@Published private(set) var defaultInputID: AudioDeviceID = 0
	@Published private(set) var defaultOutputID: AudioDeviceID = 0

	private let permissions: PermissionsManager
	private var cancellables = Set<AnyCancellable>()
	private var deviceListListener: AudioObjectPropertyListenerBlock?
	private var defaultInputListener: AudioObjectPropertyListenerBlock?
	private var defaultOutputListener: AudioObjectPropertyListenerBlock?

	init(permissions: PermissionsManager) {
		self.permissions = permissions
		reload()
		installListeners()

		// When the user grants microphone access, re-enumerate so the input
		// picker can drop devices that don't actually expose input streams.
		permissions.$status
			.removeDuplicates()
			.sink { [weak self] _ in self?.reload() }
			.store(in: &cancellables)
	}

	deinit {
		removeListeners()
	}

	// MARK: - Public

	func isInputValid(_ id: AudioDeviceID) -> Bool {
		inputDevices.contains { $0.id == id }
	}

	func isOutputValid(_ id: AudioDeviceID) -> Bool {
		outputDevices.contains { $0.id == id }
	}

	// MARK: - Reload

	func reload() {
		let canClassifyInputs = permissions.status == .authorized
		let ids = (try? Self.allDeviceIDs()) ?? []
		let devices = ids.compactMap { Self.makeDevice(id: $0, canClassifyInputs: canClassifyInputs) }

		let inputs =
			devices
			.filter(\.hasInput)
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		let outputs =
			devices
			.filter(\.hasOutput)
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

		let defaultIn = (try? Self.readDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)) ?? 0
		let defaultOut = (try? Self.readDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)) ?? 0

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.inputDevices = inputs
			self.outputDevices = outputs
			self.defaultInputID = defaultIn
			self.defaultOutputID = defaultOut
		}
	}

	// MARK: - Enumeration

	private static func allDeviceIDs() throws -> [AudioDeviceID] {
		let address = AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDevices,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain
		)
		return try CoreAudioHelpers.getPropertyArray(AudioObjectID(kAudioObjectSystemObject), address)
	}

	private static func makeDevice(id: AudioDeviceID, canClassifyInputs: Bool) -> AudioDevice? {
		let nameAddress = AudioObjectPropertyAddress(
			mSelector: kAudioObjectPropertyName,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain
		)

		guard let name = try? CoreAudioHelpers.getString(id, nameAddress) else {
			return nil
		}

		let hasOutput = CoreAudioHelpers.hasStreams(on: id, scope: kAudioDevicePropertyScopeOutput)

		// Querying input-scope streams triggers a microphone-permission prompt
		// per device on recent macOS. Until the user has granted access, treat
		// anything that isn't output-only as potentially an input — the picker
		// over-reports, but no TCC prompt is fired during enumeration.
		let hasInput: Bool
		if canClassifyInputs {
			hasInput = CoreAudioHelpers.hasStreams(on: id, scope: kAudioDevicePropertyScopeInput)
		} else {
			hasInput = !hasOutput
		}

		guard hasInput || hasOutput else { return nil }

		return AudioDevice(id: id, name: name, hasInput: hasInput, hasOutput: hasOutput)
	}

	private static func readDefaultDevice(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
		let address = AudioObjectPropertyAddress(
			mSelector: selector,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain
		)
		return try CoreAudioHelpers.getProperty(
			AudioObjectID(kAudioObjectSystemObject),
			address,
			default: AudioDeviceID(0)
		)
	}

	// MARK: - Listeners

	private static let listenerSelectors: [AudioObjectPropertySelector] = [
		kAudioHardwarePropertyDevices,
		kAudioHardwarePropertyDefaultInputDevice,
		kAudioHardwarePropertyDefaultOutputDevice,
	]

	private func installListeners() {
		let system = AudioObjectID(kAudioObjectSystemObject)
		let reloadBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
			self?.reload()
		}

		for selector in Self.listenerSelectors {
			var address = AudioObjectPropertyAddress(
				mSelector: selector,
				mScope: kAudioObjectPropertyScopeGlobal,
				mElement: kAudioObjectPropertyElementMain
			)
			AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, reloadBlock)
		}

		deviceListListener = reloadBlock
		defaultInputListener = reloadBlock
		defaultOutputListener = reloadBlock
	}

	private func removeListeners() {
		let system = AudioObjectID(kAudioObjectSystemObject)
		guard let listener = deviceListListener else { return }

		for selector in Self.listenerSelectors {
			var address = AudioObjectPropertyAddress(
				mSelector: selector,
				mScope: kAudioObjectPropertyScopeGlobal,
				mElement: kAudioObjectPropertyElementMain
			)
			AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, listener)
		}
	}
}
