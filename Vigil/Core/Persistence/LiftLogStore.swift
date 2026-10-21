import Foundation
import Observation
import SwiftData

/// Observable store for strength sessions, persisted in SwiftData as JSON payloads.
/// Records never leave this layer; callers work with `LiftSession` values.
@MainActor
@Observable
final class LiftLogStore {
    /// In-progress session (`end == nil`), at most one.
    private(set) var active: LiftSession?
    /// Finished sessions, newest first.
    private(set) var recent: [LiftSession] = []

    /// Strong reference: a `ModelContext` does not keep its container alive.
    @ObservationIgnored private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        reload()
    }

    @discardableResult
    func startSession(title: String, now: Date = .now) -> LiftSession {
        if let active { return active }
        let session = LiftSession(title: title, start: now)
        upsert(session)
        active = session
        return session
    }

    func updateActive(_ mutate: (inout LiftSession) -> Void) {
        guard var session = active else { return }
        mutate(&session)
        session.end = nil
        active = session
        upsert(session)
    }

    func finishActive(now: Date = .now) {
        guard var session = active else { return }
        active = nil
        if session.completedSetCount == 0 {
            remove(id: session.id)
            return
        }
        session.end = max(now, session.start)
        upsert(session)
        recent = sorted(recent.filter { $0.id != session.id } + [session])
    }

    func discardActive() {
        guard let session = active else { return }
        active = nil
        remove(id: session.id)
    }

    func session(id: UUID) -> LiftSession? {
        if active?.id == id { return active }
        return recent.first { $0.id == id }
    }

    /// Saves edits to a finished session.
    func update(_ session: LiftSession) {
        if active?.id == session.id {
            active = session
        } else if let index = recent.firstIndex(where: { $0.id == session.id }) {
            recent[index] = session
            recent = sorted(recent)
        } else {
            return
        }
        upsert(session)
    }

    func delete(id: UUID) {
        if active?.id == id { active = nil }
        recent.removeAll { $0.id == id }
        remove(id: id)
    }

    /// Most recent finished occurrence of an exercise (case-insensitive name match) that has completed sets.
    func lastPerformance(of exerciseName: String) -> LoggedExercise? {
        let key = Self.normalized(exerciseName)
        for session in recent {
            if let match = session.exercises.first(where: { Self.normalized($0.name) == key && !$0.completedSets.isEmpty }) {
                return match
            }
        }
        return nil
    }

    /// Names of exercises the user has logged, most recently used first (deduplicated, case-insensitive).
    var recentExerciseNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for session in recent {
            for exercise in session.exercises {
                let key = Self.normalized(exercise.name)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                names.append(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return names
    }

    func deleteAll() {
        active = nil
        recent = []
        do {
            try context.delete(model: LiftSessionRecord.self)
            try context.save()
        } catch {
            print("Vigil: failed to delete lift sessions: \(error)")
        }
    }

    // MARK: Private

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sorted(_ sessions: [LiftSession]) -> [LiftSession] {
        sessions.sorted { $0.start > $1.start }
    }

    private func reload() {
        let records: [LiftSessionRecord]
        do {
            records = try context.fetch(FetchDescriptor<LiftSessionRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)]))
        } catch {
            print("Vigil: failed to load lift sessions: \(error)")
            return
        }
        let decoder = JSONDecoder()
        var finished: [LiftSession] = []
        var open: [LiftSession] = []
        for record in records {
            guard let session = try? decoder.decode(LiftSession.self, from: record.payload) else { continue }
            if session.end == nil { open.append(session) } else { finished.append(session) }
        }
        // Defensive: keep only the newest in-progress session.
        active = open.first
        for stale in open.dropFirst() { remove(id: stale.id) }
        recent = sorted(finished)
    }

    private func upsert(_ session: LiftSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let id = session.id
        let existing = try? context.fetch(FetchDescriptor<LiftSessionRecord>(predicate: #Predicate { $0.id == id })).first
        if let existing {
            existing.start = session.start
            existing.end = session.end
            existing.updatedAt = .now
            existing.payload = data
        } else {
            context.insert(LiftSessionRecord(id: id, start: session.start, end: session.end, updatedAt: .now, payload: data))
        }
        save()
    }

    private func remove(id: UUID) {
        if let existing = try? context.fetch(FetchDescriptor<LiftSessionRecord>(predicate: #Predicate { $0.id == id })).first {
            context.delete(existing)
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Vigil: failed to save lift sessions: \(error)")
        }
    }
}
