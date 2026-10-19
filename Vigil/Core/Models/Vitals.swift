import Foundation

/// The overnight vitals that feed Recovery, one value per day (usually the sleep-window average).
/// `nil` means "not recorded" (drives the partial-data state).
struct DailyVitals: Hashable, Codable, Sendable {
    var day: LocalDay
    /// HRV SDNN, ms.
    var heartRateVariability: Double?
    /// Resting heart rate, bpm.
    var restingHeartRate: Double?
    /// Respiratory rate, breaths/min.
    var respiratoryRate: Double?
    /// Sleeping wrist temperature, absolute °C.
    var wristTemperature: Double?
    /// Blood oxygen, percent 0–100.
    var oxygenSaturation: Double?

    init(day: LocalDay, heartRateVariability: Double? = nil, restingHeartRate: Double? = nil,
         respiratoryRate: Double? = nil, wristTemperature: Double? = nil, oxygenSaturation: Double? = nil) {
        self.day = day
        self.heartRateVariability = heartRateVariability
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
    }

    /// Value for one of `HealthMetric.vitals`; `nil` for non-vital metrics.
    subscript(metric: HealthMetric) -> Double? {
        get {
            switch metric {
            case .heartRateVariability: heartRateVariability
            case .restingHeartRate: restingHeartRate
            case .respiratoryRate: respiratoryRate
            case .wristTemperature: wristTemperature
            case .oxygenSaturation: oxygenSaturation
            case .heartRate, .vo2Max, .bodyMass: nil
            }
        }
        set {
            switch metric {
            case .heartRateVariability: heartRateVariability = newValue
            case .restingHeartRate: restingHeartRate = newValue
            case .respiratoryRate: respiratoryRate = newValue
            case .wristTemperature: wristTemperature = newValue
            case .oxygenSaturation: oxygenSaturation = newValue
            case .heartRate, .vo2Max, .bodyMass: break
            }
        }
    }

    /// Vitals that have a value.
    var recordedMetrics: [HealthMetric] { HealthMetric.vitals.filter { self[$0] != nil } }
}

/// How a value compares with the personal baseline.
enum BaselineStatus: String, Codable, Sendable {
    case above
    case within
    case below
    /// No value today.
    case missing
    /// Not enough history to have a baseline yet.
    case noBaseline
}

/// A vital value compared with its 30-day baseline (Today "Vitals" card, Sleep vitals, Metric detail).
struct VitalReading: Hashable, Codable, Sendable, Identifiable {
    var metric: HealthMetric
    /// Today's value (canonical unit), nil when not recorded.
    var value: Double?
    var baseline: Baseline?
    /// `value − baseline.mean` (for wrist temperature this *is* the displayed value).
    var delta: Double?
    /// `delta ÷ baseline.mean × 100`.
    var deltaPercent: Double?
    var status: BaselineStatus
    /// Recent daily values for the sparkline (oldest first, typically 9 days).
    var trend: [MetricSample]

    var id: HealthMetric { metric }
}
