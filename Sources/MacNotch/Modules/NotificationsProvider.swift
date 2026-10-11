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
///
/// Notifications keep landing while the app runs, so we read a consistent
/// snapshot (see `SQLite`) rather than copying files by hand — a naive
/// `db` + `-wal` copy can miss freshly delivered rows. Fetches are serialised so
/// overlapping refreshes never fight over the snapshot.
enum NotificationsProvider {
    private static let dbRelativePath =
        "Library/Group Containers/group.com.apple.usernoted/db2/db"

    /// Absolute location of the Notification Center store.
    static var databasePath: String { NSHomeDirectory() + "/" + dbRelativePath }

    /// Whether the Full Disk Access grant is actually in effect for this process.
    /// macOS has no API to query the grant, so we probe the protected file — the
    /// same thing `fetch()` does. Handy for showing the real state in the menu
    /// instead of guessing.
    static var hasAccess: Bool {
        FileManager.default.isReadableFile(atPath: databasePath)
    }

    /// Cheap fingerprint of the store files (size + mtime, plus the access state).
    /// Snapshotting the whole database is expensive, so callers poll this first
    /// and only `fetch()` when it actually changed — that is what lets us look
    /// often enough to catch short-lived notifications without constant I/O.
    static func signature() -> String? {
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: databasePath) else { return nil }
        var parts = ["access"]
        for suffix in ["", "-wal", "-shm"] {
            guard let attributes = try? manager.attributesOfItem(atPath: databasePath + suffix) else {
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            parts.append("\(suffix):\(size):\(modified)")
        }
        return parts.joined(separator: "|")
    }

    private static let queue = DispatchQueue(label: "com.macnotch.notifications.fetch")

    static func fetch() -> Result<[NotificationItem], NotificationsError> {
        queue.sync { fetchLocked() }
    }

    private static func fetchLocked() -> Result<[NotificationItem], NotificationsError> {
        let source = databasePath
        let manager = FileManager.default

        guard manager.fileExists(atPath: source) else { return .failure(.unavailable) }
        guard manager.isReadableFile(atPath: source) else { return .failure(.permissionNeeded) }

        guard let snapshot = SQLite.snapshot(source: source) else {
            return .failure(.permissionNeeded)
        }
        defer { try? manager.removeItem(at: snapshot) }

        guard let columns = columnTypes(in: snapshot.path),
              columns["data"] != nil else {
            return .failure(.unavailable)
        }

        let hasRecID = columns["rec_id"] != nil
        let recIDIsInteger = (columns["rec_id"] ?? "").uppercased().contains("INT")
        let hasDate = columns["delivered_date"] != nil

        let select = [
            hasRecID ? "rec_id" : "NULL",
            "hex(data)",
            columns["app_id"] != nil ? "app_id" : "''",
            hasDate ? "delivered_date" : "NULL"
        ].joined(separator: ", ")

        // Most-recent-first. `rec_id` is the store's insertion rowid, so it keeps
        // ordering correctly even for the freshest rows that carry no
        // delivered_date — the previous date-only ordering silently hid those.
        let order: String
        switch (recIDIsInteger, hasDate) {
        case (true, true): order = "rec_id DESC, delivered_date DESC"
        case (true, false): order = "rec_id DESC"
        case (false, true): order = "delivered_date DESC"
        case (false, false): order = "rowid DESC"
        }

        // Pull well past what we display: the store keeps a sliding window, and
        // rows whose text fails to parse still consume slots, so a shallow limit
        // let recent-but-unparseable rows crowd out later ones.
        let query = """
        SELECT \(select) FROM record \
        WHERE data IS NOT NULL \
        ORDER BY \(order) LIMIT 200;
        """

        guard let output = SQLite.run(path: snapshot.path, query: query) else {
            return .failure(.unavailable)
        }

        // `app_id` is an integer key into the `app` table, so resolve bundle ids
        // from there when a payload doesn't carry one of its own.
        let appIdentifiers = identifierMap(in: snapshot.path)

        var items: [NotificationItem] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let hex = String(fields[1])
            guard !hex.isEmpty, let data = data(fromHex: hex), !data.isEmpty else { continue }

            let delivered = Double(fields[3])
            let key = String(fields[0])

            guard let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }

            // The visible text lives in the request dictionary ("req"), not at the
            // top level of the payload: `titl`/`subt`/`body`.
            let request = payload["req"] as? [String: Any] ?? payload
            let title = text(in: request, keys: ["titl", "tit", "title"]) ?? ""
            let subtitle = text(in: request, keys: ["subt", "sub", "subtitle"]) ?? ""
            let body = text(in: request, keys: ["body", "message"]) ?? ""
            if title.isEmpty && subtitle.isEmpty && body.isEmpty { continue }

            let bundleID = (payload["app"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Int(fields[2]).flatMap { appIdentifiers[$0] }
                ?? ""

            let stamp = (payload["date"] as? Double) ?? (request["date"] as? Double) ?? delivered
            let date = stamp.map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
            let app = appInfo(for: bundleID)
            items.append(NotificationItem(
                id: "\(key)-\(hex.prefix(12))",
                title: title,
                subtitle: subtitle,
                body: body,
                appName: app.name,
                bundleID: bundleID,
                date: date,
                icon: app.icon
            ))
        }

        return .success(items)
    }

    private static func columnTypes(in path: String) -> [String: String]? {
        guard let output = SQLite.run(path: path, query: "PRAGMA table_info(record);") else {
            return nil
        }
        var columns: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            if fields.count >= 3 {
                columns[String(fields[1])] = String(fields[2])
            }
        }
        return columns.isEmpty ? nil : columns
    }

    /// The `app` table maps the integer `app_id` on each record to a bundle id.
    private static func identifierMap(in path: String) -> [Int: String] {
        guard let output = SQLite.run(path: path, query: "SELECT app_id, identifier FROM app;") else {
            return [:]
        }
        var map: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 2, let id = Int(fields[0]), !fields[1].isEmpty else { continue }
            map[id] = String(fields[1])
        }
        return map
    }

    // MARK: - Payload helpers

    /// The first non-empty value among `keys`, flattened to displayable text.
    private static func text(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = flatten(dict[key]) { return value }
        }
        return nil
    }

    /// Notification text is not always a plain string. Modern macOS stores many
    /// request fields as localized-string arrays (`[format, fallback, [args]]`),
    /// and occasionally as raw data or a small dictionary. Reading them with
    /// `as? String` alone silently dropped those entries — which is why whole
    /// apps (Mail among them) never showed up in the feed.
    private static func flatten(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let list as [Any]:
            for item in list {
                if let string = flatten(item) { return string }
            }
            return nil
        case let data as Data:
            guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return nil }
            return string
        case let dictionary as [String: Any]:
            return flatten(dictionary["key"]) ?? flatten(dictionary["ident"])
        default:
            return nil
        }
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
