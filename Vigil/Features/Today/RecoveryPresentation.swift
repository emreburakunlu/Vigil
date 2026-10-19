import Foundation

/// Pure display logic of the Recovery detail screen.
enum RecoveryPresentation {
    /// Points that fill one half of the contribution bar completely.
    static let fullBarPoints = 20.0

    struct FactorDisplay: Identifiable, Hashable, Sendable {
        var kind: RecoveryFactorKind
        var name: String
        var detail: String
        /// "+14", "−3", "0" or "–" when the signal was not recorded.
        var points: String
        /// 0–1 share of the half bar.
        var fraction: Double
        var isPositive: Bool
        var isNegative: Bool
        var isAvailable: Bool
        var id: RecoveryFactorKind { kind }
    }

    static func factorName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .heartRateVariability: String(localized: "HRV")
        case .restingHeartRate: String(localized: "Resting heart rate")
        case .sleep: String(localized: "Sleep")
        case .respiratoryRate: String(localized: "Respiratory rate")
        case .wristTemperature: String(localized: "Wrist temperature")
        }
    }

    static func factor(_ factor: RecoveryFactor, sleepDuration: TimeInterval?, formatter: VigilFormatter) -> FactorDisplay {
        let name = factorName(factor.kind)
        guard factor.isAvailable, let value = factor.value else {
            return FactorDisplay(kind: factor.kind, name: name, detail: String(localized: "Not recorded"), points: "–", fraction: 0,
                                 isPositive: false, isNegative: false, isAvailable: false)
        }
        func baselineText(_ digits: Int) -> String? { factor.baseline.map { formatter.number($0, fractionDigits: digits) } }
        let detail: String
        switch factor.kind {
        case .heartRateVariability:
            detail = [formatter.heartRateVariability(milliseconds: value).text, baselineText(0).map { String(localized: "baseline \($0)") }]
                .compactMap { $0 }.joined(separator: " · ")
        case .restingHeartRate:
            detail = [formatter.heartRate(bpm: value).text, baselineText(0).map { String(localized: "baseline \($0)") }]
                .compactMap { $0 }.joined(separator: " · ")
        case .sleep:
            var parts = [String(localized: "Score \(Int(value.rounded()))")]
            if let sleepDuration { parts.append(formatter.duration(sleepDuration)) }
            detail = parts.joined(separator: " · ")
        case .respiratoryRate:
            let steady = factor.points == 0 ? String(localized: "steady") : nil
            detail = [formatter.respiratoryRate(breathsPerMinute: value).text, steady].compactMap { $0 }.joined(separator: " · ")
        case .wristTemperature:
            if let baseline = factor.baseline {
                let delta = value - baseline
                let text = formatter.temperatureDelta(celsius: delta).text
                detail = delta > 0.005 ? String(localized: "\(text) above baseline")
                    : (delta < -0.005 ? String(localized: "\(text) below baseline") : String(localized: "At baseline"))
            } else {
                detail = String(localized: "Baseline still building")
            }
        }
        let pointsText: String = factor.points == 0 ? "0" : formatter.signed(Double(factor.points), fractionDigits: 0)
        return FactorDisplay(kind: factor.kind, name: name, detail: detail, points: pointsText,
                             fraction: min(abs(Double(factor.points)) / fullBarPoints, 1),
                             isPositive: factor.points > 0, isNegative: factor.points < 0, isAvailable: true)
    }

    /// "Calibrating · 4 more nights".
    static func calibrationText(_ score: RecoveryScore) -> String? {
        guard score.isCalibrating, let days = score.calibrationDaysRemaining else { return nil }
        return String(localized: "Calibrating · \(days) more nights")
    }

    /// Average of the available recovery values, nil when empty.
    static func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
