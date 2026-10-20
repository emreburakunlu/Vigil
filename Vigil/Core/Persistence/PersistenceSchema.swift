import Foundation
import SwiftData

// SwiftData schema. Records are persistence details: feature code never touches them and works
// with the value types (`VigilSettings`, `DailySummary`) exposed by `SettingsStore` /
// `DailySummaryStore`. To change the schema add a new `VigilSchemaVn` + a migration stage; never edit
// V1 models in place once shipped.

enum VigilSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SettingsRecord.self, DailySummaryRecord.self]
    }

    /// Singleton row holding all user settings (flat primitives for migration safety).
    @Model
    final class SettingsRecord {
        var unitsRaw: String
        var appearanceRaw: String

        var dateOfBirth: Date?
        var sexRaw: String?
        var bodyMassKilograms: Double?
        var bodyMassFromHealth: Bool
        var estimatesMaxHeartRate: Bool
        var manualMaxHeartRate: Int?

        var sleepTargetSeconds: Double
        var weeklyRunDistanceMeters: Double
        var weeklyLiftSessions: Int

        var usesCustomZones: Bool
        /// Comma-separated Z1…Z4 upper bounds, e.g. `"117,137,156,176"`.
        var customZoneUpperBoundsCSV: String

        var morningSummaryEnabled: Bool
        var morningSummaryMinutes: Int
        var bedtimeReminderEnabled: Bool
        var bedtimeReminderMinutes: Int

        var onboardingCompleted: Bool
        var healthAccessRequestedAt: Date?
        var historyImportedAt: Date?

        var updatedAt: Date

        init(settings: VigilSettings = .default, now: Date = .now) {
            unitsRaw = settings.units.rawValue
            appearanceRaw = settings.appearance.rawValue
            dateOfBirth = settings.profile.dateOfBirth
            sexRaw = settings.profile.sex?.rawValue
            bodyMassKilograms = settings.profile.bodyMassKilograms
            bodyMassFromHealth = settings.profile.bodyMassFromHealth
            estimatesMaxHeartRate = settings.profile.estimatesMaxHeartRate
            manualMaxHeartRate = settings.profile.manualMaxHeartRate
            sleepTargetSeconds = settings.goals.sleepTarget
            weeklyRunDistanceMeters = settings.goals.weeklyRunDistanceMeters
            weeklyLiftSessions = settings.goals.weeklyLiftSessions
            usesCustomZones = settings.heartRateZones.usesCustomZones
            customZoneUpperBoundsCSV = settings.heartRateZones.customUpperBounds.map(String.init).joined(separator: ",")
            morningSummaryEnabled = settings.notifications.morningSummaryEnabled
            morningSummaryMinutes = settings.notifications.morningSummaryMinutes
            bedtimeReminderEnabled = settings.notifications.bedtimeReminderEnabled
            bedtimeReminderMinutes = settings.notifications.bedtimeReminderMinutes
            onboardingCompleted = settings.onboarding.completed
            healthAccessRequestedAt = settings.onboarding.healthAccessRequestedAt
            historyImportedAt = settings.onboarding.historyImportedAt
            updatedAt = now
        }

        /// Copies every field from `settings`.
        func apply(_ settings: VigilSettings, now: Date = .now) {
            let fresh = SettingsRecord(settings: settings, now: now)
            unitsRaw = fresh.unitsRaw
            appearanceRaw = fresh.appearanceRaw
            dateOfBirth = fresh.dateOfBirth
            sexRaw = fresh.sexRaw
            bodyMassKilograms = fresh.bodyMassKilograms
            bodyMassFromHealth = fresh.bodyMassFromHealth
            estimatesMaxHeartRate = fresh.estimatesMaxHeartRate
            manualMaxHeartRate = fresh.manualMaxHeartRate
            sleepTargetSeconds = fresh.sleepTargetSeconds
            weeklyRunDistanceMeters = fresh.weeklyRunDistanceMeters
            weeklyLiftSessions = fresh.weeklyLiftSessions
            usesCustomZones = fresh.usesCustomZones
            customZoneUpperBoundsCSV = fresh.customZoneUpperBoundsCSV
            morningSummaryEnabled = fresh.morningSummaryEnabled
            morningSummaryMinutes = fresh.morningSummaryMinutes
            bedtimeReminderEnabled = fresh.bedtimeReminderEnabled
            bedtimeReminderMinutes = fresh.bedtimeReminderMinutes
            onboardingCompleted = fresh.onboardingCompleted
            healthAccessRequestedAt = fresh.healthAccessRequestedAt
            historyImportedAt = fresh.historyImportedAt
            updatedAt = now
        }

        /// The value-type view of this record. Unknown raw values fall back to defaults.
        var value: VigilSettings {
            VigilSettings(
                units: UnitSystem(rawValue: unitsRaw) ?? .metric,
                appearance: AppearanceMode(rawValue: appearanceRaw) ?? .system,
                profile: UserProfile(dateOfBirth: dateOfBirth, sex: sexRaw.flatMap(BiologicalSex.init(rawValue:)),
                                     bodyMassKilograms: bodyMassKilograms, bodyMassFromHealth: bodyMassFromHealth,
                                     estimatesMaxHeartRate: estimatesMaxHeartRate, manualMaxHeartRate: manualMaxHeartRate),
                goals: Goals(sleepTarget: sleepTargetSeconds, weeklyRunDistanceMeters: weeklyRunDistanceMeters,
                             weeklyLiftSessions: weeklyLiftSessions),
                heartRateZones: HeartRateZoneSettings(usesCustomZones: usesCustomZones,
                                                      customUpperBounds: customZoneUpperBoundsCSV.split(separator: ",").compactMap { Int($0) }),
                notifications: NotificationPreferences(morningSummaryEnabled: morningSummaryEnabled,
                                                       morningSummaryMinutes: morningSummaryMinutes,
                                                       bedtimeReminderEnabled: bedtimeReminderEnabled,
                                                       bedtimeReminderMinutes: bedtimeReminderMinutes),
                onboarding: OnboardingState(completed: onboardingCompleted, healthAccessRequestedAt: healthAccessRequestedAt,
                                            historyImportedAt: historyImportedAt)
            )
        }
    }

    /// Cached `DailySummary` for one day. The full summary is JSON in `payload`; a few fields are
    /// denormalized for cheap queries (calendar, widgets).
    @Model
    final class DailySummaryRecord {
        /// `LocalDay.key` (yyyymmdd).
        @Attribute(.unique) var dayKey: Int
        var computedAt: Date
        var engineVersion: Int
        var recoveryPercent: Int?
        var sleepScore: Int?
        var strain: Int?
        /// JSON-encoded `DailySummary`.
        var payload: Data

        init(dayKey: Int, computedAt: Date, engineVersion: Int, recoveryPercent: Int?, sleepScore: Int?, strain: Int?, payload: Data) {
            self.dayKey = dayKey
            self.computedAt = computedAt
            self.engineVersion = engineVersion
            self.recoveryPercent = recoveryPercent
            self.sleepScore = sleepScore
            self.strain = strain
            self.payload = payload
        }
    }
}

