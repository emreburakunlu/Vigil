import Foundation
import HealthKit

/// HealthKit-backed `HealthDataSource`. Owner: HealthKit agent.
///
/// Phase 0: every method is a safe stub (empty data or `.notImplemented`); nothing traps.
///
/// Implementation notes for the HealthKit agent:
///  - Read types: sleepAnalysis, heartRate, heartRateVariabilitySDNN, restingHeartRate,
///    respiratoryRate, appleSleepingWristTemperature, oxygenSaturation, workoutType,
///    workoutRoute (series), runningSpeed, runningPower, runningStrideLength,
///    runningGroundContactTime, runningVerticalOscillation, distanceWalkingRunning, stepCount,
///    activeEnergyBurned, basalEnergyBurned, appleExerciseTime, appleStandTime/appleStandHour,
///    activitySummaryType, vo2Max, bodyMass, dateOfBirth, biologicalSex. Share types: none.
///  - Background delivery: `enableBackgroundDelivery(for:frequency:)` per observed type requires
///    the `com.apple.developer.healthkit.background-delivery` entitlement (present). No
///    `UIBackgroundModes` entry is needed for HealthKit background delivery. Call the observer
///    completion handler promptly. Data is unreadable while the device is locked.
///  - Prefer Apple Watch sources when merging overlapping sleep samples.
struct LiveHealthDataSource: HealthDataSource {
    /// Shared store; `HKHealthStore` is thread-safe and Sendable.
    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus() async -> HealthAuthorizationStatus {
        isHealthDataAvailable ? .notDetermined : .unavailable
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthDataError.healthDataUnavailable }
        throw HealthDataError.notImplemented
    }

    func characteristics() async throws -> UserCharacteristics { UserCharacteristics() }

    func sleepNights(in interval: DateInterval) async throws -> [SleepNight] { [] }

    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] { [] }

    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals] { [] }

    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity] { [] }

    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] { [] }

    func workout(id: UUID) async throws -> Workout? { nil }

    func runDetails(for workoutID: UUID) async throws -> RunDetails { throw HealthDataError.notFound }

    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample] { [] }

    func updates() -> AsyncStream<HealthDataUpdate> {
        AsyncStream { continuation in continuation.finish() }
    }
}
