import Foundation
import SwiftData

/// Cache of computed `DailySummary` values keyed by `LocalDay`.
///
/// Holds a strong reference to its `ModelContainer` (a `ModelContext` alone does not keep the
/// container alive) and works on the container's main context.
@MainActor
final class DailySummaryStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Summary for a day, or nil if not cached / undecodable.
    func summary(for day: LocalDay) -> DailySummary? {
        let key = day.key
        var descriptor = FetchDescriptor<DailySummaryRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap(Self.decode)
    }

    /// Summaries for `start...end`, oldest first.
    func summaries(from start: LocalDay, through end: LocalDay) -> [DailySummary] {
        let lower = start.key, upper = end.key
        let descriptor = FetchDescriptor<DailySummaryRecord>(
            predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return ((try? context.fetch(descriptor)) ?? []).compactMap(Self.decode)
    }

    /// Most recent cached day.
    func latest() -> DailySummary? {
        var descriptor = FetchDescriptor<DailySummaryRecord>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap(Self.decode)
    }

    /// Number of cached days.
    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<DailySummaryRecord>())) ?? 0
    }

    /// Inserts or replaces summaries (one save for the batch).
    func upsert(_ summaries: [DailySummary]) throws {
        guard !summaries.isEmpty else { return }
        let keys = summaries.map(\.day.key)
        let existing = try context.fetch(FetchDescriptor<DailySummaryRecord>(predicate: #Predicate { keys.contains($0.dayKey) }))
        var byKey = Dictionary(existing.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        for summary in summaries {
            let payload = try Self.encoder.encode(summary)
            if let record = byKey[summary.day.key] {
                record.computedAt = summary.computedAt
                record.engineVersion = summary.engineVersion
                record.recoveryPercent = summary.recovery?.value
                record.sleepScore = summary.sleepScore?.value
                record.strain = summary.strain?.value
                record.payload = payload
            } else {
                let record = DailySummaryRecord(dayKey: summary.day.key, computedAt: summary.computedAt,
                                                engineVersion: summary.engineVersion, recoveryPercent: summary.recovery?.value,
                                                sleepScore: summary.sleepScore?.value, strain: summary.strain?.value, payload: payload)
                context.insert(record)
                byKey[summary.day.key] = record
            }
        }
        try context.save()
    }

    func upsert(_ summary: DailySummary) throws {
        try upsert([summary])
    }

    /// Deletes every cached summary.
    func deleteAll() throws {
        try context.delete(model: DailySummaryRecord.self)
        try context.save()
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func decode(_ record: DailySummaryRecord) -> DailySummary? {
        try? decoder.decode(DailySummary.self, from: record.payload)
    }
}
