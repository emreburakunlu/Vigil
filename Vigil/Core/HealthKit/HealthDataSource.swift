import Foundation

// CONTRACT — the read-only gateway to Apple Health. Owned by the orchestrator; implemented by
// `LiveHealthDataSource` (HealthKit agent) and `MockHealthDataSource` (mock-data agent).
//
// Rules:
//  - All methods are `async` and run off the main actor (the protocol is nonisolated).
//  - Returned values are plain Sendable structs in canonical metric units (see `HealthMetric`).
//  - Results are sorted ascending by date/start unless documented otherwise.
//  - "No data" is an empty array / nil, never an error. Errors are for real failures.
//  - Nothing is ever written to HealthKit.

/// Errors thrown by a `HealthDataSource`.
enum HealthDataError: Error, Equatable, Sendable {
    /// The method is not implemented yet (Phase 0 stubs).
    case notImplemented
    /// HealthKit is not available on this device.
    case healthDataUnavailable
    /// The requested object does not exist (e.g. unknown workout id).
    case notFound
    /// The device is locked and protected Health data cannot be read (background delivery).
    case protectedDataUnavailable
    /// Any other HealthKit error, with its description.
    case underlying(String)
}

/// A "new data available" signal from HealthKit observer queries / background delivery.
struct HealthDataUpdate: Sendable {
    /// Categories that changed.
    var categories: Set<HealthDataCategory>
    var receivedAt: Date
    /// Call once the update has been processed (summaries rebuilt). The live source forwards this
    /// to HealthKit's observer completion handler, so iOS keeps a background launch alive until the
    /// refresh finishes. Implementations must tolerate it never being called (time out on their own).
    var acknowledge: @Sendable () -> Void = {}
}

/// Read-only access to everything Vigil needs from Apple Health.
protocol HealthDataSource: Sendable {
    /// Whether Health data can exist on this device at all.
    var isHealthDataAvailable: Bool { get }

    // MARK: Authorization

    /// Current authorization status (see `HealthAuthorizationStatus` for what can be known).
    func authorizationStatus() async -> HealthAuthorizationStatus
    /// Presents the Health permission sheet for all read types. Returns when the sheet is dismissed.
    func requestAuthorization() async throws

    // MARK: Characteristics

    /// Date of birth, sex and latest body mass, for prefilling "About you".
    func characteristics() async throws -> UserCharacteristics

    // MARK: Sleep

    /// Sleep nights whose wake-up time falls inside `interval`, oldest first (primary nights and naps).
    func sleepNights(in interval: DateInterval) async throws -> [SleepNight]

    // MARK: Quantity metrics

    /// Raw samples of `metric` inside `interval`, oldest first.
    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample]
    /// One `DailyVitals` per day that has at least one vital, for days overlapping `interval`.
    /// Each value is the overnight/sleep-window value HealthKit/Apple Watch reports for that wake day.
    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals]

    // MARK: Activity

    /// One `DailyActivity` per day overlapping `interval` (days with no data may be omitted).
    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity]

    // MARK: Workouts

    /// Workouts starting inside `interval`, oldest first. `kinds == nil` returns all kinds.
    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout]
    /// A single workout by id, or nil.
    func workout(id: UUID) async throws -> Workout?
    /// Route, series and running-form data for a run. Throws `.notFound` for unknown ids.
    func runDetails(for workoutID: UUID) async throws -> RunDetails
    /// Heart-rate samples (bpm) inside `interval` — used for lift HR charts, zones and strain.
    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample]
    /// Only the GPS route of a run (cheap; for list thumbnails). Empty when the run has no route.
    func route(for workoutID: UUID) async throws -> [RouteLocation]
    /// Only the cumulative-distance timeline of a run (cheap; for personal-best detection).
    func cumulativeDistance(for workoutID: UUID) async throws -> [MetricSample]
    /// Same as `dailyVitals(in:)` but reuses already-fetched `nights` for the sleep windows,
    /// instead of fetching sleep again.
    func dailyVitals(in interval: DateInterval, nights: [SleepNight]) async throws -> [DailyVitals]

    // MARK: Updates

    /// Starts observer queries (and background delivery where entitled) and yields an event
    /// whenever any category changes. Each call returns an independent stream; cancelling the
    /// consuming task stops its observers.
    func updates() -> AsyncStream<HealthDataUpdate>
}

extension HealthDataSource {
    /// Default: derived from `runDetails`. The live source overrides this with a route-only query.
    func route(for workoutID: UUID) async throws -> [RouteLocation] {
        try await runDetails(for: workoutID).route
    }

    /// Default: derived from `runDetails`. The live source overrides this with a distance-only query.
    func cumulativeDistance(for workoutID: UUID) async throws -> [MetricSample] {
        try await runDetails(for: workoutID).cumulativeDistance
    }

    /// Default: ignores `nights`. The live source overrides this to avoid a second sleep query.
    func dailyVitals(in interval: DateInterval, nights: [SleepNight]) async throws -> [DailyVitals] {
        try await dailyVitals(in: interval)
    }

    /// Convenience: VO₂ max samples (mL/kg/min).
    func vo2MaxSamples(in interval: DateInterval) async throws -> [MetricSample] {
        try await samples(of: .vo2Max, in: interval)
    }

    /// Convenience: body mass samples (kg).
    func bodyMassSamples(in interval: DateInterval) async throws -> [MetricSample] {
        try await samples(of: .bodyMass, in: interval)
    }
}
