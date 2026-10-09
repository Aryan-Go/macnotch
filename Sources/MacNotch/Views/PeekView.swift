import SwiftUI

/// Collapsed state: the black shape exactly covers the hardware notch, so the
/// panel is effectively invisible.
struct HiddenNotchView: View {
    var body: some View {
        Color.clear
    }
}

/// Compact "live activity" that drops out of the notch when the track changes.
struct PeekView: View {
    @ObservedObject var music: MusicManager
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                ArtworkView(image: music.nowPlaying.artwork, size: 26, cornerRadius: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(music.nowPlaying.title.isEmpty ? "Nothing playing" : music.nowPlaying.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(music.nowPlaying.artist.isEmpty ? music.nowPlaying.sourceName : music.nowPlaying.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                EqualizerBars(isAnimating: music.nowPlaying.isPlaying)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
    }
}
