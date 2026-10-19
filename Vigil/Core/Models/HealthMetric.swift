import Foundation

/// Every quantity metric Vigil reads, with its canonical storage unit.
///
/// All `MetricSample.value`s for a metric are in `canonicalUnit`. Convert for display only
/// through `VigilFormatter` (`formatter.format(metric, value)`).
enum HealthMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Heart rate variability, SDNN. Canonical: milliseconds.
    case heartRateVariability
    /// Resting heart rate. Canonical: beats per minute.
    case restingHeartRate
    /// Respiratory rate during sleep. Canonical: breaths per minute.
    case respiratoryRate
    /// Sleeping wrist temperature, **absolute** °C as stored by HealthKit.
    /// The deviation from baseline is computed by the engine (`VitalReading.delta`).
    case wristTemperature
    /// Blood oxygen saturation. Canonical: percent 0–100 (HealthKit's 0–1 fraction × 100).
    case oxygenSaturation
    /// Heart rate. Canonical: beats per minute.
    case heartRate
    /// Cardio fitness. Canonical: mL/(kg·min).
    case vo2Max
    /// Body mass. Canonical: kilograms.
    case bodyMass

    var id: String { rawValue }

    /// The five overnight vitals shown on Today / Recovery / Metric detail tabs, in design order.
    static let vitals: [HealthMetric] = [.heartRateVariability, .restingHeartRate, .respiratoryRate, .wristTemperature, .oxygenSaturation]

    /// Short name ("HRV", "Resting HR").
    var shortName: String {
        switch self {
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "Resting HR"
        case .respiratoryRate: "Respiratory rate"
        case .wristTemperature: "Wrist temp"
        case .oxygenSaturation: "Blood oxygen"
        case .heartRate: "Heart rate"
        case .vo2Max: "VO₂ max"
        case .bodyMass: "Body weight"
        }
    }

    /// Full name ("Heart rate variability").
    var displayName: String {
        switch self {
        case .heartRateVariability: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Respiratory rate"
        case .wristTemperature: "Wrist temperature"
        case .oxygenSaturation: "Blood oxygen"
        case .heartRate: "Heart rate"
        case .vo2Max: "VO₂ max"
        case .bodyMass: "Body weight"
        }
    }

    /// Canonical unit description (documentation/debugging only; never show to users).
    var canonicalUnit: String {
        switch self {
        case .heartRateVariability: "ms"
        case .restingHeartRate, .heartRate: "count/min"
        case .respiratoryRate: "count/min"
        case .wristTemperature: "degC"
        case .oxygenSaturation: "%"
        case .vo2Max: "ml/(kg*min)"
        case .bodyMass: "kg"
        }
    }

    /// Whether a higher value than baseline is good (`true`), bad (`false`) or neutral (`nil`).
    var higherIsBetter: Bool? {
        switch self {
        case .heartRateVariability, .vo2Max, .oxygenSaturation: true
        case .restingHeartRate: false
        case .respiratoryRate, .wristTemperature, .heartRate, .bodyMass: nil
        }
    }
}

extension VigilFormatter {
    /// Formats a canonical value of any metric (`wristTemperature` is formatted as a delta).
    func format(_ metric: HealthMetric, _ value: Double) -> FormattedValue {
        switch metric {
        case .heartRateVariability: heartRateVariability(milliseconds: value)
        case .restingHeartRate, .heartRate: heartRate(bpm: value)
        case .respiratoryRate: respiratoryRate(breathsPerMinute: value)
        case .wristTemperature: temperatureDelta(celsius: value)
        case .oxygenSaturation: oxygenSaturation(percent: value)
        case .vo2Max: vo2Max(value)
        case .bodyMass: weight(kilograms: value)
        }
    }
}
