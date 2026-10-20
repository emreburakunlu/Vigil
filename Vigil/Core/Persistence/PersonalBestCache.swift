import Foundation

/// Best efforts found inside each run, persisted so a year of runs is scanned only once (not once per launch).
///
/// Stored as JSON in Application Support (`PersonalBests.json`): `{engineVersion, isWarm, efforts}`.
/// Runs never change once recorded, so entries are never invalidated except by an engine version bump
/// or "Delete local data". `isWarm` records that a full scan of the last year has completed at least once;
/// until then the run detail screen doesn't show "personal bests set here" (that would need a full scan).
/// A nil `fileURL` keeps everything in memory (tests, previews).
@MainActor
final class PersonalBestCache {
    private struct File: Codable {
        var engineVersion: Int
        var isWarm: Bool?
        var efforts: [String: [PersonalBest]]
    }

    let fileURL: URL?
    private let engineVersion: Int
    private(set) var efforts: [UUID: [PersonalBest]] = [:]
    /// A full scan of the last year has completed.
    private(set) var isWarm = false
    private var loaded = false

    init(fileURL: URL?, engineVersion: Int = DailySummary.currentEngineVersion) {
        self.fileURL = fileURL
        self.engineVersion = engineVersion
    }

    /// `Application Support/<fileName>`, creating the directory when needed.
    static func defaultURL(fileName: String = "PersonalBests.json") -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }

    func efforts(for workoutID: UUID) -> [PersonalBest]? {
        loadIfNeeded()
        return efforts[workoutID]
    }

    var warm: Bool {
        loadIfNeeded()
        return isWarm
    }

    /// Records efforts for several runs; `markWarm` after a complete scan. Saves once.
    func store(_ new: [UUID: [PersonalBest]], markWarm: Bool = false) {
        loadIfNeeded()
        guard !new.isEmpty || (markWarm && !isWarm) else { return }
        efforts.merge(new) { _, b in b }
        if markWarm { isWarm = true }
        save()
    }

    /// Drops everything, including the file ("Delete local data").
    func reset() {
        efforts = [:]
        isWarm = false
        loaded = true
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.engineVersion == engineVersion else { return }
        efforts = Dictionary(file.efforts.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
                             uniquingKeysWith: { a, _ in a })
        isWarm = file.isWarm ?? false
    }

    private func save() {
        guard let fileURL else { return }
        let file = File(engineVersion: engineVersion, isWarm: isWarm,
                        efforts: Dictionary(efforts.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { a, _ in a }))
        do {
            try JSONEncoder().encode(file).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Vigil: failed to save personal bests: \(error)")
        }
    }
}
