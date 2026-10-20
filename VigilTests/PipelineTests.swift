import Foundation
import SwiftData
import Synchronization
import Testing
import UserNotifications
@testable import Vigil

// Core pipeline: summary building, cache freshness, delete-local-data, background updates.

@MainActor
private func makeContainer(_ scenario: MockScenario = .standard, now: Date = TestSupport.referenceDate) -> AppContainer {
    AppContainer(configuration: LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory, skipOnboarding: true, resetData: false),
                 calendar: TestSupport.utc, now: { now })
}

private let utc = TestSupport.utc

/// Forwards to a mock source; can fail every query and/or replay a scripted update stream.
private struct ScriptedSource: HealthDataSource {
    let base: MockHealthDataSource
    var failing = false
    var stream: AsyncStream<HealthDataUpdate>?

    var isHealthDataAvailable: Bool { true }
    func authorizationStatus() async -> HealthAuthorizationStatus { .requested }
    func requestAuthorization() async throws {}
    private func check() throws { if failing { throw HealthDataError.protectedDataUnavailable } }
    func characteristics() async throws -> UserCharacteristics { try check(); return try await base.characteristics() }
    func sleepNights(in interval: DateInterval) async throws -> [SleepNight] { try check(); return try await base.sleepNights(in: interval) }
    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] {
        try check(); return try await base.samples(of: metric, in: interval)
    }
    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals] { try check(); return try await base.dailyVitals(in: interval) }
    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity] { try check(); return try await base.dailyActivity(in: interval) }
    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] {
        try check(); return try await base.workouts(in: interval, kinds: kinds)
    }
    func workout(id: UUID) async throws -> Workout? { try check(); return try await base.workout(id: id) }
    func runDetails(for workoutID: UUID) async throws -> RunDetails { try check(); return try await base.runDetails(for: workoutID) }
    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample] { try check(); return try await base.heartRateSamples(in: interval) }
    func updates() -> AsyncStream<HealthDataUpdate> { stream ?? AsyncStream { $0.finish() } }
}

private final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

@MainActor
private func repository(source: any HealthDataSource) throws -> VigilRepository {
    let container = try PersistenceController.makeContainer(.inMemory)
    let settings = SettingsStore(container: container)
    settings.update { $0.onboarding.completed = true }
    return VigilRepository(dataSource: source, engine: DefaultScoreEngine(calendar: utc), settings: settings,
                           summaries: DailySummaryStore(container: container), calendar: utc, now: { TestSupport.referenceDate })
}

private var mockSource: MockHealthDataSource {
    MockHealthDataSource(scenario: .standard, referenceDate: TestSupport.referenceDate, calendar: utc, latency: nil)
}

@MainActor
@Suite("Summary pipeline")
struct SummaryPipelineTests {
    /// Correctness #1 + F10: a one-day build equals the batch (import/refresh) build of the same day.
    @Test func oneDayBuildMatchesBatchBuild() async throws {
        let container = makeContainer()
        let repo = container.repository
        let today = repo.today
        let batch = try await repo.buildSummaries(from: today.adding(days: -29, calendar: utc), through: today)
        for offset in [0, 1, 5, 20] {
            let day = today.adding(days: -offset, calendar: utc)
            let expected = try #require(batch.first { $0.day == day })
            let single = try #require(try await repo.buildSummaries(from: day, through: day).first)
            #expect(single.recovery == expected.recovery, "recovery differs on \(day)")
            #expect(single.recovery?.suggestion == expected.recovery?.suggestion)
            #expect(single.strain == expected.strain)
            #expect(single == expected, "summary differs on \(day)")
        }
        // The single-day path that screens use agrees too (today is rebuilt after invalidation).
        repo.invalidateRecent()
        let viaSummary = try await repo.summary(for: today)
        #expect(viaSummary == batch.last)
    }

    @Test func importAndRefreshAgreeWithSingleDay() async throws {
        let container = makeContainer()
        for try await _ in container.importer.importHistory(days: 20) {}
        let repo = container.repository
        let imported = try #require(container.summaries.summary(for: repo.today))
        try await container.importer.refreshRecent(days: 3)
        let refreshed = try #require(container.summaries.summary(for: repo.today))
        let single = try #require(try await repo.buildSummaries(from: repo.today, through: repo.today).first)
        #expect(imported == refreshed)
        #expect(single == refreshed)
    }

