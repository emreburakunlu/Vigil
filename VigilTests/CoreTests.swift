import Foundation
import Testing
@testable import Vigil

@Suite("LocalDay")
struct LocalDayTests {
    let calendar = TestSupport.utc

    @Test func basics() {
        let day = LocalDay(TestSupport.referenceDate, calendar: calendar)
        #expect(day == LocalDay(year: 2026, month: 10, day: 19))
        #expect(day.key == 20261019)
        #expect(day.isoString == "2026-10-19")
        #expect(LocalDay(isoString: "2026-10-19") == day)
        #expect(LocalDay(isoString: "2026-13-01") == nil)
        #expect(day.adding(days: 13, calendar: calendar) == LocalDay(year: 2026, month: 11, day: 1))
        #expect(day.days(to: LocalDay(year: 2026, month: 10, day: 12), calendar: calendar) == -7)
        #expect(day.interval(in: calendar).duration == 86_400)
        #expect(LocalDay.range(from: day.adding(days: -6, calendar: calendar), through: day, calendar: calendar).count == 7)
    }
}

@Suite("DeepLink")
struct DeepLinkTests {
    @Test(arguments: [
        DeepLink.today, .recovery(nil), .recovery(LocalDay(year: 2026, month: 10, day: 19)), .strain(nil), .sleep,
        .sleepNight(LocalDay(year: 2026, month: 10, day: 14)), .train, .run(UUID()), .lift(UUID()), .progress, .profile,
    ])
    func roundTrip(link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func rejectsForeignURLs() {
        #expect(DeepLink(url: URL(string: "https://example.com/today")!) == nil)
        #expect(DeepLink(url: URL(string: "vigil://run/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "vigil://unknown")!) == nil)
    }
}

@Suite("LaunchConfiguration")
struct LaunchConfigurationTests {
    @Test func simulatorDefaultsToMock() {
        let config = LaunchConfiguration.resolve(arguments: [], environment: [:], isSimulator: true)
        #expect(config.dataMode == .mock(.standard))
        #expect(config.storage == .onDisk(name: LaunchConfiguration.mockStoreName))
    }

    @Test func deviceDefaultsToLive() {
        let config = LaunchConfiguration.resolve(arguments: [], environment: [:], isSimulator: false)
        #expect(config.dataMode == .live)
        #expect(config.storage == .onDisk(name: LaunchConfiguration.liveStoreName))
    }

    @Test func flags() {
        #expect(LaunchConfiguration.resolve(arguments: ["-VigilMockData", "-VigilMockScenario", "partialData"], environment: [:],
                                            isSimulator: false).dataMode == .mock(.partialData))
        #expect(LaunchConfiguration.resolve(arguments: ["-VigilLiveData"], environment: [:], isSimulator: true).dataMode == .live)
        let preview = LaunchConfiguration.resolve(arguments: [], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"], isSimulator: false)
        #expect(preview.isMock && preview.storage == .inMemory)
    }
}

@Suite("Engine")
struct EngineTests {
    let engine = DefaultScoreEngine(calendar: TestSupport.utc)

    @Test func zonesFromEstimatedMax() {
        let birth = TestSupport.utc.date(from: DateComponents(year: 2005, month: 3, day: 14))!
        var profile = UserProfile.default
        profile.dateOfBirth = birth
        let zones = engine.heartRateZones(profile: profile, settings: .default, observedMaxHeartRate: nil, on: TestSupport.referenceDate)
        #expect(zones.maxHeartRate == 193) // 208 − 0.7 × 21
        #expect(zones.zones.count == 5)
        #expect(zones.zones.last?.upperBound == 193)
        #expect(zip(zones.zones, zones.zones.dropFirst()).allSatisfy { $0.upperBound + 1 == $1.lowerBound })
        #expect(zones.zone(for: 60) == nil)
        #expect(zones.zone(for: 190) == 5)
    }

    @Test func customZones() {
        let zones = engine.heartRateZones(profile: .default, settings: HeartRateZoneSettings(usesCustomZones: true, customUpperBounds: [117, 137, 156, 176]),
                                          observedMaxHeartRate: nil, on: TestSupport.referenceDate)
        #expect(zones.source == .custom)
        #expect(zones.zones.map(\.lowerBound).dropFirst() == [118, 138, 157, 177])
    }

