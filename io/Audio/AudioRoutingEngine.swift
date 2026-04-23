import AVFoundation
import Combine
import CoreAudio
import Foundation

enum AudioRoutingError: LocalizedError {
	case setDeviceFailed(OSStatus, scope: String)
	case invalidFormat(sampleRate: Double, channels: UInt32)
	case inputUnavailable
	case deviceBusy(reason: String)
	case engineException(String)

	var errorDescription: String? {
		switch self {
		case .setDeviceFailed(let status, let scope):
			return "Couldn't assign \(scope) device (OSStatus \(status))"
		case .invalidFormat(let sampleRate, let channels):
			return "Invalid audio format (\(Int(sampleRate)) Hz, \(channels) ch)"
		case .inputUnavailable:
			return "No input device available"
		case .deviceBusy(let reason):
			return "Device is unavailable — \(reason)"
		case .engineException(let reason):
			return "Audio engine error — \(reason)"
		}
	}
}

final class AudioRoutingEngine: ObservableObject {
	// MARK: - Published state

	@Published var selectedInputID: AudioDeviceID = 0 {
		didSet {
			guard oldValue != selectedInputID else { return }
			AppSettings.shared.selectedInputDeviceID = Int(selectedInputID)
			scheduleRestart()
		}
	}

	@Published var selectedOutputID: AudioDeviceID = 0 {
		didSet {
			guard oldValue != selectedOutputID else { return }
			AppSettings.shared.selectedOutputDeviceID = Int(selectedOutputID)
			scheduleRestart()
		}
	}

	@Published private(set) var isActive: Bool = false
	@Published private(set) var lastError: String?

	@Published var gainDB: Float = 0.0 {
		didSet {
			gainNode.globalGain = gainDB
			AppSettings.shared.gainDB = gainDB
		}
	}

	let levelMeter = LevelMeter()

	var onPassThruChange: ((Bool) -> Void)?

	// MARK: - Private state

	// On macOS, a single AVAudioEngine shares one HAL audio unit for input and
	// output, so you can't point the input and output at different devices on
	// the same engine. We use two engines bridged by an AVAudioPlayerNode.
	private let captureEngine = AVAudioEngine()
	private let playbackEngine = AVAudioEngine()
	private let playerNode = AVAudioPlayerNode()
	private let gainNode = AVAudioUnitEQ()

	private var restartWorkItem: DispatchWorkItem?
	private var wasActiveBeforeSleep = false
	private var isRebuilding = false
	private var configChangeObservers: [NSObjectProtocol] = []

	// MARK: - Lifecycle

	init() {
		playbackEngine.attach(playerNode)
		playbackEngine.attach(gainNode)
		gainNode.globalGain = gainDB
		observeConfigurationChanges()
	}

	deinit {
		configChangeObservers.forEach { NotificationCenter.default.removeObserver($0) }
		stopRouting()
	}

	// MARK: - Public API

	func setActive(_ active: Bool) {
		if active {
			tryStart(retriesRemaining: 1)
		} else {
			stopRouting()
		}
	}

