import AppKit
import ApplicationServices

/// Privacy permissions MacNotch relies on. Accessibility lets us see and drive
/// other apps' call windows; Full Disk Access is only needed for the system
/// notification store.
enum Permissions {
    /// Whether this app may use the Accessibility API on other processes.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Asks the system to prompt for Accessibility and adds MacNotch to the list
    /// in System Settings. The prompt is shown once per app.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