// MARK: - V2

/// V2 adds `DailySummaryRecord.settingsFingerprint` so the cache can be checked for staleness without
/// decoding payloads. `SettingsRecord` is unchanged and shared with V1.
enum VigilSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [VigilSchemaV1.SettingsRecord.self, DailySummaryRecord.self]
    }

    /// Cached `DailySummary` for one day. The full summary is JSON in `payload`; a few fields are
    /// denormalized for cheap queries (calendar, widgets, cache freshness checks).
    @Model
    final class DailySummaryRecord {
        /// `LocalDay.key` (yyyymmdd).
        @Attribute(.unique) var dayKey: Int
        var computedAt: Date
        var engineVersion: Int
        /// `DailySummary.settingsFingerprint`; nil for rows migrated from V1 (treated as stale).
        var settingsFingerprint: String?
        var recoveryPercent: Int?
        var sleepScore: Int?
        var strain: Int?
        /// JSON-encoded `DailySummary`.
        var payload: Data

        init(dayKey: Int, computedAt: Date, engineVersion: Int, settingsFingerprint: String? = nil,
             recoveryPercent: Int?, sleepScore: Int?, strain: Int?, payload: Data) {
            self.dayKey = dayKey
            self.computedAt = computedAt
            self.engineVersion = engineVersion
            self.settingsFingerprint = settingsFingerprint
            self.recoveryPercent = recoveryPercent
            self.sleepScore = sleepScore
            self.strain = strain
            self.payload = payload
        }
    }
}

typealias SettingsRecord = VigilSchemaV1.SettingsRecord
typealias DailySummaryRecord = VigilSchemaV2.DailySummaryRecord

/// Migration plan. V1 → V2 is lightweight (one new optional attribute).
enum VigilMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VigilSchemaV1.self, VigilSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: VigilSchemaV1.self, toVersion: VigilSchemaV2.self)]
    }
}
