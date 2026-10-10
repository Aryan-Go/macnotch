import AppKit
import ApplicationServices
import Combine
import Foundation

/// Backs the WhatsApp tab: recent conversations, the selected thread, and a
/// quick-reply composer.
@MainActor
final class WhatsAppModel: ObservableObject {
    @Published private(set) var chats: [WhatsAppChat] = []
    @Published private(set) var messages: [WhatsAppMessage] = []
    @Published var selected: WhatsAppChat?
    @Published var draft: String = ""
    @Published private(set) var isAvailable = WhatsAppStore.isAvailable
    @Published private(set) var note: String?

    private var timer: Timer?
    /// Handed out (below zero) to replies we've shown before WhatsApp has stored
    /// them, so a bubble can be recognised as not-yet-persisted.
    private var pendingCounter = 0

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let available = WhatsAppStore.isAvailable
            let chats = available ? WhatsAppStore.recentChats() : []
            await MainActor.run {
                self.isAvailable = available
                self.chats = chats
                if let current = self.selected, let updated = chats.first(where: { $0.jid == current.jid }) {
                    self.selected = updated
                    self.loadMessages()
                } else if self.selected == nil || !chats.contains(where: { $0.jid == self.selected?.jid }) {
                    self.selected = chats.first
                    self.loadMessages()
                }
            }
        }
    }

    func select(_ chat: WhatsAppChat) {
        guard chat.id != selected?.id else { return }
        selected = chat
        draft = ""
        note = nil
        messages = []
        loadMessages()
    }

    func loadMessages() {
        guard let chat = selected else {
            messages = []
            return
        }
        Task.detached(priority: .utility) {
            let items = WhatsAppStore.messages(forJID: chat.jid)
            await MainActor.run { self.apply(items, forJID: chat.jid) }
        }
    }

    /// Merges a freshly read conversation with replies we're still showing
    /// optimistically. A pending bubble (negative id) is dropped once WhatsApp's
    /// store contains the matching outgoing message, so the real row takes over.
    private func apply(_ items: [WhatsAppMessage], forJID jid: String) {
        guard selected?.jid == jid else { return }
        var persisted = items.filter(\.isFromMe).map(\.text)
        var stillPending: [WhatsAppMessage] = []
        for pending in messages where pending.id < 0 {
            if let index = persisted.firstIndex(of: pending.text) {
                persisted.remove(at: index)
            } else {
                stillPending.append(pending)
            }
        }
        messages = items + stillPending
    }

    /// Replyable directly when we can hand WhatsApp a phone number.
    var canReply: Bool { selected?.phoneDigits != nil }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chat = selected else { return }
        draft = ""
        note = nil

        // Show the reply immediately. WhatsApp's store can lag a send by seconds
        // — sometimes until the app next saves — so waiting on a re-read made a
        // sent message look like it had vanished.
        let pending = WhatsAppMessage(id: nextPendingID(), text: text, isFromMe: true, date: Date())
        messages.append(pending)

        WhatsAppSender.send(text: text, to: chat) { [weak self] outcome in
            Task { @MainActor in
                switch outcome {
                case .sent:
                    self?.reconcile()
                case .manual(let message):
                    self?.messages.removeAll { $0.id == pending.id }
                    self?.draft = text
                    self?.note = message
                }
            }
        }
    }

    private func nextPendingID() -> Int {
        pendingCounter -= 1
        return pendingCounter
    }

    /// Polls the store a few times so the optimistic bubble is replaced by the
    /// stored message (with its real id) as soon as WhatsApp writes it.
    private func reconcile() {
        for delay in [0.4, 1.2, 2.5, 5.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.loadMessages()
            }
        }
    }
}

/// Delivers a quick reply without pulling WhatsApp to the front.
///
/// We still use the `whatsapp://send` scheme to open the right conversation with
/// the text prefilled, but the URL is opened *in the background*: bringing
/// WhatsApp forward is what trips its screen lock, which is exactly what a reply
/// from the notch is meant to avoid. Keystrokes normally follow the frontmost
/// app, so Return goes directly to WhatsApp's own process instead of the active
/// app. Everything is driven through the Accessibility API.
enum WhatsAppSender {
    private static let whatsAppBundleID = "net.whatsapp.WhatsApp"

    enum Outcome {
        /// Handed off to WhatsApp and pressed Send.
        case sent
        /// Couldn't finish automatically; show the note (and keep the draft).
        case manual(String)
    }

    static func send(text: String, to chat: WhatsAppChat, completion: @escaping (Outcome) -> Void) {
        guard let digits = chat.phoneDigits else {
            if let url = URL(string: "whatsapp://") { open(url, activates: true) }
            completion(.manual(chat.isGroup ? "Reply to groups in WhatsApp" : "Open WhatsApp to reply"))
            return
        }

        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [
            URLQueryItem(name: "phone", value: digits),
            URLQueryItem(name: "text", value: text)
        ]
        guard let url = components.url else {
            completion(.manual("Couldn't build a WhatsApp link"))
            return
        }

        guard Permissions.hasAccessibility else {
            // Without Accessibility the only way to finish is by hand, so let the
            // prefilled chat come forward and say what to do.
            open(url, activates: true)
            completion(.manual("Opened WhatsApp — press Return to send"))
            return
        }

        open(url, activates: false)
        deliver(text: text, closeWhenDone: isWindowless(), attempt: 0, completion: completion)
    }

