import Foundation

/// Recovery colour band. Thresholds come from the design: Red 0–33, Yellow 34–66, Green 67–100.
enum RecoveryBand: String, Codable, CaseIterable, Sendable {
    case red
    case yellow
    case green

    /// Band for a recovery percentage (clamped to 0...100).
    init(percent: Int) {
        switch min(max(percent, 0), 100) {
        case 67...: self = .green
        case 34...: self = .yellow
        default: self = .red
        }
    }

    /// Inclusive percentage range covered by the band.
    var range: ClosedRange<Int> {
        switch self {
        case .red: 0...33
        case .yellow: 34...66
        case .green: 67...100
        }
    }
}

/// What the day's recovery suggests for training ("Push / Maintain / Take it easy").
enum ReadinessSuggestion: String, Codable, CaseIterable, Sendable {
    case push
    case maintain
    case takeItEasy
}

/// Qualitative level of a strain value (0–100 scale).
enum StrainLevel: String, Codable, CaseIterable, Sendable {
    case light
    case moderate
    case high
    case allOut

    /// Level for a strain value: Light < 34, Moderate 34–66, High 67–89, All out ≥ 90.
    init(strain: Int) {
        switch strain {
        case 90...: self = .allOut
        case 67...: self = .high
        case 34...: self = .moderate
        default: self = .light
        }
    }
}

/// Sleep score band used by the sleep calendar legend: 85+ Great, 70–84 Good, 50–69 Fair, < 50 Poor.
enum SleepScoreBand: String, Codable, CaseIterable, Sendable {
    case poor
    case fair
    case good
    case great

    init(score: Int) {
        switch score {
        case 85...: self = .great
        case 70...: self = .good
        case 50...: self = .fair
        default: self = .poor
        }
    }
}
