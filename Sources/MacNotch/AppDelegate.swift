import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private let music = MusicManager()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        music.start()
        controller = NotchController(music: music)
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
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
        let quit = NSMenuItem(title: "Quit MacNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleNotch() {
        controller?.toggleExpanded()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
