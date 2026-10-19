import Foundation

/// Everything the "night" cards show for one `SleepNightDetail`, already formatted.
/// Built once on load (never in `body`); the same value drives the Sleep tab and the Sleep Night screen.
struct SleepNightPresentation: Equatable, Sendable {
    struct StageTile: Equatable, Sendable, Identifiable {
        var stage: SleepStage
        var name: String
        var time: String
        var percent: String
        /// Share of the night, mapped to 0...1 of the tile's bar.
        var markFraction: Double
        /// Typical range on the same 0...1 bar scale.
        var bandStart: Double
        var bandEnd: Double
        var typical: String
        var id: SleepStage { stage }
    }

    struct TickLabel: Equatable, Sendable {
        var fraction: Double
        var text: String
    }

    struct VitalRow: Equatable, Sendable, Identifiable {
        enum Arrow: Equatable, Sendable { case up, down }
        enum Tone: Equatable, Sendable { case positive, caution }

        var metric: HealthMetric
        var name: String
        /// Formatted value; nil renders "Not available".
        var value: String?
        var arrow: Arrow?
        var tone: Tone
        var baseline: String?
        var accessibilityLabel: String
        var id: HealthMetric { metric }
    }

    var day: LocalDay
    var range: String
    var scoreValue: Int
    var band: SleepScoreBand
    var totalSleep: String
    /// Asleep ÷ target, 0...1.
    var targetProgress: Double
    var targetCaption: String
    var bedtime: String
    var wakeTime: String
    var inBed: String
    var efficiency: String
    var interruptions: String
    var scoreAccessibility: String
    var hypnogram: SleepHypnogramLayout?
    var hypnogramTicks: [TickLabel]
    var hypnogramAccessibility: String
    var stages: [StageTile]
    var vitals: [VitalRow]

    /// Bar scale of the stage tiles: a share of this fraction fills the whole bar.
    static let stageBarScale = 0.6

    init(detail: SleepNightDetail, formatter: VigilFormatter, calendar: Calendar) {
        let night = detail.night
        day = night.day
        range = SleepFormat.nightRange(for: night.day, calendar: calendar)
        scoreValue = detail.score.value
        band = detail.score.band
        totalSleep = formatter.duration(night.asleepDuration)
        let target = night.asleepDuration - detail.score.targetDifference
        targetProgress = target > 0 ? min(1, max(0, night.asleepDuration / target)) : 0
        targetCaption = SleepFormat.targetCaption(difference: detail.score.targetDifference, target: target, formatter: formatter)
        bedtime = formatter.timeOfDay(night.sleepStart, calendar: calendar)
        wakeTime = formatter.timeOfDay(night.sleepEnd, calendar: calendar)
        inBed = formatter.duration(night.inBedDuration)
        efficiency = formatter.percent(Int((night.efficiency * 100).rounded())).text
        interruptions = "\(night.interruptions)"
        scoreAccessibility = String(localized: "Sleep score \(detail.score.value), \(SleepScoreBand.spokenName(detail.score.band))")

        if night.hasStages {
            let layout = SleepHypnogramLayout(segments: night.segments)
            hypnogram = layout
            hypnogramTicks = layout?.ticks(calendar: calendar).map { TickLabel(fraction: $0.fraction, text: formatter.timeOfDay($0.date, calendar: calendar)) } ?? []
            stages = Self.stageTiles(night: night, typical: detail.typicalStageShare, formatter: formatter)
        } else {
            hypnogram = nil
            hypnogramTicks = []
            stages = []
        }
        if let layout = hypnogram {
            let summary = stages.map { "\($0.name) \($0.time)" }.joined(separator: ", ")
            hypnogramAccessibility = String(localized: "Sleep stages from \(formatter.timeOfDay(layout.start, calendar: calendar)) to \(formatter.timeOfDay(layout.end, calendar: calendar)). \(summary)")
        } else {
            hypnogramAccessibility = ""
        }
        vitals = detail.vitals.map { Self.vitalRow($0, formatter: formatter) }
    }

    /// Whether any vital has a value (the card is hidden otherwise).
    var hasVitals: Bool { vitals.contains { $0.value != nil } }

    // MARK: Stage tiles

