import AppKit

extension NSScreen {
    /// The screen that physically has a notch (the built-in display).
    /// Falls back to the screen with the mouse, then the main screen.
    static var notched: NSScreen? {
        if let screen = screens.first(where: { $0.hasNotch }) {
            return screen
        }
        return screenWithMouse ?? main
    }

    static var screenWithMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    /// True when the display has a hardware notch.
    var hasNotch: Bool {
        auxiliaryTopLeftArea?.width != nil && auxiliaryTopRightArea?.width != nil
    }

    var notchSize: NSSize? {
        guard
            let left = auxiliaryTopLeftArea?.width,
            let right = auxiliaryTopRightArea?.width
        else { return nil }
        let height = safeAreaInsets.top
        let width = frame.width - left - right
        guard width > 0, height > 0 else { return nil }
        return NSSize(width: width, height: height)
    }

    /// The notch rectangle in global (bottom-left origin) screen coordinates.
    var notchFrame: NSRect? {
        guard let size = notchSize else { return nil }
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    /// Notch frame if present, otherwise a sane stand-in centered on the top edge
    /// so the app still works on Macs without a notch / external displays.
    var notchFrameWithFallback: NSRect {
        if let notchFrame { return notchFrame }
        let width: CGFloat = 200
        let height = max(menuBarHeight, 24)
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }
}
