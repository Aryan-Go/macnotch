import AppKit

@main
struct MacNotchApp {
    @MainActor
    static func main() {
        // Only one notch panel may exist at a time.
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty { exit(0) }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
