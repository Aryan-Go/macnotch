import Foundation

/// A WhatsApp conversation, read from the app's local Core Data store.
struct WhatsAppChat: Identifiable, Equatable {
    var jid: String
    var name: String
    var lastMessage: String
    var lastDate: Date
    var unread: Int
    /// The underlying phone-number JID. For newer "linked id" chats the visible
    /// JID is `…@lid`, but WhatsApp still records the real number here.
    var contactIdentifier: String = ""

    var id: String { jid }

    var isGroup: Bool { jid.hasSuffix("@g.us") }

    /// Digits we can hand to the `whatsapp://send?phone=` scheme.
    ///
    /// Plain chats expose the number in their JID; `@lid` chats hide it there,
    /// so we fall back to the stored contact identifier. Groups have neither.
    var phoneDigits: String? {
        guard !isGroup else { return nil }
        for candidate in [jid, contactIdentifier] {
            guard candidate.hasSuffix("@s.whatsapp.net") else { continue }
            let digits = candidate.prefix { $0 != "@" }.filter(\.isNumber)
            if !digits.isEmpty { return String(digits) }
        }
        return nil
    }
}

/// One message in a conversation.
struct WhatsAppMessage: Identifiable, Equatable {
    var id: Int
    var text: String
    var isFromMe: Bool
    var date: Date
}

/// Reads recent conversations and messages from WhatsApp's `ChatStorage.sqlite`.
///
/// WhatsApp keeps the database open with write-ahead logging, so we read a
/// consistent snapshot rather than the live file.
enum WhatsAppStore {
    private static let separator = "\u{1F}"

    static var storagePath: String {
        NSHomeDirectory()
            + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
    }

    static var isAvailable: Bool {
        FileManager.default.isReadableFile(atPath: storagePath)
    }

    static func recentChats(limit: Int = 25) -> [WhatsAppChat] {
        guard let snapshot = SQLite.snapshot(source: storagePath) else { return [] }
        defer { try? FileManager.default.removeItem(at: snapshot) }

        // Some rows carry a far-future sentinel date (~year 6001); without this
        // bound those sort to the top and show up as nonsense conversations.
        let query = """
        SELECT ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGETEXT, ZLASTMESSAGEDATE, ZUNREADCOUNT, ZCONTACTIDENTIFIER \
        FROM ZWACHATSESSION \
        WHERE ZREMOVED = 0 AND ZCONTACTJID IS NOT NULL \
        AND ZLASTMESSAGEDATE > 0 AND ZLASTMESSAGEDATE < \(upperDateBound) \
        ORDER BY ZLASTMESSAGEDATE DESC LIMIT \(limit);
        """

        guard let output = SQLite.run(path: snapshot.path, query: query, separator: separator) else {
            return []
        }

        var chats: [WhatsAppChat] = []
        for line in output.split(separator: "\n") {
            let fields = String(line).components(separatedBy: separator)
            guard fields.count >= 5, !fields[0].isEmpty else { continue }
            let jid = fields[0]
            let name = fields[1].isEmpty ? fallbackName(for: jid) : fields[1]
            chats.append(WhatsAppChat(
                jid: jid,
                name: name,
                lastMessage: fields[2],
                lastDate: referenceDate(fields[3]),
                unread: Int(fields[4]) ?? 0,
                contactIdentifier: fields.count > 5 ? fields[5] : ""
            ))
        }
        return chats
    }

    static func messages(forJID jid: String, limit: Int = 40) -> [WhatsAppMessage] {
        guard let snapshot = SQLite.snapshot(source: storagePath) else { return [] }
        defer { try? FileManager.default.removeItem(at: snapshot) }

        let escaped = jid.replacingOccurrences(of: "'", with: "''")
        let query = """
        SELECT m.Z_PK, m.ZTEXT, m.ZISFROMME, m.ZMESSAGEDATE \
        FROM ZWAMESSAGE m JOIN ZWACHATSESSION s ON m.ZCHATSESSION = s.Z_PK \
        WHERE s.ZCONTACTJID = '\(escaped)' AND m.ZTEXT IS NOT NULL AND m.ZTEXT != '' \
        AND m.ZMESSAGEDATE > 0 AND m.ZMESSAGEDATE < \(upperDateBound) \
        ORDER BY m.ZMESSAGEDATE DESC LIMIT \(limit);
        """

        guard let output = SQLite.run(path: snapshot.path, query: query, separator: separator) else {
            return []
        }

        var messages: [WhatsAppMessage] = []
        for line in output.split(separator: "\n") {
            let fields = String(line).components(separatedBy: separator)
            guard fields.count >= 4 else { continue }
            messages.append(WhatsAppMessage(
                id: Int(fields[0]) ?? 0,
                text: fields[1],
                isFromMe: (Int(fields[2]) ?? 0) == 1,
                date: referenceDate(fields[3])
            ))
        }
        return messages.reversed()
    }

    /// Core Data timestamps are seconds since 2001. Anything past tomorrow is a
    /// sentinel, not a real date.
    private static var upperDateBound: Double {
        Date().timeIntervalSinceReferenceDate + 86_400
    }

    private static func referenceDate(_ raw: String) -> Date {
        guard let value = Double(raw), value > 0, value < upperDateBound else {
            return .distantPast
        }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    private static func fallbackName(for jid: String) -> String {
        let head = jid.split(separator: "@").first.map(String.init) ?? jid
        return head.isEmpty ? "Unknown" : head
    }
}