    /// Correctness #2: a past day cached before it settled is rebuilt.
    @Test func partiallyComputedPastDayIsRebuilt() async throws {
        let container = makeContainer()
        let repo = container.repository
        let yesterday = repo.today.adding(days: -1, calendar: utc)
        var built = try #require(try await repo.buildSummaries(from: yesterday, through: yesterday).first)
        built.computedAt = yesterday.startDate(in: utc).addingTimeInterval(20 * 3600)   // 20:00 that day
        built.recovery = nil
        try container.summaries.upsert(built)
        repo.invalidateRecent()
        let fingerprint = await repo.currentSettingsFingerprint()
        let stamp = try #require(container.summaries.stamps(from: yesterday, through: yesterday).first)
        #expect(!repo.isUsable(stamp, fingerprint: fingerprint))
        let fresh = try await repo.summary(for: yesterday)
        #expect(fresh.computedAt == TestSupport.referenceDate)
        #expect(fresh.recovery != nil)
        // Settled days are reused.
        let older = repo.today.adding(days: -3, calendar: utc)
        _ = try await repo.summary(for: older)
        let olderStamp = try #require(container.summaries.stamps(from: older, through: older).first)
        repo.invalidateRecent()
        #expect(repo.isUsable(olderStamp, fingerprint: fingerprint))
    }

    @Test func todayIsReusedUntilInvalidated() async throws {
        let container = makeContainer()
        let repo = container.repository
        let first = try await repo.summary(for: repo.today)
        let stamp = try #require(container.summaries.stamps(from: repo.today, through: repo.today).first)
        let fingerprint = await repo.currentSettingsFingerprint()
        #expect(repo.isUsable(stamp, fingerprint: fingerprint))
        repo.invalidateRecent()
        #expect(!repo.isUsable(stamp, fingerprint: fingerprint))
        #expect(try await repo.summary(for: repo.today) == first)
    }

    /// Correctness #8: changing the sleep target or zones invalidates cached summaries.
    @Test func settingsFingerprintInvalidatesCache() async throws {
        let container = makeContainer()
        let repo = container.repository
        let day = repo.today.adding(days: -4, calendar: utc)
        let before = try await repo.summary(for: day)
        container.settings.update { $0.goals.sleepTarget = 6 * 3600 }
        let after = try await repo.summary(for: day)
        #expect(after.settingsFingerprint != before.settingsFingerprint)
        container.settings.update { $0.heartRateZones = HeartRateZoneSettings(usesCustomZones: true, customUpperBounds: [110, 130, 150, 170]) }
        let zoned = try await repo.summary(for: day)
        #expect(zoned.settingsFingerprint != after.settingsFingerprint)
        #expect(zoned.strain != nil)
    }

    @Test func fingerprintIsStable() {
        let zones = DefaultScoreEngine(calendar: utc).heartRateZones(profile: .default, settings: .default,
                                                                      observedMaxHeartRate: nil, on: TestSupport.referenceDate)
        #expect(SummarySettingsFingerprint.make(settings: .default, zones: zones) == SummarySettingsFingerprint.make(settings: .default, zones: zones))
    }

    /// Correctness #9 + F14: today's sleep history entry matches the night detail, and the trend fetches nights.
    @Test func sleepHistoryIncludesTodayFromSummary() async throws {
        let container = makeContainer()
        let repo = container.repository
        let start = repo.today.adding(days: -13, calendar: utc)
        let history = try await repo.sleepHistory(from: start, through: repo.today)
        let detail = try #require(try await repo.sleepNightDetail(endingOn: repo.today))
        #expect(history.last?.day == repo.today)
        #expect(history.last?.score == detail.score.value)
        let trend = try await repo.sleepTrend(from: start, through: repo.today)
        #expect(trend.summaries == history)
        #expect(trend.nights.allSatisfy { $0.isPrimary })
        #expect(!trend.nights.isEmpty)
    }

    @Test func ensuredSummariesReturnsEveryDay() async throws {
        let container = makeContainer()
        let repo = container.repository
        let start = repo.today.adding(days: -9, calendar: utc)
        let summaries = try await repo.ensuredSummaries(from: start, through: repo.today)
        #expect(summaries.map(\.day) == LocalDay.range(from: start, through: repo.today, calendar: utc))
        #expect(container.summaries.cachedKeys(from: start, through: repo.today, engineVersion: DailySummary.currentEngineVersion).count == 10)
        // Second call reads the cache (same values).
        #expect(try await repo.ensuredSummaries(from: start, through: repo.today) == summaries)
    }

    @Test func refreshCoversGapSinceLastSettledDay() async throws {
        let container = makeContainer()
        #expect(container.importer.recentDayCount() == 14)
        for try await _ in container.importer.importHistory(days: 20) {}
        #expect(container.importer.recentDayCount() == 2)
    }

