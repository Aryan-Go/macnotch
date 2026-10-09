import AppKit
import Combine

/// Owns the connection to the MediaRemote adapter, keeps a merged view of the
/// now-playing state, and exposes playback + volume controls to the UI.
@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying = .empty
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var isMuted: Bool = false

    private let adapter: MediaRemoteAdapter?
    private var streamProcess: Process?
    private var restartWorkItem: DispatchWorkItem?
    private var isStopping = false

    // Merged raw payload from the JSON stream (diff updates patch this).
    private var merged: [String: Any] = [:]
    private var lastArtworkData: Data?

    private lazy var isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private lazy var isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init() {
        adapter = MediaRemoteAdapter()
        isAvailable = adapter != nil
    }

    // MARK: - Lifecycle

    func start() {
        guard let adapter else { return }
        isStopping = false
        self.volume = SystemAudio.outputVolume()
        self.isMuted = SystemAudio.isMuted()

        // Warm the adapter up off the main thread so launch never blocks.
        DispatchQueue.global(qos: .utility).async {
            adapter.runOneShot(["get"])
        }

        startStream()
        SystemAudio.observeVolumeChanges { [weak self] in
            self?.volume = SystemAudio.outputVolume()
            self?.isMuted = SystemAudio.isMuted()
        }
    }

    private func startStream() {
        guard let adapter else { return }
        streamProcess = adapter.startStream { [weak self] line in
            Task { @MainActor in self?.handle(line: line) }
        }
        streamProcess?.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleRestart() }
        }
    }

    private func scheduleRestart() {
        guard !isStopping else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopping else { return }
            self.startStream()
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func stop() {
        isStopping = true
        restartWorkItem?.cancel()
        adapter?.stopStream(streamProcess)
        streamProcess = nil
    }

    // MARK: - Stream parsing

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let isDiff = (object["diff"] as? Bool) ?? false
        guard let payload = object["payload"] as? [String: Any] else { return }

        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    merged.removeValue(forKey: key)
                } else {
                    merged[key] = value
                }
            }
        } else {
            merged = payload
        }

        rebuildModel()
    }

    private func rebuildModel() {
        let title = merged["title"] as? String ?? ""

        guard !title.isEmpty else {
            nowPlaying = .empty
            lastArtworkData = nil
            return
        }

        let artwork = decodeArtwork()

        let previous = nowPlaying
        let isSameTrack = previous.title == title
            && previous.artist == (merged["artist"] as? String ?? "")

        var model = NowPlaying(
            title: title,
            artist: merged["artist"] as? String ?? "",
            album: merged["album"] as? String ?? "",
            bundleIdentifier: merged["bundleIdentifier"] as? String ?? "",
            applicationName: merged["applicationName"] as? String ?? "",
            isPlaying: merged["playing"] as? Bool ?? false,
            duration: double(merged["duration"]),
            elapsedTime: double(merged["elapsedTime"]),
            timestamp: parseTimestamp(merged["timestamp"]),
            playbackRate: double(merged["playbackRate"], fallback: (merged["playing"] as? Bool ?? false) ? 1 : 0),
            artwork: artwork ?? (isSameTrack ? previous.artwork : nil),
            shuffleMode: int(merged["shuffleMode"], fallback: 1),
            repeatMode: int(merged["repeatMode"], fallback: 1)
        )

        if model.playbackRate == 0 && model.isPlaying { model.playbackRate = 1 }
        nowPlaying = model
    }

    private func decodeArtwork() -> NSImage? {
        guard let base64 = merged["artworkData"] as? String, !base64.isEmpty else { return nil }
        if let cached = lastArtworkData, cached == Data(base64Encoded: base64) {
            return nowPlaying.artwork
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        lastArtworkData = data
        return NSImage(data: data)
    }

    private func double(_ value: Any?, fallback: Double = 0) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return fallback
    }

    private func int(_ value: Any?, fallback: Int) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return fallback
    }

    private func parseTimestamp(_ value: Any?) -> Date {
        guard let string = value as? String else { return Date() }
        return isoFormatter.date(from: string)
            ?? isoFormatterNoFraction.date(from: string)
            ?? Date()
    }

    // MARK: - Controls

    var hasMedia: Bool { !nowPlaying.isEmpty }

    func togglePlayPause() {
        nowPlaying.isPlaying.toggle()
        nowPlaying.timestamp = Date()
        adapter?.send(.togglePlayPause)
    }

    func next() { adapter?.send(.nextTrack) }
    func previous() { adapter?.send(.previousTrack) }
    func skipForward() { adapter?.send(.skipFifteenSeconds) }
    func skipBackward() { adapter?.send(.goBackFifteenSeconds) }

    func seek(to seconds: Double) {
        nowPlaying.elapsedTime = seconds
        nowPlaying.timestamp = Date()
        adapter?.seek(toSeconds: seconds)
    }

    func toggleShuffle() { adapter?.send(.toggleShuffle) }

    func toggleRepeat() { adapter?.send(.toggleRepeat) }

    var isShuffled: Bool { nowPlaying.shuffleMode != 1 }
    var repeatLabel: String {
        switch nowPlaying.repeatMode {
        case 2: return "repeat.1"
        case 3: return "repeat"
        default: return "repeat"
        }
    }
    var isRepeatOn: Bool { nowPlaying.repeatMode != 1 }

    // MARK: - Volume

    func setVolume(_ value: Double) {
        volume = value
        if value > 0 && isMuted {
            isMuted = false
            SystemAudio.setMuted(false)
        }
        SystemAudio.setOutputVolume(value)
    }

    func toggleMute() {
        isMuted.toggle()
        SystemAudio.setMuted(isMuted)
    }
}
