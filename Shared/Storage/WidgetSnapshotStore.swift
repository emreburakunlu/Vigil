import Foundation

/// Reads and writes `WidgetSnapshot` as JSON inside the App Group container.
///
/// The app is the only writer; the widget only reads. Writes are atomic so the widget never
/// observes a half-written file.
struct WidgetSnapshotStore: Sendable {
    /// File name inside the container directory.
    static let fileName = "widget-snapshot.json"

    /// Directory holding the snapshot file.
    let directory: URL

    /// Store rooted in the App Group container (or a local fallback when unavailable).
    init(directory: URL = AppGroup.containerURLOrFallback) {
        self.directory = directory
    }

    var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    /// Loads the latest snapshot, or `nil` if none exists, it is unreadable, or its schema is newer.
    func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    /// Atomically persists the snapshot.
    func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Removes the snapshot (used by "Delete local data").
    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
