import AppKit
import Combine
import SwiftUI

/// Owns the panel, wires the mouse tracking that makes the notch react to hover,
/// and keeps everything positioned on the notched display.
@MainActor
final class NotchController {
    private let panel: NotchPanel
    private let hostingView: NSHostingView<NotchRootView>
    private let viewModel: NotchViewModel
    private let music: MusicManager
    private let briefs: BriefsModel

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var peekDismissWork: DispatchWorkItem?
    private var lastTrackKey: String = ""

    private var screen: NSScreen { NSScreen.notched ?? NSScreen.main ?? NSScreen.screens[0] }
    private var notchFrame: NSRect { screen.notchFrameWithFallback }

    init(music: MusicManager, briefs: BriefsModel) {
        self.music = music
        self.briefs = briefs

        let screen = NSScreen.notched ?? NSScreen.main ?? NSScreen.screens[0]
        let notch = screen.notchFrameWithFallback
        let model = NotchViewModel(notchSize: notch.size)
        self.viewModel = model

        let panelSize = model.panelSize
        let frame = NSRect(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )

        self.panel = NotchPanel(contentRect: frame)
        self.hostingView = NSHostingView(rootView: NotchRootView(viewModel: model, music: music, briefs: briefs))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        observeState()
        observeMusic()
        installMonitors()
        observeScreenChanges()
    }

    // MARK: - Observation

    private func observeState() {
        viewModel.$visualState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.panel.ignoresMouseEvents = (state != .expanded)
                if state == .expanded {
                    self.briefs.refreshAll()
                } else {
                    self.panel.resignKey()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMusic() {
        music.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] now in
                guard let self else { return }
                let key = "\(now.title)|\(now.artist)|\(now.isPlaying)"
                guard key != self.lastTrackKey else { return }
                let isFirstEvent = self.lastTrackKey.isEmpty
                self.lastTrackKey = key
                // Don't pop the notch open on launch just because something is
                // already playing — only on real track changes.
                if !isFirstEvent, !now.isEmpty, self.viewModel.visualState == .hidden {
                    self.showPeek()
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    private func reposition() {
        let screen = self.screen
        let size = viewModel.panelSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Peek

    private func showPeek() {
        peekDismissWork?.cancel()
        viewModel.peek()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.viewModel.visualState == .peek else { return }
            self.viewModel.collapse()
        }
        peekDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    // MARK: - Mouse tracking

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            self.handleMouse(at: NSEvent.mouseLocation, type: event.type)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            self.handleMouse(at: NSEvent.mouseLocation, type: event.type)
            return event
        }
    }

    /// Region that reveals the compact peek, in global screen coordinates.
    /// Deliberately tight around the notch so the peek stays put while you look
    /// at it, and only opens fully once you push the cursor down onto the card.
    private var hoverRect: NSRect {
        let notch = notchFrame
        return NSRect(
            x: notch.minX - 16,
            y: notch.minY - 8,
            width: notch.width + 32,
            height: notch.height + 12
        )
    }

    /// The part of the peek card that hangs below the notch. Moving onto it
    /// expands the panel.
    private var peekRect: NSRect {
        let notch = notchFrame
        let size = viewModel.peekSize
        let extra = max(0, size.height - notch.height)
        return NSRect(
            x: notch.midX - size.width / 2,
            y: notch.minY - extra,
            width: size.width,
            height: extra
        )
    }

    /// Region that keeps the panel open once expanded. Uses the largest module
    /// size so switching tabs never yanks the panel shut under the cursor.
    private var expandedRect: NSRect {
        let notch = notchFrame
        let size = viewModel.maxExpandedSize
        return NSRect(
            x: notch.midX - size.width / 2,
            y: notch.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -8, dy: -8)
    }

    private func handleMouse(at location: NSPoint, type: NSEvent.EventType) {
        let onNotch = hoverRect.contains(location)
        let onPeekCard = peekRect.contains(location)

        switch viewModel.visualState {
        case .hidden:
            guard onNotch else { return }
            peekDismissWork?.cancel()
            viewModel.peek()

        case .peek:
            // Looking at the card (or still on the notch) keeps it up.
            if onNotch || onPeekCard { peekDismissWork?.cancel() }

            if type == .leftMouseDown, onNotch {
                viewModel.isPinned = true
                viewModel.expand()
            } else if !onNotch, onPeekCard {
                // Pushed down onto the card — open the full panel.
                viewModel.expand()
            } else if !onNotch, !onPeekCard {
                viewModel.collapse()
            }

        case .expanded:
            if type == .leftMouseDown {
                if onNotch {
                    // Clicking the notch strip keeps the panel open.
                    viewModel.isPinned = true
                } else if !expandedRect.contains(location) {
                    // Clicking away closes and unpins.
                    viewModel.isPinned = false
                    viewModel.collapse()
                }
                return
            }
            if !expandedRect.contains(location) && !viewModel.isPinned {
                viewModel.collapse()
            }
        }
    }

    func toggleExpanded() {
        viewModel.togglePinned()
    }
}
