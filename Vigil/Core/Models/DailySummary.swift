import Foundation

/// Everything computed for one day, cached in SwiftData (`DailySummaryRecord`) so screens and
/// the widget don't recompute 90 days on every launch. Any part may be missing.
struct DailySummary: Hashable, Codable, Sendable {
    /// Bump when the engine or the summary pipeline changes in a way that invalidates cached summaries.
    /// 3: previous-day strain / training load seeded for one-day builds, settings fingerprint, deduplicated workouts.
    static let currentEngineVersion = 3

    var day: LocalDay
    var computedAt: Date
    var engineVersion: Int
    /// `SummarySettingsFingerprint` of the settings the summary was computed with (sleep target, profile,
    /// heart-rate zones). A mismatch with the current settings makes the cached summary stale.
    /// nil for summaries written before engine version 3.
    var settingsFingerprint: String?

    var baselines: PersonalBaselines?
    var vitals: DailyVitals?
    var activity: DailyActivity?
    /// Primary night ending on this day.
    var sleepNightID: String?
    var sleepDuration: TimeInterval?
    var sleepScore: SleepScore?
    var recovery: RecoveryScore?
    var strain: DailyStrain?

    init(day: LocalDay, computedAt: Date = .now, engineVersion: Int = DailySummary.currentEngineVersion,
         settingsFingerprint: String? = nil,
         baselines: PersonalBaselines? = nil, vitals: DailyVitals? = nil, activity: DailyActivity? = nil,
         sleepNightID: String? = nil, sleepDuration: TimeInterval? = nil, sleepScore: SleepScore? = nil,
         recovery: RecoveryScore? = nil, strain: DailyStrain? = nil) {
        self.day = day
        self.computedAt = computedAt
        self.engineVersion = engineVersion
        self.settingsFingerprint = settingsFingerprint
        self.baselines = baselines
        self.vitals = vitals
        self.activity = activity
        self.sleepNightID = sleepNightID
        self.sleepDuration = sleepDuration
        self.sleepScore = sleepScore
        self.recovery = recovery
        self.strain = strain
    }
}

/// A stable fingerprint of the settings that change computed scores. Uses FNV-1a over a canonical
/// string, so it is identical across launches (unlike `Hasher`).
enum SummarySettingsFingerprint {
    static func make(settings: VigilSettings, zones: HeartRateZones) -> String {
        let profile = settings.profile
        let birth = profile.dateOfBirth.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let canonical = [
            "sleep=\(Int(settings.goals.sleepTarget.rounded()))",
            "sex=\(profile.sex?.rawValue ?? "-")",
            "dob=\(birth)",
            "max=\(zones.maxHeartRate)",
            "zones=\(zones.zones.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ","))",
        ].joined(separator: ";")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
