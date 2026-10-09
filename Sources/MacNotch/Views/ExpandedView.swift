import SwiftUI

/// The fully opened notch panel: a tab switcher in the left "ear", live status
/// in the right ear, and the selected module below the notch line.
struct ExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var music: MusicManager
    @ObservedObject var briefs: BriefsModel

    private var notchHeight: CGFloat { viewModel.notchSize.height }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: notchHeight)
                .padding(.horizontal, 16)

            Group {
                switch viewModel.tab {
                case .music: MusicPlayerView(music: music)
                case .home: HomeView(music: music, viewModel: viewModel)
                case .briefs: BriefsView(model: briefs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            tabPicker
            Spacer(minLength: 8)
            statusReadouts
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(NotchViewModel.Tab.allCases) { tab in
                Button {
                    withAnimation(NotchViewModel.quickSpring) { viewModel.tab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.tab == tab ? .black : .white.opacity(0.55))
                        .frame(width: 26, height: 20)
                        .background(
                            Capsule().fill(viewModel.tab == tab ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private var statusReadouts: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 20)) { context in
                StatusChip(
                    systemName: "clock",
                    text: context.date.formatted(date: .omitted, time: .shortened)
                )
            }
            if let battery = SystemStats.battery() {
                StatusChip(
                    systemName: battery.symbolName,
                    text: "\(battery.level)%",
                    tint: battery.isCharging ? .green : .white.opacity(0.85)
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            EqualizerBars(isAnimating: music.nowPlaying.isPlaying, barCount: 4)
                .opacity(music.nowPlaying.isPlaying ? 1 : 0.3)
            Text(music.hasMedia ? "\(music.nowPlaying.sourceName) · \(music.nowPlaying.isPlaying ? "Playing" : "Paused")" : "No media")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}
