import AppKit
import Combine
import CoreAudio
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
	static let appName = "io"

	private let permissions = PermissionsManager()
	private lazy var deviceManager = AudioDeviceManager(permissions: permissions)
	private let routingEngine = AudioRoutingEngine()
	private let settings = AppSettings.shared
	private let displayName = DisplayName()

	private var statusItem: NSStatusItem!
	private var popover: NSPopover!
	private var eventMonitor: Any?
	private var cancellables = Set<AnyCancellable>()

	func applicationDidFinishLaunching(_ notification: Notification) {
		bindRoutingToDeviceManager()
		configureRoutingDefaults()
		setupStatusItem()
		setupPopover()
		observeSleepWake()
	}

	func applicationWillTerminate(_ notification: Notification) {
		routingEngine.stopRouting()
	}

	// MARK: - Setup

	private func bindRoutingToDeviceManager() {
		deviceManager.$inputDevices
			.combineLatest(deviceManager.$outputDevices)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _, _ in
				self?.reconcileSelection()
			}
			.store(in: &cancellables)

		routingEngine.onPassThruChange = { [weak self] active in
			self?.updateStatusIcon(active: active)
		}
	}

	private func configureRoutingDefaults() {
		let storedInput = AudioDeviceID(settings.selectedInputDeviceID)
		let storedOutput = AudioDeviceID(settings.selectedOutputDeviceID)

		routingEngine.selectedInputID =
			deviceManager.isInputValid(storedInput)
			? storedInput
			: deviceManager.defaultInputID

		routingEngine.selectedOutputID =
			deviceManager.isOutputValid(storedOutput)
			? storedOutput
			: deviceManager.defaultOutputID

		routingEngine.gainDB = settings.gainDB
	}

	private func reconcileSelection() {
		let inputVanished = !deviceManager.isInputValid(routingEngine.selectedInputID)
		let outputVanished = !deviceManager.isOutputValid(routingEngine.selectedOutputID)

		if inputVanished {
			routingEngine.selectedInputID = deviceManager.defaultInputID
		}
		if outputVanished {
			routingEngine.selectedOutputID = deviceManager.defaultOutputID
		}

		// If the currently routed device vanished and no default is available,
		// stop cleanly rather than letting the engine fail opaquely.
		if (inputVanished && routingEngine.selectedInputID == 0)
			|| (outputVanished && routingEngine.selectedOutputID == 0) {
			routingEngine.stopRouting()
		}
	}

	// MARK: - Status Item

	private func setupStatusItem() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		updateStatusIcon(active: routingEngine.isActive)

		if let button = statusItem.button {
			button.target = self
			button.action = #selector(statusItemClicked(_:))
			button.sendAction(on: [.leftMouseUp, .rightMouseUp])
		}
	}

	private func updateStatusIcon(active: Bool) {
		guard let button = statusItem?.button else { return }
		let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: Self.appName)
		image?.isTemplate = true
		button.image = image
		button.alphaValue = active ? 1.0 : 0.6
	}

	@objc private func statusItemClicked(_ sender: NSStatusBarButton) {
		guard let event = NSApp.currentEvent else { return }
		if event.type == .rightMouseUp {
			showContextMenu()
		} else {
			togglePopover()
		}
	}

	private func showContextMenu() {
		let menu = NSMenu()

		let openItem = NSMenuItem(
			title: "Switch to Listen Mode",
			action: #selector(openFromMenu),
			keyEquivalent: ""
		)
		openItem.target = self
		menu.addItem(openItem)

		menu.addItem(NSMenuItem.separator())

		let launchItem = NSMenuItem(
			title: "Launch at Login",
			action: #selector(toggleLaunchAtLogin),
			keyEquivalent: ""
		)
		launchItem.target = self
		launchItem.state = settings.launchAtLogin ? .on : .off
		menu.addItem(launchItem)

		let resetItem = NSMenuItem(
			title: "Reset Settings…",
			action: #selector(resetSettings),
			keyEquivalent: ""
		)
		resetItem.target = self
		menu.addItem(resetItem)

		menu.addItem(NSMenuItem.separator())

		let aboutItem = NSMenuItem(
			title: "About \(Self.appName)",
			action: #selector(showAbout),
			keyEquivalent: ""
		)
		aboutItem.target = self
		menu.addItem(aboutItem)

		menu.addItem(NSMenuItem.separator())

		let quitItem = NSMenuItem(
			title: "Quit \(Self.appName)",
			action: #selector(quit),
			keyEquivalent: "q"
		)
		quitItem.target = self
		menu.addItem(quitItem)

		statusItem.menu = menu
		statusItem.button?.performClick(nil)
		statusItem.menu = nil
	}

	// MARK: - Popover

	private func setupPopover() {
		popover = NSPopover()
		popover.behavior = .transient
		popover.animates = true
		popover.contentViewController = NSHostingController(rootView: rootView())
	}

	@ViewBuilder
	private func rootView() -> some View {
		ContentView(
			deviceManager: deviceManager,
			routingEngine: routingEngine,
			permissions: permissions,
			displayName: displayName
		)
	}

	private func togglePopover() {
		if popover.isShown {
			popover.performClose(nil)
			removeEventMonitor()
		} else {
			showPopover()
		}
	}

	private func showPopover() {
		guard let button = statusItem.button else { return }
		displayName.roll()
		popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
		popover.contentViewController?.view.window?.makeKey()
		installEventMonitor()
	}

	private func installEventMonitor() {
		removeEventMonitor()
		eventMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown]
		) { [weak self] _ in
			self?.popover.performClose(nil)
			self?.removeEventMonitor()
		}
	}

	private func removeEventMonitor() {
		if let monitor = eventMonitor {
			NSEvent.removeMonitor(monitor)
			eventMonitor = nil
		}
	}

	// MARK: - Menu actions

	@objc private func openFromMenu() {
		showPopover()
	}

	@objc private func toggleLaunchAtLogin() {
		settings.launchAtLogin.toggle()
		LaunchAtLogin.setEnabled(settings.launchAtLogin)
	}

	@objc private func resetSettings() {
		let alert = NSAlert()
		alert.messageText = "Reset all \(Self.appName) settings to their defaults?"
		alert.informativeText =
			"The selected input and output devices, gain, and Launch-at-Login preference will be cleared."
		alert.alertStyle = .warning
		alert.addButton(withTitle: "Reset")
		alert.addButton(withTitle: "Cancel")

		NSApp.activate(ignoringOtherApps: true)
		guard alert.runModal() == .alertFirstButtonReturn else { return }

		routingEngine.stopRouting()
		settings.reset()
		LaunchAtLogin.setEnabled(false)
		configureRoutingDefaults()
	}

	@objc private func showAbout() {
		NSApp.orderFrontStandardAboutPanel(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}

	// MARK: - Sleep / Wake

	private func observeSleepWake() {
		let notificationCenter = NSWorkspace.shared.notificationCenter
		notificationCenter.addObserver(
			self,
			selector: #selector(systemWillSleep),
			name: NSWorkspace.willSleepNotification,
			object: nil
		)
		notificationCenter.addObserver(
			self,
			selector: #selector(systemDidWake),
			name: NSWorkspace.didWakeNotification,
			object: nil
		)
	}

	@objc private func systemWillSleep() {
		routingEngine.suspendForSleep()
	}

	@objc private func systemDidWake() {
		routingEngine.resumeAfterWake()
	}
}
