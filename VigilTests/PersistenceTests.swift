import Foundation
import SwiftData
import Testing
@testable import Vigil

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    @Test func settingsDefaultsOnFirstLaunch() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = SettingsStore(container: container)
        #expect(store.settings == .default)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SettingsRecord>()) == 1)
    }

    @Test func settingsRoundTripThroughSwiftData() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = SettingsStore(container: container)
        let birth = TestSupport.utc.date(from: DateComponents(year: 2005, month: 3, day: 14))!
        store.update {
            $0.units = .imperial
            $0.appearance = .dark
            $0.profile.dateOfBirth = birth
            $0.profile.sex = .male
            $0.profile.bodyMassKilograms = 78.4
            $0.profile.estimatesMaxHeartRate = false
            $0.profile.manualMaxHeartRate = 198
            $0.goals.sleepTarget = 7.5 * 3600
            $0.goals.weeklyRunDistanceMeters = 30_000
            $0.goals.weeklyLiftSessions = 4
            $0.heartRateZones = HeartRateZoneSettings(usesCustomZones: true, customUpperBounds: [117, 137, 156, 176])
            $0.notifications.bedtimeReminderEnabled = true
            $0.notifications.bedtimeReminderMinutes = 22 * 60
            $0.onboarding.completed = true
        }
        let expected = store.settings

        // A fresh context on the same container reads the persisted row.
        let fetched = try ModelContext(container).fetch(FetchDescriptor<SettingsRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.value == expected)
        let reloaded = SettingsStore(container: container)
        #expect(reloaded.settings == expected)
        #expect(reloaded.settings.heartRateZones.customUpperBounds == [117, 137, 156, 176])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SettingsRecord>()) == 1)
    }

    @Test func bindingWritesThrough() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = SettingsStore(container: container)
        store.binding(\.units).wrappedValue = .imperial
        #expect(store.settings.units == .imperial)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SettingsRecord>()).first?.unitsRaw == UnitSystem.imperial.rawValue)
    }

    @Test func dailySummaryUpsertQueryAndDelete() throws {
        let container = try PersistenceController.makeContainer(.inMemory)
        let store = DailySummaryStore(container: container)
        let day = LocalDay(year: 2026, month: 10, day: 19)
        let recovery = RecoveryScore(value: 78, band: .green, factors: [], suggestion: .push, message: "Good day.",
                                     suggestedStrain: 55...75, signalsUsed: 5, signalsTotal: 5)
        try store.upsert([
            DailySummary(day: day.adding(days: -1), computedAt: TestSupport.referenceDate),
            DailySummary(day: day, computedAt: TestSupport.referenceDate, recovery: recovery),
        ])
        #expect(store.count() == 2)
        #expect(store.summary(for: day)?.recovery?.value == 78)

        // Upsert replaces, never duplicates.
        var updated = try #require(store.summary(for: day))
        updated.recovery?.value = 64
        try store.upsert(updated)
        #expect(store.count() == 2)
        #expect(store.summary(for: day)?.recovery?.value == 64)

        #expect(store.summaries(from: day.adding(days: -5), through: day).map(\.day) == [day.adding(days: -1), day])
        #expect(store.latest()?.day == day)

        try store.deleteAll()
        #expect(store.count() == 0)
        #expect(store.summary(for: day) == nil)
    }

    @Test func widgetSnapshotRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "VigilTests-\(UUID().uuidString)")
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.load() == nil)
        let snapshot = WidgetSnapshot.placeholder(now: TestSupport.referenceDate, calendar: TestSupport.utc)
        try store.save(snapshot)
        let loaded = try #require(store.load())
        #expect(loaded.recoveryPercent == 78)
        #expect(loaded.weeklyRunDistanceMeters == 18_400)
        #expect(loaded.generatedAt == snapshot.generatedAt)
        try store.delete()
        #expect(store.load() == nil)
    }
}
