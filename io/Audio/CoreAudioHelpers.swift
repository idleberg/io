import CoreAudio
import Foundation

enum CoreAudioError: Error {
	case propertyReadFailed(OSStatus)
	case propertySizeFailed(OSStatus)
}

enum CoreAudioHelpers {
	static func getProperty<T>(
		_ object: AudioObjectID,
		_ address: AudioObjectPropertyAddress,
		default defaultValue: T
	) throws -> T {
		var addr = address
		var value = defaultValue
		var size = UInt32(MemoryLayout<T>.size)
		let status = withUnsafeMutablePointer(to: &value) { pointer -> OSStatus in
			AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer)
		}
		guard status == noErr else { throw CoreAudioError.propertyReadFailed(status) }
		return value
	}

	static func getPropertyArray<T>(
		_ object: AudioObjectID,
		_ address: AudioObjectPropertyAddress
	) throws -> [T] {
		var addr = address
		var size: UInt32 = 0
		guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else {
			throw CoreAudioError.propertySizeFailed(noErr)
		}
		let count = Int(size) / MemoryLayout<T>.size
		guard count > 0 else { return [] }

		let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
		defer { buffer.deallocate() }

		let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer)
		guard status == noErr else { throw CoreAudioError.propertyReadFailed(status) }

		return Array(UnsafeBufferPointer(start: buffer, count: count))
	}

	static func getString(
		_ object: AudioObjectID,
		_ address: AudioObjectPropertyAddress
	) throws -> String {
		var addr = address
		var size = UInt32(MemoryLayout<CFString?>.size)
		var cfString: CFString? = nil
		let status = withUnsafeMutablePointer(to: &cfString) { ptr in
			AudioObjectGetPropertyData(object, &addr, 0, nil, &size, ptr)
		}
		guard status == noErr, let value = cfString else {
			throw CoreAudioError.propertyReadFailed(status)
		}
		return value as String
	}

	/// Returns whether the device has at least one stream with channels on the
	/// given scope.
	///
	/// Calling this with `kAudioDevicePropertyScopeInput` on recent macOS
	/// triggers a microphone-permission prompt per device. Callers MUST gate
	/// the input-scope call behind an authorized permission status; the
	/// output-scope call is always safe.
	static func hasStreams(
		on object: AudioObjectID,
		scope: AudioObjectPropertyScope
	) -> Bool {
		var address = AudioObjectPropertyAddress(
			mSelector: kAudioDevicePropertyStreamConfiguration,
			mScope: scope,
			mElement: kAudioObjectPropertyElementMain
		)

		var size: UInt32 = 0
		guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
			size > 0
		else {
			return false
		}

		let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
		defer { bufferList.deallocate() }

		guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, bufferList) == noErr else {
			return false
		}

		let abl = UnsafeMutableAudioBufferListPointer(bufferList)
		for buffer in abl where buffer.mNumberChannels > 0 {
			return true
		}
		return false
	}
}