    @Test func workoutsListUsesCachedStrain() async throws {
        let container = makeContainer()
        let repo = container.repository
        let interval = LocalDay.interval(from: repo.today.adding(days: -13, calendar: utc), through: repo.today, calendar: utc)
        let uncached = try await repo.workouts(.run, in: interval)
        #expect(!uncached.isEmpty)
        #expect(uncached.allSatisfy { $0.strain == nil })
        for try await _ in container.importer.importHistory(days: 14) {}
        let cached = try await repo.workouts(.run, in: interval)
        #expect(cached.allSatisfy { $0.strain != nil })
        #expect(cached.map(\.id) == uncached.map(\.id))
    }

    @Test func observedMaxHeartRateIsSharedByZones() async throws {
        let container = makeContainer()
        let repo = container.repository
        let observed = await repo.observedMaxHeartRate()
        #expect(observed != nil)
        #expect(repo.heartRateZones() == repo.heartRateZones(observedMaxHeartRate: observed))
    }
}

@MainActor
@Suite("Workout deduplication")
struct WorkoutDeduplicationTests {
    private func workout(_ source: DataSourceInfo, start: TimeInterval, minutes: Double, kind: WorkoutKind = .strength,
                         heartRate: Double? = nil) -> Workout {
        let begin = TestSupport.referenceDate.addingTimeInterval(start * 60)
        return Workout(id: UUID(), kind: kind, activityName: "Strength", title: nil, start: begin,
                       end: begin.addingTimeInterval(minutes * 60), duration: minutes * 60,
                       activeEnergyKilocalories: nil, totalEnergyKilocalories: nil, averageHeartRate: heartRate, maxHeartRate: heartRate,
                       distanceMeters: nil, elevationGainMeters: nil, elevationLossMeters: nil,
                       source: source, heartRateSource: nil, isIndoor: true, hasRoute: false)
    }

    @Test func overlappingLiftsFromDifferentSourcesCountOnce() {
        let hevy = workout(MockHealthDataSource.hevy, start: 0, minutes: 60)
        let watch = workout(MockHealthDataSource.workoutApp, start: 5, minutes: 50, heartRate: 120)
        let result = WorkoutDeduplication.deduplicated([hevy, watch])
        #expect(result == [watch])
    }

    @Test func keepsDistinctSessions() {
        let hevy = workout(MockHealthDataSource.hevy, start: 0, minutes: 60)
        let later = workout(MockHealthDataSource.workoutApp, start: 45, minutes: 60)    // 15 min overlap: 25 %
        let sameSource = workout(MockHealthDataSource.hevy, start: 10, minutes: 30)
        let run = workout(MockHealthDataSource.workoutApp, start: 0, minutes: 60, kind: .run)
        #expect(WorkoutDeduplication.deduplicated([hevy, later]).count == 2)
        #expect(WorkoutDeduplication.deduplicated([hevy, sameSource]).count == 2)
        #expect(WorkoutDeduplication.deduplicated([hevy, run]).count == 2)
    }

    @Test func prefersHeartRateThenLonger() {
        let withHR = workout(MockHealthDataSource.hevy, start: 0, minutes: 40, heartRate: 110)
        let longer = workout(MockHealthDataSource.workoutApp, start: 0, minutes: 60)
        #expect(WorkoutDeduplication.deduplicated([longer, withHR]) == [withHR])
        let a = workout(MockHealthDataSource.hevy, start: 0, minutes: 40)
        let b = workout(MockHealthDataSource.workoutApp, start: 0, minutes: 60)
        #expect(WorkoutDeduplication.deduplicated([a, b]) == [b])
    }

    @Test func summaryCountsDuplicateOnce() {
        let builder = SummaryBuilder(engine: DefaultScoreEngine(calendar: utc), calendar: utc)
        let hevy = workout(MockHealthDataSource.hevy, start: -180, minutes: 60, heartRate: 120)
        let watch = workout(MockHealthDataSource.workoutApp, start: -178, minutes: 58)
        let day = LocalDay(TestSupport.referenceDate, calendar: utc)
        let one = builder.summaries(for: [day], data: HealthDataBundle(workouts: [hevy]), settings: .default, now: TestSupport.referenceDate)
        let both = builder.summaries(for: [day], data: HealthDataBundle(workouts: [hevy, watch]), settings: .default, now: TestSupport.referenceDate)
        #expect(both.first?.strain?.workouts.count == 1)
        #expect(both.first?.strain == one.first?.strain)
    }
}

