import Foundation
import Observation

/// State of the About you step. Every edit is written straight to `SettingsStore`, so units chosen here
/// format everything on later steps and an app kill loses nothing.
@MainActor
@Observable
final class AboutYouModel {
    private let repository: VigilRepository
    private var settingsStore: SettingsStore { repository.settings }

    private(set) var ageText = ""
    private(set) var weightText = ""
    private(set) var manualHeartRateText = ""
    private(set) var sex: BiologicalSex?
    private(set) var bodyMassKilograms: Double?
    private(set) var bodyMassDate: Date?
    private(set) var isFromHealth = false
    private(set) var maxHeartRate = 0

    /// Accepted age range for the age field.
    static let ageRange = 10...110
    /// Accepted manual max heart rate range (bpm).
    static let heartRateRange = 120...230

    init(repository: VigilRepository) {
        self.repository = repository
        syncFromSettings()
    }

    var units: UnitSystem { settingsStore.settings.units }
    var formatter: VigilFormatter { settingsStore.formatter }
    var estimatesMaxHeartRate: Bool { settingsStore.settings.profile.estimatesMaxHeartRate }

    // MARK: Loading

    /// Fills fields that are still empty from Health (date of birth, sex, latest body mass).
    func prefillFromHealth() async {
        guard let found = try? await repository.dataSource.characteristics() else { return }
        let calendar = repository.calendar
        settingsStore.update { settings in
            if settings.profile.dateOfBirth == nil, let birth = found.dateOfBirth.flatMap({ calendar.date(from: $0) }) {
                settings.profile.dateOfBirth = birth
            }
            if settings.profile.sex == nil { settings.profile.sex = found.biologicalSex }
            if settings.profile.bodyMassKilograms == nil, let mass = found.latestBodyMass {
                settings.profile.bodyMassKilograms = mass.value
                settings.profile.bodyMassFromHealth = true
                bodyMassDate = mass.date
            }
        }
        syncFromSettings()
    }

    private func syncFromSettings() {
        let profile = settingsStore.settings.profile
        sex = profile.sex
        bodyMassKilograms = profile.bodyMassKilograms
        isFromHealth = profile.bodyMassFromHealth && profile.bodyMassKilograms != nil
        ageText = profile.age(on: repository.now(), calendar: repository.calendar).map(String.init) ?? ""
        weightText = Self.weightText(kilograms: bodyMassKilograms, formatter: formatter)
        manualHeartRateText = profile.manualMaxHeartRate.map(String.init) ?? ""
        refreshMaxHeartRate()
    }

    private func refreshMaxHeartRate() {
        maxHeartRate = repository.heartRateZones().maxHeartRate
    }

    // MARK: Edits

    func setAgeText(_ text: String) {
        let digits = String(text.filter(\.isNumber).prefix(3))
        ageText = digits
        guard let age = Int(digits), Self.ageRange.contains(age) else { return }
        let now = repository.now(), calendar = repository.calendar
        settingsStore.update {
            $0.profile.dateOfBirth = Self.dateOfBirth(forAge: age, existing: $0.profile.dateOfBirth, now: now, calendar: calendar)
        }
        refreshMaxHeartRate()
    }

    func setSex(_ value: BiologicalSex?) {
        sex = value
        settingsStore.update { $0.profile.sex = value }
    }

    func setWeightText(_ text: String) {
        weightText = text
        guard let display = Self.parseDecimal(text), display > 0 else { return }
        let kilograms = formatter.kilograms(fromDisplayWeight: display)
        guard (20.0...400.0).contains(kilograms) else { return }
        bodyMassKilograms = kilograms
        isFromHealth = false
        settingsStore.update {
            $0.profile.bodyMassKilograms = kilograms
            $0.profile.bodyMassFromHealth = false
        }
    }

    /// Changes the unit system immediately (formatting everywhere follows) and re-expresses the weight.
    func setUnits(_ value: UnitSystem) {
        settingsStore.update { $0.units = value }
        weightText = Self.weightText(kilograms: bodyMassKilograms, formatter: formatter)
    }

    func setEstimatesMaxHeartRate(_ estimates: Bool) {
        settingsStore.update { settings in
            settings.profile.estimatesMaxHeartRate = estimates
            if !estimates, settings.profile.manualMaxHeartRate == nil {
                settings.profile.manualMaxHeartRate = repository.heartRateZones().maxHeartRate
            }
        }
        manualHeartRateText = settingsStore.settings.profile.manualMaxHeartRate.map(String.init) ?? ""
        refreshMaxHeartRate()
    }

    func setManualHeartRateText(_ text: String) {
        let digits = String(text.filter(\.isNumber).prefix(3))
        manualHeartRateText = digits
        guard let bpm = Int(digits), Self.heartRateRange.contains(bpm) else { return }
        settingsStore.update { $0.profile.manualMaxHeartRate = bpm }
        refreshMaxHeartRate()
    }

    // MARK: Pure helpers

    /// Keeps `existing` when it already yields `age`; otherwise `age` years before `now`.
    static func dateOfBirth(forAge age: Int, existing: Date?, now: Date, calendar: Calendar) -> Date {
        if let existing, calendar.dateComponents([.year], from: existing, to: now).year == age { return existing }
        return calendar.date(byAdding: .year, value: -age, to: now) ?? now
    }

    static func weightText(kilograms: Double?, formatter: VigilFormatter) -> String {
        guard let kilograms else { return "" }
        return formatter.weight(kilograms: kilograms).value
    }

    /// Parses "78.4" or "78,4".
    static func parseDecimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacing(",", with: "."))
    }
}
