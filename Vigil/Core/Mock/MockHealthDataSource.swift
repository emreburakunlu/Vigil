import Foundation
import Synchronization

/// Shared mutable authorization state so `newUser` flips to `.requested` once the sheet "was shown".
final class MockAuthorizationBox: Sendable {
    private let state: Mutex<HealthAuthorizationStatus>

    init(_ initial: HealthAuthorizationStatus) { state = Mutex(initial) }

    var status: HealthAuthorizationStatus { state.withLock { $0 } }
    func markRequested() { state.withLock { $0 = .requested } }
}

/// Deterministic in-memory `HealthDataSource` for the simulator, previews and tests.
///
/// The athlete: a 21-year-old, ~75 kg, lifting Push / Pull / Legs (logged in Hevy) and running three
/// times a week, recorded on an Apple Watch. Everything is a pure function of `(seed, day)`: the same
/// day always yields the same values, repeated calls agree, and nothing after `referenceDate` exists.
/// See `MockScenario` for the situations that can be simulated and `Docs/ARCHITECTURE.md` for flags.
///
/// Launch with `-VigilMockLatency [maxMilliseconds]` (default 150) to add a random delay to every call,
/// which exercises loading states. Latency is never applied under tests or previews.
struct MockHealthDataSource: HealthDataSource {
    let scenario: MockScenario
    /// "Now" for the mock. Defaults to the real current time so the simulator always looks fresh.
    let referenceDate: Date
    let calendar: Calendar
    /// How far back data exists (ignored by `.newUser`, which has 3 days).
    let historyDays: Int
    /// Changes every generated value; same seed → same data.
    let seed: UInt64
    /// Random per-call delay in milliseconds, nil = instant.
    let latency: ClosedRange<Int>?

    let today: LocalDay
    let todayDN: Int
    let firstDN: Int
    let authorization: MockAuthorizationBox

    init(scenario: MockScenario = .standard, referenceDate: Date = .now, calendar: Calendar = .current,
         historyDays: Int = 400, seed: UInt64 = 2026, latency: ClosedRange<Int>? = MockHealthDataSource.launchLatency) {
        self.scenario = scenario
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.historyDays = historyDays
        self.seed = seed
        self.latency = latency
        let today = LocalDay(referenceDate, calendar: calendar)
        self.today = today
        self.todayDN = today.mockDayNumber
        self.firstDN = today.mockDayNumber - (scenario == .newUser ? 2 : historyDays)
        self.authorization = MockAuthorizationBox(scenario == .newUser ? .notDetermined : .requested)
    }

    static let watch = DataSourceInfo(name: "Apple Watch", bundleIdentifier: "com.apple.health", deviceName: "Apple Watch Series 12")
    static let workoutApp = DataSourceInfo(name: "Workout", bundleIdentifier: "com.apple.workout", deviceName: "Apple Watch Series 12")
    static let hevy = DataSourceInfo(name: "Hevy", bundleIdentifier: "com.hevyapp.hevy", deviceName: nil)

    /// `-VigilMockLatency [ms]` on the command line; always nil under tests and previews.
    static var launchLatency: ClosedRange<Int>? {
        let info = ProcessInfo.processInfo
        if info.environment["XCTestConfigurationFilePath"] != nil || info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        guard let index = info.arguments.firstIndex(of: "-VigilMockLatency") else { return nil }
        let next = info.arguments.indices.contains(index + 1) ? Int(info.arguments[index + 1]) : nil
        return 0...max(0, next ?? 150)
    }

    var noise: MockNoise { MockNoise(seed: seed) }
    var firstDay: LocalDay { LocalDay(mockDayNumber: firstDN) }
    var hasData: Bool { ![.healthAccessDenied, .empty].contains(scenario) }

    func pause() async throws {
        guard let latency else { return }
        try await Task.sleep(for: .milliseconds(Int.random(in: latency)))
    }

    // MARK: Authorization

    var isHealthDataAvailable: Bool { true }

    func authorizationStatus() async -> HealthAuthorizationStatus { authorization.status }

    func requestAuthorization() async throws {
        try await pause()
        authorization.markRequested()
    }