@MainActor
@Suite("Lifecycle")
struct LifecycleTests {
    /// Correctness #3: deleting local data stays deleted.
    @Test func deleteLocalDataClearsEverything() async throws {
        let container = makeContainer()
        for try await _ in container.importer.importHistory(days: 7) {}
        _ = await container.widgetSnapshots.refresh()
        #expect(container.summaries.count() == 7)
        #expect(container.widgetSnapshots.currentSnapshot() != nil)
        let version = container.dataVersion
        try await container.deleteAllLocalData()
        #expect(container.summaries.count() == 0)
        #expect(container.widgetSnapshots.currentSnapshot() == nil)
        #expect(!container.settings.settings.onboarding.completed)
        #expect(container.dataVersion > version)
        // Nothing writes anything back.
        container.settingsDidChange()
        await container.refreshIfStale(minimumInterval: 0)
        try await container.importer.refreshRecent()
        #expect(await container.widgetSnapshots.refresh() == nil)
        #expect(container.summaries.count() == 0)
        #expect(container.widgetSnapshots.currentSnapshot() == nil)
    }

    @Test func refreshBumpsDataVersion() async throws {
        let container = makeContainer()
        let version = container.dataVersion
        await container.refreshIfStale(minimumInterval: 0)
        #expect(container.dataVersion > version)
        let afterRefresh = container.dataVersion
        container.settingsDidChange()
        #expect(container.dataVersion > afterRefresh)
        #expect(container.currentDay == container.repository.today)
    }

    /// Background delivery: every update is acknowledged after its refresh, bursts are coalesced.
    @Test func healthUpdatesAreCoalescedAndAcknowledged() async throws {
        let (stream, continuation) = AsyncStream<HealthDataUpdate>.makeStream()
        let repo = try repository(source: ScriptedSource(base: mockSource, stream: stream))
        let widget = WidgetSnapshotService(repository: repo, store: WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "VigilTest-\(UUID().uuidString)")), reloadTimelines: {})
        let importer = HistoryImportService(repository: repo, widgetSnapshots: widget)
        importer.coalesceDelay = .milliseconds(50)
        importer.backgroundCoalesceDelay = .milliseconds(50)
        importer.isForeground = { true }
        var refreshes = 0
        importer.onDataChanged = { refreshes += 1 }
        let acks = Counter()
        let observing = Task { await importer.observeHealthUpdates() }
        for _ in 0..<3 {
            continuation.yield(HealthDataUpdate(categories: [.sleep], receivedAt: TestSupport.referenceDate, acknowledge: { acks.increment() }))
        }
        for _ in 0..<200 where acks.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        continuation.finish()
        await observing.value
        #expect(acks.count == 3)
        #expect(refreshes == 1)
        #expect(repo.summaries.count() >= 2)
    }

    /// False "likely denied": errors are not denial; characteristics count as data.
    @Test func accessStateTreatsErrorsAsConnected() async throws {
        let failing = try repository(source: ScriptedSource(base: mockSource, failing: true))
        #expect(await failing.healthAccessState() == .connected)
        let denied = try repository(source: ScriptedSource(base: MockHealthDataSource(scenario: .healthAccessDenied,
                                                                                     referenceDate: TestSupport.referenceDate,
                                                                                     calendar: utc, latency: nil)))
        #expect(await denied.healthAccessState() == .likelyDenied)
    }
}

@MainActor
@Suite("Notifications and widget freshness")
struct NotificationLifecycleTests {
    private func snapshot(sleep: TimeInterval?) -> WidgetSnapshot {
        var s = WidgetSnapshot.placeholder(now: TestSupport.referenceDate.addingTimeInterval(-5 * 3600), calendar: utc)
        s.sleepDuration = sleep
        return s
    }

    @Test func syncSkipsIdenticalPlans() async {
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let service = NotificationService(scheduler: scheduler, calendar: utc, now: { TestSupport.referenceDate })
        await service.sync(settings: .default, snapshot: nil)
        let added = scheduler.addCount
        #expect(added > 0)
        await service.sync(settings: .default, snapshot: nil)
        #expect(scheduler.addCount == added)
        await service.removeAll()
        #expect(scheduler.requests.isEmpty)
    }

