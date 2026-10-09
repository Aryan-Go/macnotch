import SwiftUI

struct MusicPlayerView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        VStack(spacing: 12) {
            trackRow
            controlRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(NotchViewModel.spring, value: music.nowPlaying.title)
    }

    // MARK: - Track info + progress

    private var trackRow: some View {
        HStack(spacing: 16) {
            ArtworkView(image: music.nowPlaying.artwork, size: 88, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(music.hasMedia ? music.nowPlaying.title : "Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(music.hasMedia ? music.nowPlaying.artist : "Start something in Music or Spotify")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                if !music.nowPlaying.album.isEmpty {
                    Text(music.nowPlaying.album)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    progress(date: context.date)
                }
            }
        }
        .frame(height: 90)
    }

    @ViewBuilder
    private func progress(date: Date) -> some View {
        let duration = music.nowPlaying.duration
        let elapsed = music.nowPlaying.currentElapsed(at: date)
        let fraction = duration > 0 ? elapsed / duration : 0

        VStack(spacing: 4) {
            ProgressTrack(progress: fraction) { value in
                guard duration > 0 else { return }
                music.seek(to: value * duration)
            }
            HStack {
                Text(elapsed.timeString)
                Spacer()
                Text("−" + max(duration - elapsed, 0).timeString)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Controls + volume on one line

    private var controlRow: some View {
        HStack(spacing: 14) {
            transportControls
                .frame(maxWidth: .infinity)
            volumeControl
                .frame(width: 170)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 13) {
            ControlButton(
                systemName: "shuffle",
                size: 30,
                isActive: music.isShuffled
            ) { music.toggleShuffle() }

            ControlButton(systemName: "backward.fill", size: 34, iconScale: 0.42) {
                music.previous()
            }

            ControlButton(
                systemName: music.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                size: 46,
                iconScale: 0.4,
                isActive: true
            ) { music.togglePlayPause() }

            ControlButton(systemName: "forward.fill", size: 34, iconScale: 0.42) {
                music.next()
            }

            ControlButton(
                systemName: music.repeatLabel,
                size: 30,
                isActive: music.isRepeatOn
            ) { music.toggleRepeat() }
        }
        .disabled(!music.hasMedia)
        .opacity(music.hasMedia ? 1 : 0.4)
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button {
                music.toggleMute()
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            LevelTrack(
                value: Binding(
                    get: { music.isMuted ? 0 : music.volume },
                    set: { music.setVolume($0) }
                )
            )

            Text("\(Int((music.isMuted ? 0 : music.volume) * 100))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var volumeSymbol: String {
        if music.isMuted || music.volume == 0 { return "speaker.slash.fill" }
        if music.volume < 0.34 { return "speaker.fill" }
        if music.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}
