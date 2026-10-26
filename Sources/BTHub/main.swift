import AppKit

// Plain AppKit entry point: SwiftUI's MenuBarExtra flashed a window on click and lost the menu.
MainActor.assumeIsolated {
    // Login item and `brew services` may both start it; a second copy would advertise the same Mac twice.
    if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