    @Test func morningUsesRealValuesOnlyWithSleep() async {
        let scheduler = InMemoryNotificationScheduler(status: .authorized)
        let service = NotificationService(scheduler: scheduler, calendar: utc, now: { TestSupport.referenceDate.addingTimeInterval(-6 * 3600) })
        await service.sync(settings: .default, snapshot: snapshot(sleep: nil))
        let bodies = scheduler.requests.values.map(\.content.body)
        #expect(!bodies.isEmpty)
        #expect(bodies.allSatisfy { $0 == NotificationPlanner.genericMorningBody || $0.hasPrefix("Bedtime") })
        await service.sync(settings: .default, snapshot: snapshot(sleep: 7 * 3600))
        #expect(scheduler.requests.values.contains { $0.content.body.contains("Slept") })
    }

    /// Correctness #5: completing onboarding asks for permission when the morning summary is on.
    @Test func onboardingCompletionRequestsPermission() async {
        let scheduler = InMemoryNotificationScheduler(status: .notDetermined, grantsOnRequest: true)
        let container = makeContainer()
        let service = NotificationService(scheduler: scheduler, calendar: utc, now: { TestSupport.referenceDate })
        #expect(await service.requestAuthorizationIfNeeded())
        #expect(scheduler.authorizationRequests == 1)
        await container.requestNotificationPermissionIfEnabled()
        #expect(container.settings.settings.notifications.morningSummaryEnabled)
    }

    /// Correctness #7: yesterday's snapshot isn't shown today; the timeline flips at midnight.
    @Test func widgetFlipsAtMidnight() {
        let generated = utc.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 22))!
        let s = WidgetSnapshot.placeholder(now: generated, calendar: utc)
        #expect(WidgetSnapshot.displayState(snapshot: s, at: generated.addingTimeInterval(3600), calendar: utc) == .ready(s))
        #expect(WidgetSnapshot.displayState(snapshot: s, at: generated.addingTimeInterval(3 * 3600), calendar: utc) == .needsUpdate)
        let midnight = utc.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        #expect(WidgetSnapshot.nextDayStart(after: generated, calendar: utc) == midnight)
    }

    @Test func widgetRefreshSkipsUnchangedSnapshot() async throws {
        let container = makeContainer()
        var reloads = 0
        let store = WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: "VigilTest-\(UUID().uuidString)"))
        let service = WidgetSnapshotService(repository: container.repository, store: store, reloadTimelines: { reloads += 1 })
        #expect(await service.refresh() != nil)
        #expect(await service.refresh() != nil)
        #expect(reloads == 1)
    }
}

@MainActor
@Suite("Persistence caches")
struct PersistenceCacheTests {
    @Test func personalBestCachePersists() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PB-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        let pb = PersonalBest(category: .fiveKilometers, duration: 1_500, distanceMeters: 5_000, date: TestSupport.referenceDate, workoutID: id, isNew: false)
        let cache = PersonalBestCache(fileURL: url)
        cache.store([id: [pb]], markWarm: true)
        let reloaded = PersonalBestCache(fileURL: url)
        #expect(reloaded.efforts(for: id) == [pb])
        #expect(reloaded.warm)
        reloaded.reset()
        #expect(PersonalBestCache(fileURL: url).efforts(for: id) == nil)
        #expect(PersonalBestCache(fileURL: url, engineVersion: 999).efforts(for: id) == nil)
    }

    @Test func runDetailWaitsForWarmCache() async throws {
        let container = makeContainer()
        let repo = container.repository
        let interval = LocalDay.interval(from: repo.today.adding(days: -13, calendar: utc), through: repo.today, calendar: utc)
        let run = try #require(try await repo.workouts(.run, in: interval).first)
        #expect(try await repo.runDetail(id: run.id).personalBests.isEmpty)
        _ = try await repo.personalBests()
        #expect(repo.personalBestCache.warm)
        _ = try await repo.runDetail(id: run.id)
    }

    /// V1 stores (no fingerprint column) open with the V2 schema.
    @Test func migratesV1Store() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "VigilMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Vigil.store")
        do {
            let schema = Schema(versionedSchema: VigilSchemaV1.self)
            let v1 = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(v1)
            context.insert(VigilSchemaV1.DailySummaryRecord(dayKey: 20261019, computedAt: TestSupport.referenceDate, engineVersion: 2,
                                                            recoveryPercent: 70, sleepScore: 80, strain: 40, payload: Data()))
            try context.save()
        }
        let v2 = try PersistenceController.makeContainer(url: url)
        let records = try ModelContext(v2).fetch(FetchDescriptor<DailySummaryRecord>())
        #expect(records.count == 1)
        #expect(records.first?.settingsFingerprint == nil)
        #expect(records.first?.recoveryPercent == 70)
    }
}
