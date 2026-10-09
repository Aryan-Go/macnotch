import AppKit
import Foundation

enum NotificationsError: Error {
    case permissionNeeded
    case unavailable
}

/// Reads recent notifications from the system Notification Center database.
///
/// The database lives under `group.com.apple.usernoted`, which macOS protects
/// with Full Disk Access. Without it the read fails and we surface a hint. Each
/// row's payload is a binary plist carrying the title/subtitle/body.
enum NotificationsProvider {
    private static let dbRelativePath =
        "Library/Group Containers/group.com.apple.usernoted/db2/db"

    static func fetch() -> Result<[NotificationItem], NotificationsError> {
        let source = NSHomeDirectory() + "/" + dbRelativePath
        let manager = FileManager.default

        guard manager.fileExists(atPath: source) else { return .failure(.unavailable) }
        guard manager.isReadableFile(atPath: source) else { return .failure(.permissionNeeded) }

        // Query a private copy so we never fight the live database's WAL locks.
        guard let working = copyDatabase(source: source) else {
            return .failure(.permissionNeeded)
        }
        defer { try? manager.removeItem(at: working.directory) }

        guard let schema = columnNames(in: working.path) else { return .failure(.unavailable) }
        guard schema.contains("data"), schema.contains("delivered_date") else {
            return .failure(.unavailable)
        }

        let select = [
            schema.contains("rec_id") ? "rec_id" : "NULL",
            "hex(data)",
            schema.contains("app_id") ? "app_id" : "''",
            "delivered_date"
        ].joined(separator: ", ")

        let query = """
        SELECT \(select) FROM record \
        WHERE data IS NOT NULL AND delivered_date IS NOT NULL \
        ORDER BY delivered_date DESC LIMIT 30;
        """

        guard let output = runSQLite(path: working.path, query: query, separator: "|") else {
            return .failure(.unavailable)
        }

        var items: [NotificationItem] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let hex = String(fields[1])
            guard !hex.isEmpty, let data = data(fromHex: hex), !data.isEmpty else { continue }

            let bundleID = String(fields[2])
            let delivered = Double(fields[3]) ?? 0
            let key = String(fields[0])

            guard let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }

            let title = firstString(payload, ["tit", "title"]) ?? ""
            let subtitle = firstString(payload, ["sub", "subtitle"]) ?? ""
            let body = firstString(payload, ["body", "message"]) ?? ""
            if title.isEmpty && body.isEmpty { continue }

            let app = appInfo(for: bundleID)
            items.append(NotificationItem(
                id: key + hex.prefix(16),
                title: title,
                subtitle: subtitle,
                body: body,
                appName: app.name,
                bundleID: bundleID,
                date: Date(timeIntervalSinceReferenceDate: delivered),
                icon: app.icon
            ))
        }

        return .success(items)
    }

    // MARK: - Database helpers

    private static func copyDatabase(source: String) -> (directory: URL, path: String)? {
        let manager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macnotch-usernoted-\(ProcessInfo.processInfo.processIdentifier)")
        try? manager.removeItem(at: directory)
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }

        let base = URL(fileURLWithPath: source)
        var copied = false
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            let to = directory.appendingPathComponent(base.lastPathComponent + suffix)
            guard (try? manager.copyItem(at: from, to: to)) != nil else {
                if suffix.isEmpty { return nil }
                continue
            }
            if suffix.isEmpty { copied = true }
        }
        guard copied else { return nil }
        return (directory, directory.appendingPathComponent(base.lastPathComponent).path)
    }

    private static func columnNames(in path: String) -> Set<String>? {
        guard let output = runSQLite(path: path, query: "PRAGMA table_info(record);", separator: "|") else {
            return nil
        }
        var names = Set<String>()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            if fields.count >= 2 { names.insert(String(fields[1])) }
        }
        return names.isEmpty ? nil : names
    }

    private static func runSQLite(path: String, query: String, separator: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-noheader", "-separator", separator, path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Payload helpers

    private static func firstString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func data(fromHex hex: String) -> Data? {
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private struct AppInfo {
        var name: String
        var icon: NSImage?
    }

    private static var appCache: [String: AppInfo] = [:]
    private static let cacheLock = NSLock()

    private static func appInfo(for bundleID: String) -> AppInfo {
        cacheLock.lock()
        if let cached = appCache[bundleID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var info = AppInfo(name: bundleID.split(separator: ".").last.map(String.init) ?? "App", icon: nil)
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            info.name = name.replacingOccurrences(of: ".app", with: "")
            info.icon = NSWorkspace.shared.icon(forFile: url.path)
        }

        cacheLock.lock()
        appCache[bundleID] = info
        cacheLock.unlock()
        return info
    }
}
