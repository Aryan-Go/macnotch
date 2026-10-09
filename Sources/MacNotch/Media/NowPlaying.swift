import AppKit

/// Snapshot of what the system is currently playing.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String
    var applicationName: String
    var isPlaying: Bool
    var duration: Double
    var elapsedTime: Double
    var timestamp: Date
    var playbackRate: Double
    var artwork: NSImage?
    var shuffleMode: Int
    var repeatMode: Int

    static let empty = NowPlaying(
        title: "",
        artist: "",
        album: "",
        bundleIdentifier: "",
        applicationName: "",
        isPlaying: false,
        duration: 0,
        elapsedTime: 0,
        timestamp: .distantPast,
        playbackRate: 0,
        artwork: nil,
        shuffleMode: 1,
        repeatMode: 1
    )

    var isEmpty: Bool { title.isEmpty }

    /// Best-effort real-time playhead, interpolated from the last known snapshot.
    func currentElapsed(at date: Date = Date()) -> Double {
        guard isPlaying, playbackRate > 0, timestamp != .distantPast else {
            return elapsedTime
        }
        let advanced = elapsedTime + date.timeIntervalSince(timestamp) * playbackRate
        if duration > 0 { return min(max(0, advanced), duration) }
        return max(0, advanced)
    }

    /// Friendly name of the source app.
    var sourceName: String {
        if !applicationName.isEmpty { return applicationName }
        switch bundleIdentifier {
        case "com.apple.Music": return "Music"
        case "com.spotify.client": return "Spotify"
        case "com.apple.podcasts": return "Podcasts"
        case "com.tidal.desktop": return "TIDAL"
        case "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox": return "Browser"
        default: return bundleIdentifier.split(separator: ".").last.map(String.init) ?? "Unknown"
        }
    }
}
