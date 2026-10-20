import Foundation
import SwiftData

/// Cache of computed `DailySummary` values keyed by `LocalDay`.
///
/// Holds a strong reference to its `ModelContainer` (a `ModelContext` alone does not keep the
/// container alive) and works on the container's main context.
///
/// Decoded summaries are memoized in memory (keyed by day and `computedAt`), so repeated range reads
/// only decode payloads that changed. Freshness checks use `stamps(from:through:)`, which fetches only
/// the small denormalized columns, never the JSON payload.
@MainActor
final class DailySummaryStore {
    /// The cheap, payload-free description of one cached day.
    struct Stamp: Hashable, Sendable {
        var day: LocalDay
        var computedAt: Date
        var engineVersion: Int
        var settingsFingerprint: String?
    }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Decoded payloads by day key; valid while `computedAt` matches the record.
    private var memo: [Int: DailySummary] = [:]

    init(container: ModelContainer) {
        self.container = container
    }

    /// Summary for a day, or nil if not cached / undecodable.
    func summary(for day: LocalDay) -> DailySummary? {
        let key = day.key
        var descriptor = FetchDescriptor<DailySummaryRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap(decode)
    }

    /// Summaries for `start...end`, oldest first.
    func summaries(from start: LocalDay, through end: LocalDay) -> [DailySummary] {
        let lower = start.key, upper = end.key
        guard lower <= upper else { return [] }
        let stamps = stamps(lower: lower, upper: upper)
        let changed = stamps.filter { memo[$0.day.key]?.computedAt != $0.computedAt }.map(\.day.key)
        if !changed.isEmpty {
            let keys = changed
            let descriptor = FetchDescriptor<DailySummaryRecord>(predicate: #Predicate { keys.contains($0.dayKey) })
            for record in (try? context.fetch(descriptor)) ?? [] { _ = decode(record) }
        }
        return stamps.compactMap { stamp in
            memo[stamp.day.key].flatMap { $0.computedAt == stamp.computedAt ? $0 : nil }
        }
    }

    /// Freshness stamps for `start...end`, oldest first (no payload decoding).
    func stamps(from start: LocalDay, through end: LocalDay) -> [Stamp] {
        stamps(lower: start.key, upper: end.key)
    }

    /// Keys (`LocalDay.key`) of the days in `start...end` cached with `engineVersion`.
    func cachedKeys(from start: LocalDay, through end: LocalDay, engineVersion: Int) -> Set<Int> {
        Set(stamps(from: start, through: end).filter { $0.engineVersion == engineVersion }.map(\.day.key))
    }

    /// Daily strain per cached day in `start...end`.
    func strains(from start: LocalDay, through end: LocalDay) -> [LocalDay: DailyStrain] {
        Dictionary(summaries(from: start, through: end).compactMap { s in s.strain.map { (s.day, $0) } },
                   uniquingKeysWith: { _, b in b })
    }

    /// Most recent cached day.
    func latest() -> DailySummary? {
        var descriptor = FetchDescriptor<DailySummaryRecord>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first.flatMap(decode)
    }

    /// Stamp of the most recently computed summary (any day), or nil when the cache is empty.
    func latestComputed() -> Stamp? {
        var descriptor = FetchDescriptor<DailySummaryRecord>(sortBy: [SortDescriptor(\.computedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.dayKey, \.computedAt, \.engineVersion, \.settingsFingerprint]
        return (try? context.fetch(descriptor))?.first.map(Self.stamp)
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
                record.settingsFingerprint = summary.settingsFingerprint
                record.recoveryPercent = summary.recovery?.value
                record.sleepScore = summary.sleepScore?.value
                record.strain = summary.strain?.value
                record.payload = payload
            } else {
                let record = DailySummaryRecord(dayKey: summary.day.key, computedAt: summary.computedAt,
                                                engineVersion: summary.engineVersion,
                                                settingsFingerprint: summary.settingsFingerprint,
                                                recoveryPercent: summary.recovery?.value,
                                                sleepScore: summary.sleepScore?.value, strain: summary.strain?.value,
                                                payload: payload)
                context.insert(record)
                byKey[summary.day.key] = record
            }
        }
        try context.save()
        for summary in summaries { memo[summary.day.key] = summary }
    }

    func upsert(_ summary: DailySummary) throws {
        try upsert([summary])
    }

    /// Deletes every cached summary.
    func deleteAll() throws {
        memo = [:]
        try context.delete(model: DailySummaryRecord.self)
        try context.save()
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private func stamps(lower: Int, upper: Int) -> [Stamp] {
        guard lower <= upper else { return [] }
        var descriptor = FetchDescriptor<DailySummaryRecord>(
            predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        descriptor.propertiesToFetch = [\.dayKey, \.computedAt, \.engineVersion, \.settingsFingerprint]
        return ((try? context.fetch(descriptor)) ?? []).map(Self.stamp)
    }

    private static func stamp(_ record: DailySummaryRecord) -> Stamp {
        let key = record.dayKey
        return Stamp(day: LocalDay(year: key / 10_000, month: key / 100 % 100, day: key % 100),
                     computedAt: record.computedAt, engineVersion: record.engineVersion,
                     settingsFingerprint: record.settingsFingerprint)
    }

    private func decode(_ record: DailySummaryRecord) -> DailySummary? {
        if let memoized = memo[record.dayKey], memoized.computedAt == record.computedAt { return memoized }
        guard let summary = try? Self.decoder.decode(DailySummary.self, from: record.payload) else { return nil }
        memo[record.dayKey] = summary
        return summary
    }
}
