import Foundation

/// Locates the vendored MediaRemote helper files.
///
/// They live in `Contents/Resources` inside the built `.app`, and inside the
/// SwiftPM resource bundle when running via `swift run`. We intentionally check
/// the app bundle first so we never touch `Bundle.module` (which traps if its
/// bundle is missing) in a distributed build.
enum AppResources {
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"

    private static let fm = FileManager.default

    static func find(_ name: String) -> URL? {
        for directory in searchDirectories {
            let candidate = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static var searchDirectories: [URL] {
        var directories: [URL] = []

        if let resources = Bundle.main.resourceURL {
            directories.append(resources)
        }
        directories.append(Bundle.main.bundleURL)

        if let executable = Bundle.main.executableURL {
            directories.append(executable.deletingLastPathComponent())
        }

        // Development fallback: `swift run` without a bundled .app.
        if let development = Bundle.module.resourceURL {
            directories.append(development)
        }

        return directories
    }
}
