import SwiftUI

struct HomeView: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 16) {
            clockRow
            quickActions
            nowPlayingCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var clockRow: some View {
        HStack(alignment: .center, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            batteryRing
        }
    }

    private var batteryRing: some View {
        let battery = SystemStats.battery()
        let level = Double(battery?.level ?? 0) / 100

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, level))
                .stroke(
                    (battery?.isCharging ?? false) ? Color.green : Color.white,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: battery?.symbolName ?? "battery.0")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(battery?.level ?? 0)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 66, height: 66)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ActionTile(systemName: "moon.stars.fill", title: "Dark Mode") {
                SystemStats.toggleDarkMode()
            }
            ActionTile(
                systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                title: "Mute"
            ) {
                music.toggleMute()
            }
            ActionTile(systemName: "lock.fill", title: "Lock") {
                ScreenLock.lock()
            }
        }
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 12) {
            ArtworkView(image: music.nowPlaying.artwork, size: 34, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(music.hasMedia ? music.nowPlaying.title : "Nothing playing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.hasMedia ? music.nowPlaying.artist : "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            if music.hasMedia {
                HStack(spacing: 10) {
                    ControlButton(systemName: "backward.fill", size: 26, iconScale: 0.42) {
                        music.previous()
                    }
                    ControlButton(
                        systemName: music.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                        size: 30,
                        iconScale: 0.4,
                        isActive: true
                    ) { music.togglePlayPause() }
                    ControlButton(systemName: "forward.fill", size: 26, iconScale: 0.42) {
                        music.next()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

private struct ActionTile: View {
    var systemName: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}