    /// The URL is handled asynchronously and WhatsApp may need a moment to build
    /// (and focus) the composer, so work at it over a short window before giving
    /// up. Everything runs through the Accessibility API, which keeps working on
    /// WhatsApp while it stays in the background.
    ///
    /// WhatsApp for Mac is a Catalyst app: its Send button often reports a
    /// successful `AXPress` without anything actually being sent. So after
    /// clicking it we confirm the composer emptied, and if our text is still
    /// sitting there we send a real Return instead — which WhatsApp always
    /// honours while the composer holds focus.
    private static func deliver(
        text: String,
        closeWhenDone: Bool,
        attempt: Int,
        completion: @escaping (Outcome) -> Void
    ) {
        let maxAttempts = 20

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: whatsAppBundleID).first else {
            retry(attempt: attempt, max: maxAttempts, fail: "Open WhatsApp once, then retry", completion: completion) {
                deliver(text: text, closeWhenDone: closeWhenDone, attempt: attempt + 1, completion: completion)
            }
            return
        }

        let application = AX.application(pid: app.processIdentifier)
        guard let composer = composer(in: application) else {
            retry(attempt: attempt, max: maxAttempts, fail: "Couldn't reach the WhatsApp message box", completion: completion) {
                deliver(text: text, closeWhenDone: closeWhenDone, attempt: attempt + 1, completion: completion)
            }
            return
        }

        if AX.value(composer) != text {
            AX.setValue(composer, text as CFTypeRef)
            AX.setFocused(composer, true)
        }

        // The box must actually hold our text before a Send means anything.
        guard AX.value(composer) == text else {
            retry(attempt: attempt, max: maxAttempts, fail: "Couldn't reach the WhatsApp message box", completion: completion) {
                deliver(text: text, closeWhenDone: closeWhenDone, attempt: attempt + 1, completion: completion)
            }
            return
        }

        if let button = sendButton(in: application), AX.isEnabled(button) {
            _ = AX.press(button)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AX.value(composer) != text {
                finish(closeWhenDone: closeWhenDone, application: application, completion: completion)
                return
            }
            postReturn(to: app.processIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if AX.value(composer) != text {
                    finish(closeWhenDone: closeWhenDone, application: application, completion: completion)
                } else if attempt < maxAttempts {
                    deliver(text: text, closeWhenDone: closeWhenDone, attempt: attempt + 1, completion: completion)
                } else {
                    completion(.manual("Couldn't send — open WhatsApp once, then retry"))
                }
            }
        }
    }

    private static func retry(
        attempt: Int,
        max: Int,
        fail: String,
        completion: @escaping (Outcome) -> Void,
        _ work: @escaping () -> Void
    ) {
        guard attempt < max else {
            completion(.manual(fail))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private static func finish(closeWhenDone: Bool, application: AXUIElement, completion: @escaping (Outcome) -> Void) {
        // WhatsApp only keeps the chat in a real window, so if none was open
        // before the reply we're the reason one exists now — tidy it away.
        if closeWhenDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { closeWindow(application) }
        }
        completion(.sent)
    }

    private static func composer(in application: AXUIElement) -> AXUIElement? {
        let fields = AX.allElements(ofRole: "AXTextArea", in: application)
            + AX.allElements(ofRole: "AXTextField", in: application)
        return fields.first { AX.isSettable($0, "AXValue") }
    }

    private static func sendButton(in application: AXUIElement) -> AXUIElement? {
        AX.allElements(ofRole: "AXButton", in: application).first(where: matchesSend)
    }

    private static func postReturn(to pid: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let key = CGKeyCode(0x24) // Return
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.postToPid(pid)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.postToPid(pid)
    }

    /// Whether WhatsApp is running with no window open, so we know a window that
    /// appears after our reply belongs to us.
    private static func isWindowless() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: whatsAppBundleID).first else {
            return true
        }
        let application = AX.application(pid: app.processIdentifier)
        return AX.element(application, "AXMainWindow") == nil && AX.element(application, "AXFocusedWindow") == nil
    }

    private static func closeWindow(_ application: AXUIElement) {
        for root in AX.roots(of: application) {
            if let close = AX.elements(ofRole: "AXButton", in: root).first(where: { AX.string($0, "AXSubrole") == "AXCloseButton" }) {
                _ = AX.press(close)
                return
            }
        }
    }

    private static func matchesSend(_ element: AXUIElement) -> Bool {
        AX.labels(element).contains { $0.contains("send") }
    }

    private static func open(_ url: URL, activates: Bool) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.open(url, configuration: configuration) { _, _ in }
    }
}
