import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: NotchController?
    private let music = MusicManager()
    private let briefs = BriefsModel()
    private let calls = CallManager()
    private let whatsapp = WhatsAppModel()
    private var statusItem: NSStatusItem?
    private var accessibilityItem: NSMenuItem?
    private var diskAccessItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        music.start()
        briefs.start()
        calls.start()
        whatsapp.start()
        controller = NotchController(music: music, briefs: briefs, calls: calls, whatsapp: whatsapp)
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        briefs.stop()
        calls.stop()
        whatsapp.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "music.note.list",
                accessibilityDescription: "MacNotch"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "MacNotch", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show notch", action: #selector(toggleNotch), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let accessibility = NSMenuItem(
            title: "Enable call detection (Accessibility)…",
            action: #selector(grantAccessibility),
            keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)
        accessibilityItem = accessibility

        let diskAccess = NSMenuItem(
            title: "Full Disk Access (notifications)…",
            action: #selector(grantFullDiskAccess),
            keyEquivalent: ""
        )
        diskAccess.target = self
        menu.addItem(diskAccess)
        diskAccessItem = diskAccess

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
        updatePermissionItems()
    }

    /// Reflect the *live* permission state each time the menu opens, so granting
    /// access in System Settings is confirmed without relaunching.
    func menuNeedsUpdate(_ menu: NSMenu) {
        calls.refreshPermission()
        updatePermissionItems()
    }

    private func updatePermissionItems() {
        let hasAccessibility = Permissions.hasAccessibility
        accessibilityItem?.title = hasAccessibility ? "Call detection enabled" : "Enable call detection (Accessibility)…"
        accessibilityItem?.isEnabled = !hasAccessibility

        let hasDiskAccess = NotificationsProvider.hasAccess
        diskAccessItem?.title = hasDiskAccess ? "Notification access enabled" : "Full Disk Access (notifications)…"
    }

    @objc private func grantAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
        calls.refreshPermission()
    }

    @objc private func grantFullDiskAccess() {
        Permissions.openFullDiskAccessSettings()
    }

    @objc private func toggleNotch() {
        controller?.toggleExpanded()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
