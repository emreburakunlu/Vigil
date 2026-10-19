import Foundation

/// Vigil's coarse workout classification.
enum WorkoutKind: String, CaseIterable, Codable, Sendable {
    /// Running (outdoor or indoor/treadmill).
    case run
    /// Strength: traditional/functional strength training, core training, and similar.
    case strength
    /// Anything else (walks, cycling, HIIT, …): counts toward strain, not Train lists.
    case other
}

/// A workout read from HealthKit (any app that saves to Health — Apple Workout, Hevy, Strava, …).
struct Workout: Identifiable, Hashable, Codable, Sendable {
    /// `HKWorkout.uuid`.
    var id: UUID
    var kind: WorkoutKind
    /// Localized activity type name, e.g. "Outdoor Run", "Traditional Strength Training".
    var activityName: String
    /// User/app-provided title when available (e.g. "Upper Body" from Hevy metadata).
    var title: String?
    var start: Date
    var end: Date
    /// Active duration in seconds (excludes pauses; `HKWorkout.duration`).
    var duration: TimeInterval
    /// Active energy, kcal.
    var activeEnergyKilocalories: Double?
    /// Active + basal energy, kcal.
    var totalEnergyKilocalories: Double?
    /// Average / max heart rate during the workout, bpm.
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    /// Total distance, metres (runs).
    var distanceMeters: Double?
    /// Elevation gained / lost, metres (from metadata or route).
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    /// The app that saved the workout.
    var source: DataSourceInfo
    /// Device that measured heart rate, when different from `source` ("Heart rate from Apple Watch").
    var heartRateSource: DataSourceInfo?
    /// Indoor (treadmill / gym) vs. outdoor.
    var isIndoor: Bool
    /// Whether an `HKWorkoutRoute` exists (route map available).
    var hasRoute: Bool

    /// Title shown in lists: the app title if present, otherwise the activity name.
    var displayName: String { title ?? activityName }

    /// Average pace, seconds per kilometre (runs with distance only).
    var averagePaceSecondsPerKilometer: Double? {
        guard let distanceMeters, distanceMeters > 0, duration > 0 else { return nil }
        return duration / (distanceMeters / 1_000)
    }

    /// Wall-clock interval of the workout.
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}
