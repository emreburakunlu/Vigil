import Foundation

/// Pure mapping from repository values to what the Today screens display. Kept free of SwiftUI so the
/// decisions (captions, deltas, subtitles) can be unit-tested.
enum TodayPresentation {

    // MARK: Score tiles

    /// Colour family of a caption under a ring.
    enum CaptionTone: Hashable, Sendable {
        case recovery, warning, danger, sleep, strain, muted
    }

    struct ScoreDisplay: Hashable, Sendable {
        var value: String
        var unit: String?
        var progress: Double
        var caption: String
        var tone: CaptionTone
        var hasScore: Bool
    }

    static func recovery(_ score: RecoveryScore?) -> ScoreDisplay {
        guard let score else {
            return ScoreDisplay(value: "–", unit: nil, progress: 0, caption: String(localized: "No score"), tone: .muted, hasScore: false)
        }
        let caption: String
        let tone: CaptionTone
        if score.isCalibrating {
            caption = String(localized: "Calibrating")
            tone = .warning
        } else if score.isPartial {
            caption = String(localized: "\(score.signalsUsed) of \(score.signalsTotal) signals")
            tone = .warning
        } else {
            switch score.band {
            case .green: caption = String(localized: "Green"); tone = .recovery
            case .yellow: caption = String(localized: "Yellow"); tone = .warning
            case .red: caption = String(localized: "Red"); tone = .danger
            }
        }
        return ScoreDisplay(value: "\(score.value)", unit: "%", progress: Double(score.value) / 100, caption: caption, tone: tone, hasScore: true)
    }

    static func sleep(score: SleepScore?, night: SleepNight?, formatter: VigilFormatter) -> ScoreDisplay {
        guard let score else {
            return ScoreDisplay(value: "–", unit: nil, progress: 0, caption: String(localized: "No sleep"), tone: .muted, hasScore: false)
        }
        let caption = night.map { formatter.duration($0.asleepDuration) } ?? String(localized: "Sleep score")
        return ScoreDisplay(value: "\(score.value)", unit: nil, progress: Double(score.value) / 100, caption: caption, tone: .sleep, hasScore: true)
    }

    /// `isInProgress` is true for today when the day's data is still incomplete ("So far").
    static func strain(_ strain: DailyStrain?, isInProgress: Bool) -> ScoreDisplay {
        guard let strain else {
            return ScoreDisplay(value: "–", unit: nil, progress: 0, caption: String(localized: "No data"), tone: .muted, hasScore: false)
        }
        let caption = isInProgress ? String(localized: "So far") : strainLevelName(strain.level)
        return ScoreDisplay(value: "\(strain.value)", unit: nil, progress: Double(strain.value) / 100, caption: caption, tone: .strain, hasScore: true)
    }

    static func strainLevelName(_ level: StrainLevel) -> String {
        switch level {
        case .light: String(localized: "Light")
        case .moderate: String(localized: "Moderate")
        case .high: String(localized: "High")
        case .allOut: String(localized: "All out")
        }
    }

    static func suggestionName(_ suggestion: ReadinessSuggestion) -> String {
        switch suggestion {
        case .push: String(localized: "Push")
        case .maintain: String(localized: "Maintain")
        case .takeItEasy: String(localized: "Take it easy")
        }
    }

    static func bandName(_ band: RecoveryBand) -> String {
        switch band {
        case .green: String(localized: "Green")
        case .yellow: String(localized: "Yellow")
        case .red: String(localized: "Red")
        }
    }

    /// "Green · Ready to push" style line on the Recovery detail pill.
    static func bandSummary(_ score: RecoveryScore) -> String {
        let detail = switch score.suggestion {
        case .push: String(localized: "Ready to push")
        case .maintain: String(localized: "Hold steady")
        case .takeItEasy: String(localized: "Take it easy")
        }
        return "\(bandName(score.band)) · \(detail)"
    }

    // MARK: Vitals

    struct DeltaDisplay: Hashable, Sendable {
        var text: String
        var direction: VDeltaDirection
        var tone: VDeltaTone
    }

    struct VitalDisplay: Identifiable, Hashable, Sendable {
        var metric: HealthMetric
        var value: String?
        var unit: String?
        var delta: DeltaDisplay?
        var trend: [Double]
        /// Colour hint for the sparkline.
        var tone: VDeltaTone
        var id: HealthMetric { metric }
        var isRecorded: Bool { value != nil }
    }

    static func vital(_ reading: VitalReading, formatter: VigilFormatter) -> VitalDisplay {
        guard reading.value != nil else {
            return VitalDisplay(metric: reading.metric, value: nil, unit: nil, delta: nil, trend: [], tone: .neutral)
        }
        // Wrist temperature is shown as the deviation from baseline (the reading's `delta`).
        let shown: FormattedValue? = reading.metric == .wristTemperature
            ? reading.delta.map { formatter.temperatureDelta(celsius: $0) }
            : reading.value.map { formatter.format(reading.metric, $0) }
        let delta = deltaDisplay(reading, formatter: formatter)
        return VitalDisplay(metric: reading.metric, value: shown?.value ?? "–", unit: shown?.unit, delta: delta,
                            trend: reading.trend.map(\.value), tone: delta?.tone ?? .neutral)
    }

