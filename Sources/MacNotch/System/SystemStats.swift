import Darwin
import Foundation
import IOKit.ps

/// Small system readings surfaced in the notch: battery, clock, appearance.
enum SystemStats {
    struct Battery {
        var level: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        var symbolName: String
    }

    static func battery() -> Battery? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let level = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let symbol: String
            if charging {
                symbol = "battery.100.bolt"
            } else {
                switch level {
                case ..<13: symbol = "battery.0"
                case ..<38: symbol = "battery.25"
                case ..<63: symbol = "battery.50"
                case ..<88: symbol = "battery.75"
                default: symbol = "battery.100"
                }
            }

            return Battery(level: level, isCharging: charging, isPluggedIn: plugged, symbolName: symbol)
        }
        return nil
    }

    static func toggleDarkMode() {
        run(
            "/usr/bin/osascript",
            ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"]
        )
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Locks the screen and brings up the login window.
///
/// macOS has no public API for this. `SACLockScreenImmediate` in the private
/// `login.framework` is what the system's own UI calls, and it is what every
/// third-party lock utility uses. Its binary lives in the dyld shared cache, so
/// we resolve the symbol at runtime instead of linking against it.
enum ScreenLock {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let function: LockFunction? = {
        let paths = [
            "/System/Library/PrivateFrameworks/login.framework/login",
            "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
                  let symbol = dlsym(handle, "SACLockScreenImmediate")
            else { continue }
            return unsafeBitCast(symbol, to: LockFunction.self)
        }
        return nil
    }()

    static var isAvailable: Bool { function != nil }

    static func lock() {
        if let function {
            _ = function()
            return
        }

        // Fall back to the ⌃⌘Q shortcut. Needs Accessibility permission.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