    func characteristics() async throws -> UserCharacteristics {
        try await pause()
        guard hasData else { return UserCharacteristics() }
        let birth = DateComponents(year: calendar.component(.year, from: referenceDate) - 21, month: 3, day: 14)
        let mass = bodyMassSamplesSync(in: DateInterval(start: referenceDate.addingTimeInterval(-60 * 86_400), end: referenceDate)).last
        return UserCharacteristics(dateOfBirth: birth, biologicalSex: .male, latestBodyMass: mass)
    }

    // MARK: Sleep

    func sleepNights(in interval: DateInterval) async throws -> [SleepNight] {
        try await pause()
        guard hasData else { return [] }
        return dayNumbers(overlapping: interval).flatMap { nights(for: LocalDay(mockDayNumber: $0)) }
            .filter { interval.contains($0.sleepEnd) }
    }

    // MARK: Metrics

    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] {
        try await pause()
        guard hasData else { return [] }
        switch metric {
        case .heartRate:
            return heartRateSamplesSync(in: interval)
        case .vo2Max:
            return vo2MaxSamplesSync(in: interval)
        case .bodyMass:
            return bodyMassSamplesSync(in: interval)
        default:
            return dayNumbers(overlapping: interval).compactMap { dn -> MetricSample? in
                let day = LocalDay(mockDayNumber: dn)
                guard let value = vitals(for: day)?[metric] else { return nil }
                return MetricSample(date: vitalsDate(day), value: value, sourceName: Self.watch.deviceName)
            }.filter { interval.contains($0.date) }
        }
    }

    func vo2MaxSamplesSync(in interval: DateInterval) -> [MetricSample] {
        guard hasData, let range = dayRange(overlapping: interval) else { return [] }
        return vo2MaxSamples(dn: range, in: interval)
    }

    func bodyMassSamplesSync(in interval: DateInterval) -> [MetricSample] {
        guard hasData, let range = dayRange(overlapping: interval) else { return [] }
        return bodyMassSamples(dn: range, in: interval)
    }

    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals] {
        try await pause()
        guard hasData else { return [] }
        return dayNumbers(overlapping: interval).compactMap { vitals(for: LocalDay(mockDayNumber: $0)) }
    }

    // MARK: Activity

    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity] {
        try await pause()
        guard hasData else { return [] }
        return dayNumbers(overlapping: interval).map { dailyActivityValue(for: LocalDay(mockDayNumber: $0)) }
    }

    // MARK: Workouts

    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] {
        try await pause()
        return workoutsSync(in: interval, kinds: kinds)
    }

    func workoutsSync(in interval: DateInterval, kinds: Set<WorkoutKind>?) -> [Workout] {
        guard hasData else { return [] }
        return dayNumbers(overlapping: interval)
            .flatMap { workouts(on: LocalDay(mockDayNumber: $0)) }
            .filter { interval.contains($0.start) && (kinds?.contains($0.kind) ?? true) }
    }

    func workout(id: UUID) async throws -> Workout? {
        try await pause()
        guard hasData, let day = Self.day(fromWorkoutID: id) else { return nil }
        return workouts(on: day).first { $0.id == id }
    }

    func runDetails(for workoutID: UUID) async throws -> RunDetails {
        try await pause()
        guard hasData, let day = Self.day(fromWorkoutID: workoutID),
              let run = workouts(on: day).first(where: { $0.id == workoutID }), run.kind == .run else {
            throw HealthDataError.notFound
        }
        return buildRunDetails(for: run, day: day)
    }

    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample] {
        try await pause()
        return heartRateSamplesSync(in: interval)
    }

    func updates() -> AsyncStream<HealthDataUpdate> {
        AsyncStream { continuation in continuation.finish() }
    }

    // MARK: Helpers

    /// Day numbers of the days overlapping `interval` that can hold data (`firstDN … today`).
    func dayRange(overlapping interval: DateInterval) -> ClosedRange<Int>? {
        guard interval.end > interval.start else { return nil }
        let lo = max(LocalDay(interval.start, calendar: calendar).mockDayNumber, firstDN)
        let hi = min(LocalDay(interval.end.addingTimeInterval(-1), calendar: calendar).mockDayNumber, todayDN)
        return lo <= hi ? lo...hi : nil
    }

    func dayNumbers(overlapping interval: DateInterval) -> [Int] {
        guard let range = dayRange(overlapping: interval) else { return [] }
        return Array(range)
    }
}