    static func deltaDisplay(_ reading: VitalReading, formatter: VigilFormatter) -> DeltaDisplay? {
        guard reading.value != nil, reading.status != .noBaseline, reading.status != .missing, let delta = reading.delta else { return nil }
        if delta == 0 {
            return DeltaDisplay(text: String(localized: "Steady"), direction: .flat, tone: .neutral)
        }
        let isAbove = delta > 0
        let favourable: Bool? = reading.metric.higherIsBetter.map { $0 == isAbove }
        let tone: VDeltaTone
        if reading.status == .within {
            // Inside the normal range a favourable move is still good news; an unfavourable one is not worth a warning.
            tone = favourable == true ? .positive : .neutral
        } else {
            tone = switch favourable {
            case .some(true): .positive
            case .some(false), .none: .caution
            }
        }
        let text: String
        switch reading.metric {
        case .heartRateVariability, .oxygenSaturation, .vo2Max, .bodyMass:
            text = reading.deltaPercent.map { formatter.percentChange($0).text } ?? formatter.signed(delta, fractionDigits: 0)
        case .restingHeartRate, .heartRate:
            text = FormattedValue(value: formatter.signed(delta, fractionDigits: 0), unit: "bpm").text
        case .respiratoryRate:
            text = FormattedValue(value: formatter.signed(delta, fractionDigits: 1), unit: "br/min").text
        case .wristTemperature:
            text = formatter.temperatureDelta(celsius: delta).text
        }
        return DeltaDisplay(text: text, direction: isAbove ? .up : .down, tone: tone)
    }

    // MARK: Workouts

    struct WorkoutDisplay: Identifiable, Hashable, Sendable {
        var id: UUID
        var kind: WorkoutKind
        var title: String
        var subtitle: String
        var trailingPrimary: String?
        var trailingSecondary: String?
    }

    static func workout(_ item: WorkoutSummary, formatter: VigilFormatter, calendar: Calendar = .current) -> WorkoutDisplay {
        let workout = item.workout
        var parts = [formatter.timeOfDay(workout.start, calendar: calendar)]
        parts.append(workout.kind == .run ? formatter.duration(workout.duration, style: .clock) : formatter.duration(workout.duration, style: .minutes))
        if let via = thirdPartySource(workout) { parts.append(String(localized: "via \(via)")) }

        var primary: String?
        var secondary: String?
        if let distance = workout.distanceMeters, distance > 0 {
            primary = formatter.distance(meters: distance).text
            secondary = workout.averagePaceSecondsPerKilometer.map { formatter.pace(secondsPerKilometer: $0).text }
        } else {
            primary = workout.activeEnergyKilocalories.map { formatter.energy(kilocalories: $0).text }
            secondary = workout.averageHeartRate.map { String(localized: "avg \(formatter.heartRate(bpm: $0).text)") }
        }
        return WorkoutDisplay(id: workout.id, kind: workout.kind, title: workout.displayName, subtitle: parts.joined(separator: " · "),
                              trailingPrimary: primary, trailingSecondary: secondary)
    }

    /// The saving app's name when it is not an Apple app ("Hevy").
    static func thirdPartySource(_ workout: Workout) -> String? {
        let bundle = workout.source.bundleIdentifier ?? ""
        if bundle.hasPrefix("com.apple.") || workout.source.name.isEmpty { return nil }
        if bundle.isEmpty, ["Workout", "Apple Watch", "Health"].contains(workout.source.name) { return nil }
        return workout.source.name
    }

    // MARK: Weekly

    /// "8h" instead of "8h 00m" for round targets.
    static func compactDuration(_ seconds: TimeInterval, formatter: VigilFormatter) -> String {
        let text = formatter.duration(seconds)
        return text.hasSuffix(" 00m") ? String(text.dropLast(4)) : text
    }

    static func weekRange(_ weekly: WeeklyProgress, calendar: Calendar = .current) -> String {
        let start = weekly.startDay.startDate(in: calendar)
        let end = weekly.endDay.startDate(in: calendar)
        var style = Date.IntervalFormatStyle().month(.abbreviated).day()
        style.calendar = calendar
        return (start..<end.addingTimeInterval(3600)).formatted(style)
    }

    // MARK: Header

    static func title(for day: LocalDay, today: LocalDay, calendar: Calendar = .current) -> String {
        if day == today { return String(localized: "Today") }
        if day == today.adding(days: -1, calendar: calendar) { return String(localized: "Yesterday") }
        return day.startDate(in: calendar).formatted(.dateTime.weekday(.wide))
    }

    static func longDate(_ day: LocalDay, calendar: Calendar = .current) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func shortDate(_ day: LocalDay, calendar: Calendar = .current) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Partial data

    /// Why the partial-data banner is shown. nil when nothing is missing.
    static func partialExplanation(missing allMissing: [HealthMetric], recovery: RecoveryScore?) -> String? {
        // Blood oxygen does not feed Recovery, so its absence alone is not worth a banner.
        let missing = allMissing.filter { $0 != .oxygenSaturation }
        guard !missing.isEmpty else { return nil }
        let list = ListFormatter.localizedString(byJoining: missing.map { $0.displayName.lowercased() })
        if let used = recoveryInputs(recovery) {
            return String(localized: "Your watch didn't record \(list) last night. Recovery uses \(used).")
        }
        return String(localized: "Your watch didn't record \(list) last night.")
    }

    private static func recoveryInputs(_ recovery: RecoveryScore?) -> String? {
        guard let recovery else { return nil }
        let names = recovery.factors.filter(\.isAvailable).map { factor -> String in
            switch factor.kind {
            case .heartRateVariability: String(localized: "HRV")
            case .restingHeartRate: String(localized: "resting heart rate")
            case .sleep: String(localized: "sleep")
            case .respiratoryRate: String(localized: "respiratory rate")
            case .wristTemperature: String(localized: "wrist temperature")
            }
        }
        return names.isEmpty ? nil : ListFormatter.localizedString(byJoining: names)
    }
}