	private func tryStart(retriesRemaining: Int) {
		do {
			try startRouting()
		} catch {
			// Bluetooth devices commonly need a second attempt: the first one
			// wakes the HAL and the second catches the now-ready format.
			if retriesRemaining > 0 {
				teardownGraph()
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
					self?.tryStart(retriesRemaining: retriesRemaining - 1)
				}
				return
			}
			handleFailure(error, context: "start")
		}
	}

	func startRouting() throws {
		if isActive { return }
		try configureGraph()
		try Self.guardException { try self.playbackEngine.start() }
		try Self.guardException { try self.captureEngine.start() }
		try Self.guardException { self.playerNode.play() }
		levelMeter.start()
		isActive = true
		lastError = nil
		onPassThruChange?(true)
	}

	func stopRouting() {
		teardownGraph()
		levelMeter.stop()
		levelMeter.reset()
		updateInactiveState()
	}

	func restartRouting() throws {
		guard isActive else { return }
		teardownGraph()
		try configureGraph()
		try Self.guardException { try self.playbackEngine.start() }
		try Self.guardException { try self.captureEngine.start() }
		try Self.guardException { self.playerNode.play() }
	}

	func suspendForSleep() {
		wasActiveBeforeSleep = isActive
		if isActive { stopRouting() }
	}

	func resumeAfterWake() {
		guard wasActiveBeforeSleep else { return }
		wasActiveBeforeSleep = false
		setActive(true)
	}

	// MARK: - Graph configuration

	private func configureGraph() throws {
		guard !isRebuilding else { return }
		isRebuilding = true
		defer { isRebuilding = false }

		guard selectedInputID != 0, selectedOutputID != 0 else {
			throw AudioRoutingError.inputUnavailable
		}

		try Self.setDevice(selectedInputID, for: captureEngine.inputNode, scope: "input")
		try Self.setDevice(selectedOutputID, for: playbackEngine.outputNode, scope: "output")

		let inputFormat = captureEngine.inputNode.outputFormat(forBus: 0)
		guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
			throw AudioRoutingError.invalidFormat(
				sampleRate: inputFormat.sampleRate,
				channels: inputFormat.channelCount
			)
		}

		try Self.guardException {
			self.playbackEngine.disconnectNodeInput(self.gainNode)
			self.playbackEngine.disconnectNodeOutput(self.playerNode)
			self.playbackEngine.disconnectNodeOutput(self.gainNode)

			self.playbackEngine.connect(self.playerNode, to: self.gainNode, format: inputFormat)
			self.playbackEngine.connect(self.gainNode, to: self.playbackEngine.mainMixerNode, format: inputFormat)
		}

		let outputFormat = playbackEngine.outputNode.inputFormat(forBus: 0)
		if outputFormat.sampleRate > 0, outputFormat.channelCount > 0 {
			try Self.guardException {
				self.playbackEngine.disconnectNodeOutput(self.playbackEngine.mainMixerNode)
				self.playbackEngine.connect(
					self.playbackEngine.mainMixerNode,
					to: self.playbackEngine.outputNode,
					format: outputFormat
				)
			}
		}

		// Tap the input; forward buffers to the player and metering. Copy each
		// buffer before scheduling — AVAudioEngine reuses the tap's buffer
		// memory, so scheduling the original causes it to be overwritten
		// before it's played back.
		let tapFormat = inputFormat
		try Self.guardException {
			self.captureEngine.inputNode.removeTap(onBus: 0)
			self.captureEngine.inputNode.installTap(
				onBus: 0,
				bufferSize: 512,
				format: tapFormat
			) { [weak self] buffer, _ in
				guard let self else { return }
				self.levelMeter.process(buffer)
				guard buffer.format.isEqual(tapFormat),
					let copy = Self.copyBuffer(buffer)
				else { return }
				// Scheduling on a player whose output format no longer matches
				// the buffer raises NSException; guard it too.
				_ = try? Self.guardException {
					self.playerNode.scheduleBuffer(copy, completionHandler: nil)
				}
			}
		}

		playbackEngine.prepare()
		captureEngine.prepare()
	}

	private func teardownGraph() {
		_ = try? Self.guardException {
			self.captureEngine.inputNode.removeTap(onBus: 0)
			if self.playerNode.isPlaying { self.playerNode.stop() }
			if self.captureEngine.isRunning { self.captureEngine.stop() }
			if self.playbackEngine.isRunning { self.playbackEngine.stop() }
		}
	}

	/// Wraps an AVAudioEngine call that could raise an Objective-C exception
	/// (mid-Bluetooth codec switch, device claimed by another process, etc.)
	/// and rethrows it as `AudioRoutingError.engineException`.
	private static func guardException(_ block: () throws -> Void) throws {
		var swiftError: Error?
		do {
			try ExceptionCatcher.perform {
				do {
					try block()
				} catch {
					swiftError = error
				}
			}
		} catch {
			throw AudioRoutingError.engineException(error.localizedDescription)
		}
		if let swiftError { throw swiftError }
	}

	private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
		guard let copy = AVAudioPCMBuffer(
			pcmFormat: buffer.format,
			frameCapacity: buffer.frameCapacity
		) else {
			return nil
		}
		copy.frameLength = buffer.frameLength
		let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
		let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
		for (src, dst) in zip(source, destination) {
			guard let srcData = src.mData, let dstData = dst.mData else { continue }
			memcpy(dstData, srcData, Int(src.mDataByteSize))
		}
		return copy
	}

	private static func setDevice(
		_ id: AudioDeviceID,
		for node: AVAudioIONode,
		scope: String
	) throws {
		guard let audioUnit = node.audioUnit else {
			throw AudioRoutingError.inputUnavailable
		}
		var deviceID = id
		let status = AudioUnitSetProperty(
			audioUnit,
			kAudioOutputUnitProperty_CurrentDevice,
			kAudioUnitScope_Global,
			0,
			&deviceID,
			UInt32(MemoryLayout<AudioDeviceID>.size)
		)
		guard status == noErr else {
			throw AudioRoutingError.setDeviceFailed(status, scope: scope)
		}
	}

	private func updateInactiveState() {
		isActive = false
		onPassThruChange?(false)
	}

	private func handleFailure(_ error: Error, context: String) {
		lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		NSLog("io: %@ failed — %@", context, String(describing: error))
		teardownGraph()
		updateInactiveState()
	}

	// MARK: - Restart debounce

	private func scheduleRestart() {
		restartWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			do {
				try self.restartRouting()
			} catch {
				self.handleFailure(error, context: "device switch")
			}
		}
		restartWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
	}

	// MARK: - Configuration-change handling

	private func observeConfigurationChanges() {
		let center = NotificationCenter.default
		let handler: (Notification) -> Void = { [weak self] _ in
			guard let self, self.isActive else { return }
			do {
				try self.restartRouting()
			} catch {
				self.handleFailure(error, context: "config change")
			}
		}

		for engine in [captureEngine, playbackEngine] {
			let token = center.addObserver(
				forName: .AVAudioEngineConfigurationChange,
				object: engine,
				queue: .main,
				using: handler
			)
			configChangeObservers.append(token)
		}
	}
}
