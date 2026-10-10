import AppKit
import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    enum VisualState: Equatable {
        case hidden
        case peek
        case expanded
    }

    enum Tab: String, CaseIterable, Identifiable {
        case music = "Music"
        case home = "Home"
        case briefs = "Briefs"
        case whatsapp = "WhatsApp"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .music: return "music.note"
            case .home: return "house.fill"
            case .briefs: return "square.grid.2x2.fill"
            case .whatsapp: return "message.fill"
            }
        }
    }

    @Published var visualState: VisualState = .hidden
    @Published var tab: Tab = .music
    @Published var isPinned = false

    /// Set by the controller while a call is ringing; takes over the panel.
    @Published var activeCall: IncomingCall?
    var isCallActive: Bool { activeCall != nil }

    let notchSize: NSSize

    init(notchSize: NSSize) {
        self.notchSize = notchSize
    }

    // MARK: - Sizes

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width, height: notchSize.height)
    }

    var peekSize: CGSize {
        CGSize(
            width: max(notchSize.width + 150, 300),
            height: notchSize.height + 44
        )
    }

    var expandedSize: CGSize { expandedSize(for: tab) }

    /// Size of the incoming-call takeover card.
    var callSize: CGSize {
        CGSize(width: max(notchSize.width + 340, 520), height: notchSize.height + 96)
    }

    /// Each module needs a different amount of vertical room.
    func expandedSize(for tab: Tab) -> CGSize {
        let height: CGFloat
        switch tab {
        case .music: height = notchSize.height + 196
        case .home: height = notchSize.height + 258
        case .briefs: height = notchSize.height + 330
        case .whatsapp: height = notchSize.height + 320
        }
        return CGSize(width: max(notchSize.width + 340, 560), height: height)
    }

    /// Largest open size, used to size the panel and the hover region.
    var maxExpandedSize: CGSize {
        let sizes = Tab.allCases.map { expandedSize(for: $0) } + [callSize]
        return CGSize(
            width: sizes.map(\.width).max() ?? expandedSize.width,
            height: sizes.map(\.height).max() ?? expandedSize.height
        )
    }

    var currentSize: CGSize {
        if isCallActive { return callSize }
        switch visualState {
        case .hidden: return collapsedSize
        case .peek: return peekSize
        case .expanded: return expandedSize
        }
    }

    /// Panel is larger than any visual state so content can animate freely.
    var panelSize: CGSize {
        CGSize(width: maxExpandedSize.width + 80, height: maxExpandedSize.height + 80)
    }

    var topCornerRadius: CGFloat {
        visualState == .hidden && !isCallActive ? 4 : 8
    }

    var bottomCornerRadius: CGFloat {
        if isCallActive { return 24 }
        switch visualState {
        case .hidden: return 10
        case .peek: return 20
        case .expanded: return 28
        }
    }

    // MARK: - Transitions

    func expand(tab: Tab? = nil) {
        if let tab { self.tab = tab }
        withAnimation(NotchViewModel.spring) { visualState = .expanded }
    }

    func peek() {
        guard visualState == .hidden, !isPinned else { return }
        withAnimation(NotchViewModel.spring) { visualState = .peek }
    }

    func collapse() {
        guard !isPinned else { return }
        withAnimation(NotchViewModel.spring) { visualState = .hidden }
    }

    func togglePinned() {
        isPinned.toggle()
        if isPinned {
            expand()
        } else {
            collapse()
        }
    }

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let quickSpring = Animation.spring(response: 0.28, dampingFraction: 0.8)
}
