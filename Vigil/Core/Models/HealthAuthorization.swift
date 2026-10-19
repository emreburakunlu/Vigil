import Foundation

/// What Vigil knows about Health access.
///
/// HealthKit never reveals whether *read* access was denied. `.requested` therefore means
/// "the sheet was shown"; the services layer infers the denied state (StateDenied screen) when
/// `.requested` and no samples exist in any category (`HealthAccessState.likelyDenied`).
enum HealthAuthorizationStatus: String, Codable, Sendable {
    /// Health data is not available on this device (e.g. iPad without Health).
    case unavailable
    /// The permission sheet has not been shown yet.
    case notDetermined
    /// The permission sheet was shown (user may have allowed or denied any subset).
    case requested
}

/// User-facing access state derived by `VigilRepository.healthAccessState()`.
enum HealthAccessState: String, Codable, Sendable {
    case unavailable
    case notDetermined
    /// Authorized and at least some data was found.
    case connected
    /// Requested but nothing is readable — show the "Health access off" screen.
    case likelyDenied
}

/// Groups of data Vigil reads (Onboarding "Connect Apple Health" + Profile "Connected · n of m").
enum HealthDataCategory: String, CaseIterable, Codable, Sendable {
    case sleep
    case heartRate
    case heartRateVariability
    case restingHeartRate
    case respiratoryRate
    case wristTemperature
    case oxygenSaturation
    case workouts
    case workoutRoutes
    case runningMetrics
    case activity
    case vo2Max
    case bodyMass
}

/// Characteristics prefilled on "About you" (all optional; HealthKit may not have them).
struct UserCharacteristics: Hashable, Codable, Sendable {
    var dateOfBirth: DateComponents?
    var biologicalSex: BiologicalSex?
    /// Latest body mass sample, kg.
    var latestBodyMass: MetricSample?

    init(dateOfBirth: DateComponents? = nil, biologicalSex: BiologicalSex? = nil, latestBodyMass: MetricSample? = nil) {
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.latestBodyMass = latestBodyMass
    }
}

/// Sex options offered on "About you" (used for max-HR / calorie estimates only).
enum BiologicalSex: String, CaseIterable, Codable, Sendable {
    case female
    case male
    case other
}
