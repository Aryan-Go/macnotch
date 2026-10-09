import AppKit

/// Thread-safe accumulator for a child process's stdout.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Thin wrapper around the bundled `mediaremote-adapter` Perl script.
///
/// Apple restricts direct use of the private MediaRemote framework from app
/// processes (macOS 15.4+). The bundled script is run by `/usr/bin/perl`, which
/// is entitled to talk to the framework, and we just read/write its stdout/stdin.
///
/// `@unchecked Sendable`: instances hold only immutable paths, and every
/// operation spawns its own process rather than mutating shared state.
final class MediaRemoteAdapter: @unchecked Sendable {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    let scriptURL: URL
    let frameworkURL: URL

    init?() {
        guard let script = AppResources.find(AppResources.scriptName),
              let framework = AppResources.find(AppResources.frameworkName),
              FileManager.default.fileExists(
                atPath: framework.appendingPathComponent("MediaRemoteAdapter").path
              )
        else { return nil }

        self.scriptURL = script
        self.frameworkURL = framework
    }

    /// Base arguments shared by every invocation.
    private var baseArguments: [String] {
        [scriptURL.path, frameworkURL.path]
    }

    /// Runs a one-shot command (get/send/seek/...). Returns stdout on success.
    ///
    /// stdout is drained on the pipe's own queue while we wait: `get` can emit
    /// a couple of hundred KB of base64 artwork, which is far more than the
    /// pipe buffer, so reading only after exit would deadlock both sides.
    @discardableResult
    func runOneShot(_ arguments: [String], timeout: TimeInterval = 3.0) -> String? {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = baseArguments + arguments

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let box = DataBox()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            box.append(chunk)
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        var exited = finished.wait(timeout: .now() + timeout) == .success
        if !exited {
            process.terminate()
            exited = finished.wait(timeout: .now() + 1.0) == .success
        }
        out.fileHandleForReading.readabilityHandler = nil

        guard exited, process.terminationStatus == 0 else { return nil }
        return String(data: box.value, encoding: .utf8)
    }

    /// Starts a long-lived `stream` process that emits newline-delimited JSON.
    ///
    /// The helper is wrapped in a tiny shell watchdog. The Perl process only
    /// writes when the track *changes*, so if it is orphaned (app force-quit or
    /// crashed) it would sit there forever holding a MediaRemote client. The
    /// watchdog kills it as soon as either it or this app goes away.
    func startStream(onLine: @escaping (String) -> Void) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.watchdogScript, "sh", scriptURL.path, frameworkURL.path]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            let newline = UInt8(ascii: "\n")
            while let index = buffer.firstIndex(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<index)
                buffer.removeSubrange(buffer.startIndex...index)
                guard !lineData.isEmpty,
                      let line = String(data: lineData, encoding: .utf8) else { continue }
                onLine(line)
            }
        }

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }

    /// `$1` = perl script, `$2` = framework. Exits when either the helper or the
    /// parent application disappears.
    private static let watchdogScript = """
    parent=$PPID
    /usr/bin/perl "$1" "$2" stream &
    child=$!
    trap 'kill "$child" 2>/dev/null; exit 0' TERM INT
    while kill -0 "$child" 2>/dev/null && kill -0 "$parent" 2>/dev/null; do
      sleep 1
    done
    kill "$child" 2>/dev/null
    wait "$child" 2>/dev/null
    """

    func stopStream(_ process: Process?) {
        guard let process else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    /// MediaRemote command IDs (see adapter README).
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
        case toggleShuffle = 6
        case toggleRepeat = 7
        case goBackFifteenSeconds = 12
        case skipFifteenSeconds = 13
    }

    func send(_ command: Command) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runOneShot(["send", String(command.rawValue)])
        }
    }

    func seek(toSeconds seconds: Double) {
        let micros = max(0, Int(seconds * 1_000_000))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runOneShot(["seek", String(micros)])
        }
    }

    /// mode: 1 = off, 2 = albums, 3 = tracks
    func setShuffle(_ mode: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runOneShot(["shuffle", String(mode)])
        }
    }

    /// mode: 1 = off, 2 = one, 3 = all
    func setRepeat(_ mode: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runOneShot(["repeat", String(mode)])
        }
    }
}
