import AVFoundation
import Foundation

final class LevelMeter: ObservableObject {
	static let minDB: Float = -60.0
	static let maxDB: Float = 0.0

	@Published var displayLevels: [Float] = [LevelMeter.minDB, LevelMeter.minDB]
	@Published var peakLevels: [Float] = [LevelMeter.minDB, LevelMeter.minDB]

	private let decayPerFrame: Float = 1.5
	private let peakHoldFrames: Int = 120

	private var rawLevels: [Float] = [LevelMeter.minDB, LevelMeter.minDB]
	private var peakHoldCounters: [Int] = [0, 0]
	private var timer: Timer?
	private let lock = NSLock()

	func start() {
		stop()
		let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
			self?.tick()
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}

	func reset() {
		lock.lock()
		rawLevels = Array(repeating: Self.minDB, count: rawLevels.count)
		peakHoldCounters = Array(repeating: 0, count: peakHoldCounters.count)
		lock.unlock()

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.displayLevels = Array(repeating: Self.minDB, count: self.displayLevels.count)
			self.peakLevels = Array(repeating: Self.minDB, count: self.peakLevels.count)
		}
	}

	func process(_ buffer: AVAudioPCMBuffer) {
		let channelCount = Int(buffer.format.channelCount)
		let frameCount = Int(buffer.frameLength)
		guard channelCount > 0, frameCount > 0 else { return }
		guard let newLevels = Self.levels(from: buffer, channels: channelCount, frames: frameCount) else { return }

		lock.lock()
		rawLevels = newLevels
		if peakHoldCounters.count != channelCount {
			peakHoldCounters = Array(repeating: 0, count: channelCount)
		}
		lock.unlock()

		if displayLevels.count != channelCount || peakLevels.count != channelCount {
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				self.displayLevels = Array(repeating: Self.minDB, count: channelCount)
				self.peakLevels = Array(repeating: Self.minDB, count: channelCount)
			}
		}
	}

	private static func levels(from buffer: AVAudioPCMBuffer, channels: Int, frames: Int) -> [Float]? {
		if let floatData = buffer.floatChannelData {
			return (0..<channels).map { channel in
				let samples = UnsafeBufferPointer(start: floatData[channel], count: frames)
				var sum: Float = 0
				for sample in samples { sum += sample * sample }
				return dbFromSumOfSquares(sum, frames: frames)
			}
		}
		if let int16Data = buffer.int16ChannelData {
			return integerLevels(data: int16Data, channels: channels, frames: frames, scale: Float(Int16.max))
		}
		if let int32Data = buffer.int32ChannelData {
			return integerLevels(data: int32Data, channels: channels, frames: frames, scale: Float(Int32.max))
		}
		return nil
	}

	private static func integerLevels<T: BinaryInteger>(
		data: UnsafePointer<UnsafeMutablePointer<T>>,
		channels: Int,
		frames: Int,
		scale: Float
	) -> [Float] {
		(0..<channels).map { channel in
			let samples = UnsafeBufferPointer(start: data[channel], count: frames)
			var sum: Float = 0
			for sample in samples {
				let normalized = Float(sample) / scale
				sum += normalized * normalized
			}
			return dbFromSumOfSquares(sum, frames: frames)
		}
	}

	private static func dbFromSumOfSquares(_ sum: Float, frames: Int) -> Float {
		let rms = sqrt(sum / Float(frames))
		return 20 * log10(max(rms, 1e-7))
	}

	private func tick() {
		lock.lock()
		let raw = rawLevels
		var peakCounters = peakHoldCounters
		lock.unlock()

		let channelCount = min(raw.count, displayLevels.count)
		guard channelCount > 0 else { return }

		var newDisplay = displayLevels
		var newPeaks = peakLevels

		for i in 0..<channelCount {
			let rawLevel = max(raw[i], Self.minDB)

			if rawLevel >= newDisplay[i] {
				newDisplay[i] = rawLevel
			} else {
				newDisplay[i] = max(newDisplay[i] - decayPerFrame, Self.minDB)
			}

			if rawLevel > newPeaks[i] {
				newPeaks[i] = rawLevel
				peakCounters[i] = peakHoldFrames
			} else if peakCounters[i] > 0 {
				peakCounters[i] -= 1
			} else {
				newPeaks[i] = max(newPeaks[i] - decayPerFrame, newDisplay[i])
			}
		}

		lock.lock()
		peakHoldCounters = peakCounters
		lock.unlock()

		displayLevels = newDisplay
		peakLevels = newPeaks
	}
}
