import AppKit
import BTHubCore
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

    // Key links can arrive before didFinishLaunching, so the hub must exist by then.
    func applicationWillFinishLaunching(_ notification: Notification) {
        hub = Hub()
        hub.approveJoin = { [weak self] peer, code in self?.askToApprove(peer, code: code) ?? false }
        // `brew services` starts the binary directly, which never registers the bthub:// scheme on its own.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A windowless accessory app looks idle to the system; keep it from being terminated or napped away.
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar app")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        subscription = hub.$peers.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateIcon() }
        updateIcon()

        // On macOS 27 MenuBarAgent hands the app focus for ~0.1 s per click and takes it back, so a .transient
        // popover closes at once. Close it ourselves on clicks elsewhere instead.
        popover.behavior = .applicationDefined
        let panel = NSHostingController(rootView: PanelView(hub: hub) { [weak self] in self?.showSettings() })
        panel.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panel

        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let key = urls.lazy.compactMap(NetworkKey.key(from:)).first, key != hub.networkKey else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Use the network key from another Mac?")
        alert.informativeText = hub.networkKey == nil
            ? String(localized: "This Mac will see and control the audio devices of the Macs that use this key.")
            : String(localized: "It replaces the current key; Macs that still use the old one lose the connection to this Mac.")
        alert.addButton(withTitle: String(localized: "Use key"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { hub.useKey(key) }
    }

    /// Shows the joining Mac's name and code; the user allows it only if that Mac shows the same code.
    private func askToApprove(_ peer: PeerInfo, code: String) -> Bool {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "\(peer.name) wants to join your BT Hub network")
        alert.informativeText = String(localized: "Allow it only if \(peer.name) shows this code:")
        let label = NSTextField(labelWithString: code)
        label.font = .monospacedSystemFont(ofSize: 28, weight: .semibold)
        alert.accessoryView = label
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Deny"))
        return alert.runModal() == .alertFirstButtonReturn
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