    private static func stageTiles(night: SleepNight, typical: [SleepStage: ClosedRange<Double>], formatter: VigilFormatter) -> [StageTile] {
        SleepStage.hypnogramStages.map { stage in
            let share = night.stageDurations.share(of: stage)
            let range = typical[stage]
            let name = stageName(stage)
            let typicalText: String
            if let range {
                let low = formatter.number(range.lowerBound * 100, fractionDigits: 0)
                let high = formatter.percent(Int((range.upperBound * 100).rounded())).text
                typicalText = stage == .awake
                    ? String(localized: "Typical \(low)–\(high) of night")
                    : String(localized: "Typical \(low)–\(high)")
            } else {
                typicalText = ""
            }
            return StageTile(
                stage: stage, name: name,
                time: formatter.duration(night.stageDurations[stage]),
                percent: formatter.percent(Int((share * 100).rounded())).text,
                markFraction: min(1, share / stageBarScale),
                bandStart: min(1, (range?.lowerBound ?? 0) / stageBarScale),
                bandEnd: min(1, (range?.upperBound ?? 0) / stageBarScale),
                typical: typicalText)
        }
    }

    static func stageName(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: String(localized: "Awake")
        case .rem: String(localized: "REM")
        case .core, .asleepUnspecified: String(localized: "Core")
        case .deep: String(localized: "Deep")
        case .inBed: String(localized: "In bed")
        }
    }

    // MARK: Vitals

    static func vitalName(_ metric: HealthMetric) -> String {
        metric == .heartRateVariability ? metric.shortName : metric.displayName
    }

    private static func vitalRow(_ reading: VitalReading, formatter: VigilFormatter) -> VitalRow {
        let metric = reading.metric
        let name = vitalName(metric)
        let valueText: String?
        if metric == .wristTemperature {
            valueText = reading.delta.map { formatter.temperatureDelta(celsius: $0).text }
        } else {
            valueText = reading.value.map { formatter.format(metric, $0).text }
        }
        let baselineText = baselineText(reading, formatter: formatter)

        var arrow: VitalRow.Arrow?
        switch reading.status {
        case .above: arrow = .up
        case .below: arrow = .down
        case .within, .missing, .noBaseline: arrow = nil
        }
        var tone = VitalRow.Tone.caution
        if let arrow, let higherIsBetter = metric.higherIsBetter {
            tone = (arrow == .up) == higherIsBetter ? .positive : .caution
        }

        var spoken = valueText.map { "\(name) \($0)" } ?? String(localized: "\(name) not available")
        switch reading.status {
        case .above: spoken += String(localized: ", above baseline")
        case .below: spoken += String(localized: ", below baseline")
        case .within: spoken += String(localized: ", within baseline")
        case .missing, .noBaseline: break
        }
        if let baselineText { spoken += String(localized: ", baseline \(baselineText)") }
        return VitalRow(metric: metric, name: name, value: valueText, arrow: arrow, tone: tone,
                        baseline: baselineText, accessibilityLabel: spoken)
    }

    private static func baselineText(_ reading: VitalReading, formatter: VigilFormatter) -> String? {
        guard let baseline = reading.baseline, baseline.isEstablished else { return nil }
        switch reading.metric {
        case .wristTemperature:
            let spread = formatter.temperatureDelta(celsius: baseline.standardDeviation)
            let value = spread.value.hasPrefix("+") ? String(spread.value.dropFirst()) : spread.value
            return "±\(FormattedValue(value: value, unit: spread.unit).text)"
        case .oxygenSaturation:
            let range = baseline.normalRange
            let low = formatter.number(range.lowerBound, fractionDigits: 0)
            let high = formatter.oxygenSaturation(percent: min(100, range.upperBound)).text
            return "\(low)–\(high)"
        default:
            return formatter.format(reading.metric, baseline.mean).text
        }
    }
}

extension SleepScoreBand {
    /// VoiceOver wording for the band.
    static func spokenName(_ band: SleepScoreBand) -> String {
        switch band {
        case .great: String(localized: "great")
        case .good: String(localized: "good")
        case .fair: String(localized: "fair")
        case .poor: String(localized: "poor")
        }
    }

    /// Legend text of the calendar ("85+ Great").
    var legend: String {
        switch self {
        case .great: String(localized: "85+ Great")
        case .good: String(localized: "70–84 Good")
        case .fair: String(localized: "50–69 Fair")
        case .poor: String(localized: "<50 Poor")
        }
    }
}
