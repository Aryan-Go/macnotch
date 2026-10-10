import AppKit
import Combine
import Foundation

/// A call we believe is ringing right now, discovered by inspecting other apps'
/// windows with the Accessibility API.
struct IncomingCall: Equatable, Identifiable {
    var id: String
    var callerName: String
    var appName: String
    var bundleID: String
    var canAccept: Bool
    var canDecline: Bool
}

/// Watches the call windows of FaceTime (which also handles iPhone Continuity
/// calls) and WhatsApp.
///
/// macOS exposes no call API — CallKit's `CXCallObserver` is explicitly
/// unavailable here — so we observe the apps' own windows through Accessibility
/// instead. That has the upside of also handing us the real Accept/Decline
/// buttons, which we press on the user's behalf.
@MainActor
final class CallManager: ObservableObject {
    @Published private(set) var call: IncomingCall?
    @Published private(set) var needsAccessibility = !Permissions.hasAccessibility

    private var timer: Timer?

    private static let acceptTokens = [
        "accept", "answer", "pick up", "pickup"
    ]
    private static let declineTokens = [
        "decline", "reject", "hang up", "hangup", "end call", "dismiss", "deny", "ignore"
    ]

    /// Apps whose call windows we inspect. FaceTime covers Continuity phone
    /// calls; the extra bundle id catches the standalone incoming-call UI on
    /// some macOS versions.
    private static let candidates: [(bundle: String, name: String)] = [
        ("com.apple.FaceTime", "FaceTime"),
        ("com.apple.IncomingCall", "Incoming Call"),
        ("net.whatsapp.WhatsApp", "WhatsApp")
    ]

    func start() {
        if !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
        }
        needsAccessibility = !Permissions.hasAccessibility

        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshPermission() {
        needsAccessibility = !Permissions.hasAccessibility
    }

    func accept() { press(Self.acceptTokens) }
    func decline() { press(Self.declineTokens) }

    // MARK: - Scanning

    private func scan() {
        guard Permissions.hasAccessibility else {
            needsAccessibility = true
            if call != nil { call = nil }
            return
        }
        needsAccessibility = false

        for candidate in Self.candidates {
            guard let app = runningApplication(bundle: candidate.bundle, name: candidate.name) else { continue }
            let application = AX.application(pid: app.processIdentifier)

            for window in AX.windows(of: application) {
                // A ringing call is a compact window. Ignoring large windows keeps
                // a full chat/main window (whose contents could coincidentally
                // mention the right words) from ever being treated as one.
                if let size = AX.size(window), size.width > 900 || size.height > 700 { continue }

                let buttons = AX.elements(ofRole: "AXButton", in: window)
                // A genuinely ringing call shows *both* an answer and a decline
                // control. Requiring both is what keeps ordinary windows — whose
                // chat rows or buttons merely mention "join"/"ignore" — from being
                // mistaken for a call and pinned open forever.
                let hasAccept = buttons.contains { matches($0, Self.acceptTokens) }
                let hasDecline = buttons.contains { matches($0, Self.declineTokens) }
                guard hasAccept, hasDecline else { continue }

                let title = AX.string(window, "AXTitle") ?? ""
                let discovered = IncomingCall(
                    id: "\(app.processIdentifier)-\(title)",
                    callerName: callerName(in: window, title: title, appName: candidate.name),
                    appName: candidate.name,
                    bundleID: candidate.bundle,
                    canAccept: true,
                    canDecline: true
                )
                if call != discovered { call = discovered }
                return
            }
        }

        if call != nil { call = nil }
    }

    /// Re-walks the app's windows and presses the first button matching `tokens`.
    /// We look the element up again each time because AX elements go stale once
    /// the underlying UI changes.
    private func press(_ tokens: [String]) {
        guard Permissions.hasAccessibility else { return }
        for candidate in Self.candidates {
            guard let app = runningApplication(bundle: candidate.bundle, name: candidate.name) else { continue }
            let application = AX.application(pid: app.processIdentifier)
            for window in AX.windows(of: application) {
                if let size = AX.size(window), size.width > 900 || size.height > 700 { continue }
                if let button = AX.elements(ofRole: "AXButton", in: window).first(where: { matches($0, tokens) }) {
                    _ = AX.press(button)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.scan() }
                    return
                }
            }
        }
    }

    private func matches(_ element: AXUIElement, _ tokens: [String]) -> Bool {
        AX.labels(element).contains { label in
            tokens.contains { phrase in Self.label(label, contains: phrase) }
        }
    }

    /// Word-boundary phrase match. A button reading "Join the call" is not an
    /// "answer" control just because it starts with one of the tokens — only a
    /// whole word (or whole phrase, for tokens like "hang up") counts.
    private static func label(_ label: String, contains phrase: String) -> Bool {
        let words = label.split { !$0.isLetter && !$0.isNumber }
        let needle = phrase.split { !$0.isLetter && !$0.isNumber }
        guard !needle.isEmpty, needle.count <= words.count else { return false }
        for start in 0...(words.count - needle.count) where Array(words[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }

    private func callerName(in window: AXUIElement, title: String, appName: String) -> String {
        let generic = ["facetime", "whatsapp", "incoming call", "incoming", "audio", "video", "call", ""]
        if !title.isEmpty, !generic.contains(title.lowercased()) {
            return title
        }
        // Fall back to the first meaningful run of text inside the window.
        for element in AX.elements(ofRole: "AXStaticText", in: window) {
            guard let value = AX.string(element, "AXValue") ?? AX.string(element, "AXDescription") else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !generic.contains(trimmed.lowercased()) {
                return trimmed
            }
        }
        return "\(appName) call"
    }

    private func runningApplication(bundle: String, name: String) -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            return app
        }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundle || $0.localizedName == name
        }
    }
}
