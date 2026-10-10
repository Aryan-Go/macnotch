import ApplicationServices
import Foundation

/// Thin wrappers over the Accessibility API used to inspect and drive other
/// apps' windows (the call UI in particular). Attribute names are written as
/// literals so this stays robust across SDKs.
enum AX {
    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    /// A single child attribute that holds another element (`AXMainWindow`,
    /// `AXFocusedWindow`, …), validated so a non-element value can't be misread.
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
    }

    static func windows(of application: AXUIElement) -> [AXUIElement] {
        (attribute(application, "AXWindows") as? [AXUIElement]) ?? []
    }

    /// The element's `AXSize`, if it exposes one.
    static func size(_ element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, "AXSize"), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, "AXRole")
    }

    /// The accessible name of a control, lowercased.
    ///
    /// Only the attributes that actually carry a control's label are read.
    /// `AXValue` is deliberately excluded: it can hold arbitrary content (a chat
    /// row's message text, for instance), which previously made ordinary windows
    /// look like a ringing call.
    ///
    /// Labels from Catalyst apps are decorated with invisible directional marks
    /// (U+200E and friends), so those are stripped before matching.
    static func labels(_ element: AXUIElement) -> [String] {
        ["AXTitle", "AXDescription", "AXHelp"]
            .compactMap { string(element, $0) }
            .map(cleaned)
            .filter { !$0.isEmpty }
    }

    private static func cleaned(_ raw: String) -> String {
        String(raw.unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint && !CharacterSet.controlCharacters.contains($0) })
            .lowercased()
    }

    /// Moves keyboard focus to an element (`AXFocused`).
    @discardableResult
    static func setFocused(_ element: AXUIElement, _ focused: Bool) -> Bool {
        let value: CFBoolean = focused ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(element, "AXFocused" as CFString, value) == .success
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, "AXPress" as CFString) == .success
    }

    static func isEnabled(_ element: AXUIElement) -> Bool {
        (attribute(element, "AXEnabled") as? Bool) ?? true
    }

    static func value(_ element: AXUIElement) -> String? {
        attribute(element, "AXValue") as? String
    }

    @discardableResult
    static func setValue(_ element: AXUIElement, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, "AXValue" as CFString, value) == .success
    }

    /// Whether an attribute can be written — used to tell an editable composer
    /// apart from a read-only label that merely looks like a text field.
    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    /// The window roots to walk for an application.
    ///
    /// `AXWindows` only lists a window while its app is frontmost — a background
    /// app (WhatsApp after a quick reply) reports none even though the window is
    /// on screen. `AXMainWindow`/`AXFocusedWindow` still resolve in that state, so
    /// fall back to those before giving up on the application element itself.
    static func roots(of application: AXUIElement) -> [AXUIElement] {
        let windows = windows(of: application)
        if !windows.isEmpty { return windows }
        for name in ["AXMainWindow", "AXFocusedWindow"] {
            if let window = element(application, name) {
                return [window]
            }
        }
        return [application]
    }

    /// Every element of the given role across all of an application's windows.
    static func allElements(ofRole role: String, in application: AXUIElement, maxDepth: Int = 14) -> [AXUIElement] {
        roots(of: application).flatMap { elements(ofRole: role, in: $0, maxDepth: maxDepth) }
    }

    /// Breadth-first walk collecting every element of the given role.
    static func elements(ofRole role: String, in root: AXUIElement, maxDepth: Int = 14) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while let (element, depth) = queue.popLast() {
            if Self.role(element) == role { matches.append(element) }
            guard depth < maxDepth else { continue }
            for child in children(element) {
                queue.append((child, depth + 1))
            }
        }
        return matches
    }
}
