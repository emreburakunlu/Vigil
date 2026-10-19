import Foundation

/// Pure display logic of the Strain detail screen.
enum StrainPresentation {
    struct ZoneRow: Identifiable, Hashable, Sendable {
        var number: Int
        var name: String
        var range: String
        var duration: String
        /// Share of the day's zone time, 0–1.
        var fraction: Double
        /// Bar length relative to the longest zone, 0–1.
        var relativeFraction: Double
        var id: Int { number }
    }

    static func zoneRows(durations: ZoneDurations, zones: HeartRateZones, formatter: VigilFormatter) -> [ZoneRow] {
        let total = durations.total
        let longest = durations.seconds.max() ?? 0
        return zones.zones.sorted { $0.number < $1.number }.map { zone in
            let seconds = durations[zone.number]
            return ZoneRow(number: zone.number, name: LocalizedName.zone(zone.number),
                           range: "\(zone.lowerBound)–\(zone.upperBound) bpm",
                           duration: formatter.duration(seconds),
                           fraction: total > 0 ? seconds / total : 0,
                           relativeFraction: longest > 0 ? seconds / longest : 0)
        }
    }

    enum LocalizedName {
        static func zone(_ number: Int) -> String {
            switch number {
            case 1: String(localized: "Warm-up")
            case 2: String(localized: "Easy")
            case 3: String(localized: "Aerobic")
            case 4: String(localized: "Threshold")
            default: String(localized: "Maximum")
            }
        }
    }

    /// "1h 40m · 2 workouts"
    static func zoneSummary(durations: ZoneDurations, workoutCount: Int, formatter: VigilFormatter) -> String {
        let count = workoutCount == 1 ? String(localized: "1 workout") : String(localized: "\(workoutCount) workouts")
        return durations.total > 0 ? "\(formatter.duration(durations.total)) · \(count)" : count
    }

    static func riskName(_ risk: TrainingLoadRisk) -> String {
        switch risk {
        case .detraining: String(localized: "Detraining")
        case .productive: String(localized: "Productive")
        case .caution: String(localized: "Building fast")
        case .high: String(localized: "Too much, too fast")
        }
    }

    static func suggestedText(_ recovery: RecoveryScore?) -> String? {
        recovery.map { String(localized: "Suggested for \($0.value)% recovery: \($0.suggestedStrain.lowerBound)–\($0.suggestedStrain.upperBound)") }
    }

    /// Fraction of the 270° gauge for a 0–100 value.
    static func gaugeFraction(_ value: Int) -> Double { min(max(Double(value), 0), 100) / 100 }
}
