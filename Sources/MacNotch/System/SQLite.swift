import Foundation

/// Helpers for reading SQLite databases that other apps keep open.
///
/// macOS apps journal with write-ahead logging, so copying the files by hand can
/// miss freshly written rows (and racing copies can corrupt the result). We
/// instead take a transactionally-consistent snapshot with SQLite's own
/// `.backup` command, falling back to a raw copy only if that isn't available.
enum SQLite {
    /// A temporary, self-contained copy of `source`, or nil if it can't be read.
    /// Every call gets its own directory so concurrent reads never collide.
    static func snapshot(source: String) -> URL? {
        let manager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macnotch-sqlite-\(UUID().uuidString)")
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }

        let destination = directory.appendingPathComponent("snapshot.db")
        if backup(source: source, destination: destination.path),
           manager.fileExists(atPath: destination.path) {
            return destination
        }
        if copyFiles(source: source, into: directory, name: "snapshot.db") {
            return destination
        }

        try? manager.removeItem(at: directory)
        return nil
    }

    /// Runs a query against a database and returns its `-noheader` output.
    static func run(path: String, query: String, separator: String = "|") -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-noheader", "-separator", separator, path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func backup(source: String, destination: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [source, ".backup '\(destination)'"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func copyFiles(source: String, into directory: URL, name: String) -> Bool {
        let manager = FileManager.default
        var copied = false
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            let to = directory.appendingPathComponent(name + suffix)
            guard (try? manager.copyItem(at: from, to: to)) != nil else {
                if suffix.isEmpty { return false }
                continue
            }
            if suffix.isEmpty { copied = true }
        }
        return copied
    }
}
