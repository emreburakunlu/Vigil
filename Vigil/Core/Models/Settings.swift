import Foundation

/// The user's profile (onboarding "About you", Profile screen).
struct UserProfile: Hashable, Codable, Sendable {
    /// Date of birth (from Health or derived from the entered age).
    var dateOfBirth: Date?
    var sex: BiologicalSex?
    /// Body mass, kg. Synced from Health when `bodyMassFromHealth`.
    var bodyMassKilograms: Double?
    var bodyMassFromHealth: Bool
    /// `true` = estimate max HR from age ("Estimate for me"); `false` = use `manualMaxHeartRate`.
    var estimatesMaxHeartRate: Bool
    var manualMaxHeartRate: Int?

    static let `default` = UserProfile(dateOfBirth: nil, sex: nil, bodyMassKilograms: nil,
                                       bodyMassFromHealth: true, estimatesMaxHeartRate: true, manualMaxHeartRate: nil)

    /// Age in whole years on `date`.
    func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let dateOfBirth else { return nil }
        return calendar.dateComponents([.year], from: dateOfBirth, to: date).year
    }
}

/// Weekly / nightly goals (onboarding "Set your goals", Profile → Goals).
struct Goals: Hashable, Codable, Sendable {
    /// Nightly time asleep target, seconds (default 8 h; stepper 5–11 h in 15-min steps).
    var sleepTarget: TimeInterval
    /// Weekly running distance, metres (default 25 km).
    var weeklyRunDistanceMeters: Double
    /// Weekly strength sessions (default 3, 0–7).
    var weeklyLiftSessions: Int

    static let `default` = Goals(sleepTarget: 8 * 3600, weeklyRunDistanceMeters: 25_000, weeklyLiftSessions: 3)
}

/// Heart-rate zone configuration (Profile → Heart rate zones: Automatic / Custom).
struct HeartRateZoneSettings: Hashable, Codable, Sendable {
    /// `false` = automatic from max HR.
    var usesCustomZones: Bool
    /// Upper bounds (bpm) of Z1…Z4 when custom; Z5 runs to max HR. Exactly 4 ascending values.
    var customUpperBounds: [Int]

    static let `default` = HeartRateZoneSettings(usesCustomZones: false, customUpperBounds: [])
}

/// Local notification preferences.
struct NotificationPreferences: Hashable, Codable, Sendable {
    /// "Morning recovery summary · After you wake, or at the time below".
    var morningSummaryEnabled: Bool
    /// Fallback delivery time, minutes after midnight (default 07:30).
    var morningSummaryMinutes: Int
    /// "Bedtime reminder · Based on your sleep target".
    var bedtimeReminderEnabled: Bool
    /// Reminder time, minutes after midnight (default 22:30).
    var bedtimeReminderMinutes: Int

    static let `default` = NotificationPreferences(morningSummaryEnabled: true, morningSummaryMinutes: 7 * 60 + 30,
                                                   bedtimeReminderEnabled: false, bedtimeReminderMinutes: 22 * 60 + 30)
}

/// Onboarding / import progress flags.
struct OnboardingState: Hashable, Codable, Sendable {
    var completed: Bool
    /// When Health access was requested (the sheet was shown).
    var healthAccessRequestedAt: Date?
    /// When the 90-day history import last finished.
    var historyImportedAt: Date?

    static let `default` = OnboardingState(completed: false, healthAccessRequestedAt: nil, historyImportedAt: nil)
}

/// All user settings as one value. Read via `SettingsStore.settings`, mutate via `SettingsStore.update`.
struct VigilSettings: Hashable, Codable, Sendable {
    var units: UnitSystem
    var appearance: AppearanceMode
    var profile: UserProfile
    var goals: Goals
    var heartRateZones: HeartRateZoneSettings
    var notifications: NotificationPreferences
    var onboarding: OnboardingState

    static let `default` = VigilSettings(units: .metric, appearance: .system, profile: .default, goals: .default,
                                         heartRateZones: .default, notifications: .default, onboarding: .default)

    /// Formatter for the current unit system.
    var formatter: VigilFormatter { VigilFormatter(units: units) }
}