    @Test func constantLoadHasRatioOne() {
        let today = LocalDay(year: 2026, month: 10, day: 19)
        let loads = Dictionary(uniqueKeysWithValues: (0..<60).map { (today.adding(days: -$0, calendar: TestSupport.utc), 50.0) })
        let load = engine.trainingLoad(dailyLoads: loads, asOf: today, historyDays: 56)
        #expect(load.ratio == 1)
        #expect(load.risk == .productive)
        #expect(load.history.count == 56)
        #expect(load.history.last?.day == today)
    }

    @Test func baselineStatistics() throws {
        let baseline = try #require(DefaultScoreEngine.baseline(of: [58, 61, 64]))
        #expect(baseline.mean == 61)
        #expect(baseline.standardDeviation == 3)
        #expect(baseline.status(of: 68) == .noBaseline) // only 3 samples
    }
}

@Suite("SplitCalculator")
struct SplitCalculatorTests {
    @Test func metricSplitsWithPartial() {
        let start = TestSupport.referenceDate
        // 2.5 km at a steady 300 s/km, sampled every 10 s.
        let samples = stride(from: 0.0, through: 750, by: 10).map { MetricSample(date: start.addingTimeInterval($0), value: $0 / 300 * 1_000) }
        let splits = SplitCalculator.splits(details: RunDetails(workoutID: UUID(), cumulativeDistance: samples), units: .metric)
        #expect(splits.count == 3)
        #expect(splits.prefix(2).allSatisfy { abs($0.duration - 300) < 0.001 && !$0.isPartial })
        #expect(abs(splits[2].distanceMeters - 500) < 0.001)
        #expect(splits[2].isPartial)
        #expect(abs(splits[2].paceSecondsPerKilometer - 300) < 0.001)
    }

    @Test func imperialSplits() {
        let start = TestSupport.referenceDate
        let samples = stride(from: 0.0, through: 1_000, by: 5).map { MetricSample(date: start.addingTimeInterval($0), value: $0 * 4) }
        let splits = SplitCalculator.splits(details: RunDetails(workoutID: UUID(), cumulativeDistance: samples), units: .imperial)
        #expect(splits.count == 3) // 4000 m = 2 full miles + 781 m
        #expect(abs(splits[0].distanceMeters - UnitConversion.metersPerMile) < 0.001)
    }

    @Test func haversine() {
        // One degree of latitude ≈ 111.2 km.
        #expect(abs(SplitCalculator.haversineMeters(0, 0, 1, 0) - 111_195) < 100)
    }
}

@MainActor
@Suite("Repository with mock data")
struct RepositoryTests {
    func container(_ scenario: MockScenario) -> AppContainer {
        AppContainer(configuration: LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory, skipOnboarding: true, resetData: false),
                     calendar: TestSupport.utc, now: { TestSupport.referenceDate })
    }

    @Test func standardDayOverview() async throws {
        let container = container(.standard)
        let day = container.repository.today
        let overview = try await container.repository.dayOverview(for: day)
        #expect(overview.recovery != nil)
        #expect(overview.sleepScore != nil)
        #expect(overview.vitals.count == 5)
        #expect(overview.completeness == .complete)
        #expect(overview.workouts.contains { $0.workout.kind == .run })
        #expect(await container.repository.healthAccessState() == .connected)
    }

    @Test func partialDataScenario() async throws {
        let overview = try await container(.partialData).repository.dayOverview(for: LocalDay(TestSupport.referenceDate, calendar: TestSupport.utc))
        #expect(overview.completeness == .partial(missing: [.respiratoryRate, .wristTemperature]))
        #expect(overview.recovery?.isPartial == true)
    }

    @Test func deniedScenario() async {
        #expect(await container(.healthAccessDenied).repository.healthAccessState() == .likelyDenied)
        #expect(await container(.newUser).repository.healthAccessState() == .notDetermined)
    }

    @Test func runDetailHasSplits() async throws {
        let container = container(.standard)
        let interval = DateInterval(start: TestSupport.referenceDate.addingTimeInterval(-14 * 86_400), end: TestSupport.referenceDate)
        let run = try #require(try await container.repository.workouts(.run, in: interval).first)
        let detail = try await container.repository.runDetail(id: run.id)
        let distance = try #require(run.workout.distanceMeters)
        #expect(detail.splits.count == Int((distance / 1_000).rounded(.up)))
        #expect(!detail.details.route.isEmpty)
    }

    @Test func historyImportFillsCache() async throws {
        let container = container(.standard)
        var last: ImportProgress?
        for try await event in container.importer.importHistory(days: 14) { last = event }
        #expect(last?.phase == .finished)
        #expect(container.summaries.count() == 14)
        #expect(container.settings.settings.onboarding.historyImportedAt == TestSupport.referenceDate)
    }
}
