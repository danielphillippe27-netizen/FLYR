import Foundation

/// Upgrade-only cleanup for the removed PLAUD integration. No SDK or provider calls.
enum RetiredRecordingCleanup {
    private static let identifier = (Bundle.main.bundleIdentifier ?? "com.wolfgrid") + ".plaud.audio.v1"

    static func run() {
        guard !UserDefaults.standard.bool(forKey: "upgrade.recording-cleanup.v1") else { return }
        cancelTransfers(identifier: identifier) {
            let manager = FileManager.default
            guard let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let folders = ["plaud-audio", "plaud-capture", "plaud-background-uploads", "plaud-applications",
                           "plaud-contact-preferences", "plaud-splits", "plaud-merges", "plaud-deletions"]
            var succeeded = true
            for folder in folders {
                let path = root.appendingPathComponent(folder, isDirectory: true)
                // Retry on subsequent launches if a locked file could not be removed.
                if manager.fileExists(atPath: path.path) {
                    do { try manager.removeItem(at: path) } catch { succeeded = false }
                }
            }
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.lowercased().hasPrefix("plaud.") {
                defaults.removeObject(forKey: key)
            }
            if succeeded { defaults.set(true, forKey: "upgrade.recording-cleanup.v1") }
        }
    }

    static func cancelTransfers(identifier incoming: String, completion: @escaping () -> Void) {
        guard incoming == identifier else { completion(); return }
        let session = URLSession(configuration: .background(withIdentifier: identifier))
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
            session.invalidateAndCancel()
            completion()
        }
    }
}
