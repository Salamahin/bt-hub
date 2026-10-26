import AppKit
import Combine
import SwiftUI

/// Owns the status-bar icon, the panel it opens, and the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hub: Hub!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A windowless accessory app looks idle to the system; keep it from being terminated or napped away.
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar app")
        hub = Hub()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        subscription = hub.$peers.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateIcon() }
        updateIcon()

        // On macOS 27 MenuBarAgent hands the app focus for ~0.1 s per click and takes it back, so a .transient
        // popover closes at once. Close it ourselves on clicks elsewhere instead.
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: PanelView(hub: hub) { [weak self] in self?.showSettings() })

        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    private func updateIcon() {
        let symbol = hub.anyConnectedHere ? "headphones.circle.fill" : "headphones"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BT Hub")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePanel()
            return
        }
        Task { await hub.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Global monitors see only clicks in other apps, which is exactly "outside the panel".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func closePanel() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func showSettings() {
        closePanel()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(hub: hub))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "BT Hub Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
