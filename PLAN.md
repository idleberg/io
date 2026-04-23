# Line In Clone — macOS App Plan

A macOS menu bar utility that routes audio from a selected input device to a selected output device, inspired by the discontinued [Line In](https://rogueamoeba.com/freebies/) app by Rogue Amoeba.

---

## Overview

- **Platform:** macOS 13+ (Ventura)
- **Language:** Swift 5.9+
- **UI framework:** SwiftUI
- **Audio frameworks:** CoreAudio, AVFoundation
- **Distribution:** Direct download (no App Store, avoids sandbox constraints)
- **App type:** Menu bar utility (`LSUIElement = YES`)

---

## Features

- Select any audio input device (microphone, USB interface, etc.)
- Select any audio output device (speakers, headphones, etc.)
- Pass Thru toggle to start/stop routing
- Input gain control (−40 dB to +20 dB) with `AVAudioUnitEQ`
- Stereo level meters with ballistics, flanking the Pass Thru button
- Float mode: keeps the UI in a persistent, always-on-top panel
- Launch at Login setting
- Dynamic device list (responds to USB plug/unplug)
- Defaults to the system default input and output devices on first launch

---

## Project Structure

```
LineIn/
├── App/
│   ├── LineInApp.swift              # @main entry point, scene setup
│   └── AppDelegate.swift            # NSStatusItem, popover/panel management
├── Audio/
│   ├── AudioDevice.swift            # Value type: id, name, isInput, isOutput
│   ├── AudioDeviceManager.swift     # CoreAudio enumeration + change observation
│   ├── AudioRoutingEngine.swift     # AVAudioEngine wrapper, device switching, gain
│   └── LevelMeter.swift            # Tap reading, RMS→dBFS, ballistics
├── Permissions/
│   └── PermissionsManager.swift     # Microphone access request + status
└── UI/
    ├── ContentView.swift            # Root SwiftUI view
    ├── DevicePickerRow.swift        # Labelled device dropdown component
    ├── GainSlider.swift             # dB-scale input gain control
    ├── LevelMeterView.swift         # Animated stereo meter bars
    └── StatusBarIcon.swift          # Menu bar icon + state
```

---

## Setup

### Info.plist keys

```xml
<!-- Hide from Dock and app switcher -->
<key>LSUIElement</key>
<true/>
```

### Entitlements

```xml
<!-- Required for microphone/input device access -->
<key>com.apple.security.device.audio-input</key>
<true/>
```

No sandbox required if distributing outside the App Store, which simplifies the CoreAudio device property API usage.

---

## Module Breakdown

### `AudioDevice.swift`

A lightweight value type representing a single audio device.

```swift
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}
```

### `AudioDeviceManager.swift`

Responsible for:

1. **Enumerating devices** via `AudioObjectGetPropertyData` with `kAudioHardwarePropertyDevices`
2. **Filtering inputs/outputs** by querying `kAudioDevicePropertyStreamConfiguration` on the input and output scopes
3. **Fetching device names** via `kAudioObjectPropertyName`
4. **Reading default devices** via `kAudioHardwarePropertyDefaultInputDevice` / `kAudioHardwarePropertyDefaultOutputDevice`
5. **Observing changes** via `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDevices` — fires when USB devices are connected or disconnected

Conforms to `ObservableObject`, publishing:

```swift
@Published var inputDevices: [AudioDevice]
@Published var outputDevices: [AudioDevice]
@Published var defaultInputID: AudioDeviceID
@Published var defaultOutputID: AudioDeviceID
```

On device list change, cross-reference current selections against the new list and fall back to the system default if the selected device has disappeared.

### `AudioRoutingEngine.swift`

Wraps `AVAudioEngine` and manages the audio routing graph.

**Key insight:** `AVAudioEngine` does not expose a `setInputDevice()` method. Device assignment requires reaching into the underlying Audio Unit of the engine's input/output nodes directly:

```swift
func setInputDevice(_ id: AudioDeviceID) throws {
    var deviceID = id
    let err = AudioUnitSetProperty(
        engine.inputNode.audioUnit!,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard err == noErr else { throw AudioRoutingError.setDeviceFailed(err) }
}
```

Same pattern for the output node.

**The tap trick:** `AVAudioEngine` won't pull audio from the input node unless something is consuming it. The tap on the gain node (see below) serves this purpose. Remove it before stopping the engine (`gainNode.removeTap(onBus: 0)`).

**Routing graph with gain node:**

```
InputNode → GainNode (AVAudioUnitEQ) → MainMixerNode → OutputNode
```

The `AVAudioUnitEQ` sits between input and mixer and provides decibel-scale gain including boost above 0 dB. The mixer still handles sample rate conversion.

```swift
let gainNode = AVAudioUnitEQ()
gainNode.globalGain = 0.0  // dB, range: −96 to +24
engine.attach(gainNode)
engine.connect(inputNode, to: gainNode, format: inputFormat)
engine.connect(gainNode, to: mainMixerNode, format: inputFormat)
```

`globalGain` applies to all channels uniformly and can be set at any time without restarting the engine.

**The tap:** Attach to `inputNode` as before. With the gain node in the graph, the tap still fires on the raw pre-gain signal. If you want metering to reflect the post-gain level, move the tap to the output of `gainNode` instead:

```swift
gainNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { buffer, _ in
    self.levelMeter.process(buffer)
}
```

Post-gain metering is more useful — it shows what actually reaches the output.

**Public interface:**

```swift
@Observable class AudioRoutingEngine {
    var selectedInputID: AudioDeviceID
    var selectedOutputID: AudioDeviceID
    var isActive: Bool
    var gainDB: Float        // −40.0 to +20.0, applied to AVAudioUnitEQ.globalGain
    var channelLevels: [Float]  // dBFS per channel, updated ~60fps, populated by LevelMeter

    func startRouting() throws
    func stopRouting()
    func restartRouting() throws  // call on device change
}
```

When `selectedInputID` or `selectedOutputID` change, call `restartRouting()`. Debounce by ~100ms to avoid thrashing if the user drags through the picker quickly.

### `LevelMeter.swift`

Responsible for reading audio buffers from the tap, computing RMS level per channel in dBFS, and applying ballistics so the UI animates smoothly.

**RMS → dBFS calculation:**

```swift
func process(_ buffer: AVAudioPCMBuffer) {
    guard let data = buffer.floatChannelData else { return }
    let channelCount = Int(buffer.format.channelCount)
    let frameCount = Int(buffer.frameLength)

    let raw = (0..<channelCount).map { ch -> Float in
        let samples = UnsafeBufferPointer(start: data[ch], count: frameCount)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(frameCount))
        return 20 * log10(max(rms, 1e-7))  // clamp to avoid log(0)
    }

    DispatchQueue.main.async { self.rawLevels = raw }
}
```

**Ballistics:** Drive a display update loop from a `CADisplayLink` or 60fps `Timer`, separate from the tap callback. This decouples metering from the audio thread:

```swift
// Called at ~60fps on the main thread
func tick() {
    for i in 0..<displayLevels.count {
        let raw = rawLevels[i]
        if raw >= displayLevels[i] {
            displayLevels[i] = raw                    // instant attack
            if raw > peakLevels[i] {
                peakLevels[i] = raw
                peakHoldCounters[i] = peakHoldFrames  // ~120 frames = 2 seconds
            }
        } else {
            displayLevels[i] -= decayPerFrame         // ~1.5 dB/frame at 60fps
        }

        if peakHoldCounters[i] > 0 {
            peakHoldCounters[i] -= 1
        } else {
            peakLevels[i] = max(peakLevels[i] - decayPerFrame, displayLevels[i])
        }
    }
}
```

**Published state:**

```swift
@Observable class LevelMeter {
    var displayLevels: [Float]   // smoothed dBFS per channel, for meter bar height
    var peakLevels: [Float]      // peak hold dBFS per channel, for peak marker
    
    private var rawLevels: [Float] = []
    private var peakHoldCounters: [Int] = []

    private let minDB: Float = -60.0
    private let maxDB: Float =   0.0
    private let decayPerFrame: Float = 1.5        // dB lost per frame at 60fps
    private let peakHoldFrames: Int = 120         // 2 seconds at 60fps
}
```

Reset all levels to `minDB` when Pass Thru is toggled off.

### `PermissionsManager.swift`

```swift
@Observable class PermissionsManager {
    var status: AVAuthorizationStatus

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        )
    }
}
```

Check status on launch. Gate the main UI behind an authorization check — show a prompt with an "Open System Settings" button if denied.

---

## UI

### Menu bar behaviour

- **Left-click** the status bar icon: toggle the popover (or floating panel in float mode)
- **Right-click** the status bar icon: context menu

### Status bar icon

Use `NSImage(systemSymbolName: "waveform", ...)` as a template image. Toggle between:
- `waveform` at reduced opacity when Pass Thru is off
- `waveform` at full opacity (or filled variant) when Pass Thru is on

### Popover (default mode)

Standard `NSPopover` anchored to the status bar item. Width: ~288pt. Auto-dismisses on click outside.

```
┌─────────────────────────────────┐
│ Line In                  ● LIVE │
├─────────────────────────────────┤
│ INPUT                           │
│ ┌─────────────────────────────┐ │
│ │ Focusrite Scarlett 2i2    ▾ │ │
│ └─────────────────────────────┘ │
│                                 │
│ OUTPUT                          │
│ ┌─────────────────────────────┐ │
│ │ Sony WH-1000XM5           ▾ │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ 🔈 ──────────●──────────── +6dB │
├─────────────────────────────────┤
│ ██████░░░  [Pass Thru]  ░░█████ │
├─────────────────────────────────┤
│ 📌  Launch at Login      Quit   │
└─────────────────────────────────┘
```

- Each device picker opens a dropdown with a checkmark on the current selection
- Gain slider: horizontal, between device pickers and the meter row
- Meter + Pass Thru row: left meter grows right-to-left, right meter grows left-to-right, button centred between them (mirroring the original Line In layout)
- Pass Thru button: green with a glowing LED dot and "LIVE" badge when active
- Footer: pin icon button for float mode (highlighted when on), Launch at Login toggle (text link), Quit

### `GainSlider.swift`

A horizontal `Slider` mapped to a dB scale, exposed in the UI between the device pickers and the meter row.

```swift
Slider(value: $routingEngine.gainDB, in: -40...20, step: 0.5)
```

Display the current value as a formatted label (e.g. `0 dB`, `+6 dB`, `−12 dB`). A value of 0 dB means unity gain — no amplification or attenuation. Mark the 0 dB point visually (a notch or tick) so the user can snap back to unity easily; consider adding `snapValues: [0]` behaviour via a custom gesture or a reset-on-double-click.

Speaker icons at either end of the slider (quiet on the left, loud on the right) communicate the control's purpose without a text label.

### `LevelMeterView.swift`

Renders the stereo level meters flanking the Pass Thru button, matching the horizontal layout of the original Line In app.

**Layout:** A single `HStack` containing, in order: the left channel meter, the Pass Thru button, the right channel meter.

```swift
HStack(spacing: 4) {
    LevelBar(level: meter.displayLevels[0],
             peak: meter.peakLevels[0],
             direction: .rightToLeft)   // L channel grows inward from left edge
    PassThruButton(...)
    LevelBar(level: meter.displayLevels[1],
             peak: meter.peakLevels[1],
             direction: .leftToRight)   // R channel grows inward from right edge
}
```

**`LevelBar`:** A horizontal bar composed of discrete rounded segments (capsule shapes), matching the segmented look of the original app. Segments light up from the inside out.

```swift
// Map dBFS to a 0–1 normalized fill ratio
let normalized = (level - minDB) / (maxDB - minDB)  // minDB = -60, maxDB = 0
let litSegments = Int(normalized * Float(totalSegments))
```

**Colour zones** (applied per segment by index):

| Range | Colour |
|---|---|
| Below −12 dBFS | Green |
| −12 dBFS to −3 dBFS | Amber |
| Above −3 dBFS | Red |

**Peak hold marker:** A single brighter segment rendered at the `peakLevel` position, independent of the fill. It holds for ~2 seconds then decays.

**Idle state:** When Pass Thru is off, render all segments at minimum opacity (dimmed, not hidden) — this matches the original app's appearance and clearly communicates that the meter exists but is inactive.

### Float mode panel

When float mode is enabled, the popover is replaced with a persistent `NSPanel`.

```swift
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 288, height: 220),
    styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isMovableByWindowBackground = true
panel.titlebarAppearsTransparent = true
panel.titleVisibility = .hidden
panel.backgroundColor = .clear
panel.isOpaque = false
panel.hasShadow = true
```

Key flags:
- `.nonactivatingPanel` — clicking the panel does not steal focus from the active app
- `.canJoinAllSpaces` — visible on all Mission Control spaces
- `.floating` level — above all normal windows
- `isMovableByWindowBackground = true` — drag anywhere to reposition

**Position persistence:** call `panel.setFrameAutosaveName("FloatingPanel")` and macOS handles save/restore automatically.

**Switching modes:**

```swift
func setFloatMode(_ enabled: Bool) {
    if enabled {
        popover.close()
        panel.orderFrontRegardless()
    } else {
        panel.orderOut(nil)
        // next status bar click will open the popover again
    }
    UserDefaults.standard.set(enabled, forKey: "floatMode")
}
```

**Panel close button behaviour:** Hook `windowWillClose` on the panel delegate. When the user clicks ✕, turn float mode off — don't leave the app in a state where it's neither showing a popover nor a panel.

**Status bar click in float mode:** Toggle `panel.isVisible` rather than opening a popover.

### Context menu (right-click on status bar icon)

```
Open Line In
────────────
Launch at Login  ✓
────────────
About Line In
────────────
Quit Line In
```

"Open Line In" re-opens the popover (or brings the floating panel to front) if it was dismissed.

---

## State & Data Flow

```
AudioDeviceManager          AudioRoutingEngine
  └─ inputDevices    ──────►  selectedInputID
  └─ outputDevices   ──────►  selectedOutputID
  └─ device changes  ──────►  restartRouting()

AudioRoutingEngine          LevelMeter
  └─ gainNode tap    ──────►  process(buffer)   [audio thread]
                             tick()             [main thread, 60fps]
                               └─ displayLevels, peakLevels

AppDelegate
  └─ manages NSStatusItem
  └─ manages NSPopover / NSPanel
  └─ responds to float mode toggle

PermissionsManager
  └─ gates ContentView until authorized
```

All audio state lives in `AudioRoutingEngine`. `LevelMeter` is owned by the engine and updated from the tap callback. UI observes `engine.channelLevels` and `engine.peakLevels` directly. `AudioDeviceManager` is injected as an environment object. Settings (`floatMode`, `launchAtLogin`) are persisted in `UserDefaults`.

---

## Edge Cases

| Scenario | Handling |
|---|---|
| Selected device is unplugged | Device change listener fires → fall back to system default → stop and restart engine |
| Input and output are the same device | Permitted for multi-channel interfaces; warn the user about feedback risk |
| `AVAudioEngine.start()` throws | Catch, surface error in UI, leave Pass Thru toggled off |
| Sample rate mismatch | Handled transparently by `AVAudioMixerNode` |
| App is backgrounded | Audio routing continues — correct behaviour |
| macOS sleeps / wakes | Observe `NSWorkspace.willSleepNotification` to stop engine cleanly; observe `NSWorkspace.didWakeNotification` to restart |
| Float panel closed via ✕ | `windowWillClose` delegate → disable float mode, restore popover behaviour |
| Float panel on fullscreen spaces | `.fullScreenAuxiliary` enables this; consider documenting it |
| Launch with mic permission denied | Show permission prompt view, gate all audio code behind authorization |
| Mono input device selected | `buffer.format.channelCount` will be 1; mirror the single channel to both meter bars rather than leaving the right bar dark |
| Pass Thru toggled off | Stop the engine, reset `LevelMeter` display and peak levels to `minDB`, render meter segments at idle opacity |
| Gain slider at maximum (+20 dB) with hot input | Clipping is possible; the red meter zone serves as the warning — no additional handling needed |

---

## Settings Persistence (`UserDefaults`)

| Key | Type | Default |
|---|---|---|
| `selectedInputDeviceID` | `Int` | system default |
| `selectedOutputDeviceID` | `Int` | system default |
| `passThruActive` | `Bool` | `false` |
| `gainDB` | `Float` | `0.0` |
| `floatMode` | `Bool` | `false` |
| `launchAtLogin` | `Bool` | `false` |

For Launch at Login, use `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+ API, replaces the deprecated `SMLoginItemSetEnabled`).

---

## Estimated Effort

| Phase | Effort |
|---|---|
| Project + entitlements setup | 30 min |
| CoreAudio device enumeration | 2–3 hrs |
| `AVAudioEngine` routing + device switching | 3–4 hrs |
| Gain node (`AVAudioUnitEQ`) + slider UI | 1–2 hrs |
| Level metering: tap → RMS → dBFS | 1 hr |
| Level metering: ballistics + peak hold | 2–3 hrs |
| `LevelMeterView`: segmented bars + colour zones | 1–2 hrs |
| Permissions flow | 1 hr |
| SwiftUI popover UI | 2 hrs |
| Float mode panel + mode switching | 2–3 hrs |
| Edge case handling + polish | 2–3 hrs |
| **Total** | **~18–24 hrs** |

The CoreAudio property address API is the steepest part — it's a C-style API with `UnsafeMutableRawPointer` casting that feels unnatural in Swift. Wrapping it in a small generic helper early will save pain later:

```swift
func getProperty<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> T {
    var addr = address
    var value: T = unsafeBitCast(0, to: T.self)
    var size = UInt32(MemoryLayout<T>.size)
    let err = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
    guard err == noErr else { throw AudioError.propertyReadFailed(err) }
    return value
}
```

---

## References

- [AVAudioEngine — Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [AVAudioUnitEQ — Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiouniteq)
- [AudioObjectGetPropertyData — CoreAudio](https://developer.apple.com/documentation/coreaudio/1422524-audioobjectgetpropertydata)
- [kAudioOutputUnitProperty_CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)
- [SMAppService — ServiceManagement](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [NSPanel — AppKit](https://developer.apple.com/documentation/appkit/nspanel)
- [CADisplayLink — QuartzCore](https://developer.apple.com/documentation/quartzcore/cadisplaylink)
