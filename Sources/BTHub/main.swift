import AppKit

// Plain AppKit entry point: SwiftUI's MenuBarExtra flashed a window on click and lost the menu.
MainActor.assumeIsolated {
    // Login item and `brew services` may both start it; a second copy would advertise the same Mac twice.
    // Launched by launchd, this process is not in the list yet, so look for any other copy rather than a second one.
    let me = ProcessInfo.processInfo.processIdentifier
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
