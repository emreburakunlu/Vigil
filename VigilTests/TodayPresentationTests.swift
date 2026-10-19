import Foundation
import Testing
@testable import Vigil

@Suite("Today presentation")
struct TodayPresentationTests {
    let metric = VigilFormatter(units: .metric, locale: Locale(identifier: "en_US"))
    let imperial = VigilFormatter(units: .imperial, locale: Locale(identifier: "en_US"))
    let day = LocalDay(year: 2026, month: 10, day: 19)

    private func recovery(value: Int = 78, used: Int = 5, calibration: Int? = nil) -> RecoveryScore {
        RecoveryScore(value: value, band: RecoveryBand(percent: value), factors: [], suggestion: .push, message: "m",
                      suggestedStrain: 55...75, signalsUsed: used, signalsTotal: 5, calibrationDaysRemaining: calibration)
    }

    @Test func recoveryCaptions() {
        #expect(TodayPresentation.recovery(nil).hasScore == false)
        #expect(TodayPresentation.recovery(recovery()).caption == "Green")
        #expect(TodayPresentation.recovery(recovery(value: 40)).caption == "Yellow")
        #expect(TodayPresentation.recovery(recovery(value: 20)).tone == .danger)
        #expect(TodayPresentation.recovery(recovery(used: 3)).caption == "3 of 5 signals")
        #expect(TodayPresentation.recovery(recovery(calibration: 4)).caption == "Calibrating")
        #expect(TodayPresentation.recovery(recovery()).progress == 0.78)
    }

    @Test func strainCaptionInProgress() {
        let strain = DailyStrain(day: day, value: 62, level: .moderate, workouts: [], everydayMovement: 5, zoneDurations: ZoneDurations(), trainingLoad: 0)
        #expect(TodayPresentation.strain(strain, isInProgress: false).caption == "Moderate")
        #expect(TodayPresentation.strain(strain, isInProgress: true).caption == "So far")
        #expect(TodayPresentation.strain(nil, isInProgress: false).value == "–")
    }

    private func reading(_ metricKind: HealthMetric, value: Double?, mean: Double, sd: Double = 4, delta: Double? = nil, percent: Double? = nil,
                         status: BaselineStatus) -> VitalReading {
        VitalReading(metric: metricKind, value: value, baseline: Baseline(mean: mean, standardDeviation: sd, sampleCount: 30),
                     delta: delta, deltaPercent: percent, status: status, trend: [])
    }

    @Test func vitalDeltas() {
        let hrv = TodayPresentation.vital(reading(.heartRateVariability, value: 68, mean: 61, delta: 7, percent: 12, status: .above), formatter: metric)
        #expect(hrv.value == "68")
        #expect(hrv.unit == "ms")
        #expect(hrv.delta?.text == "+12%")
        #expect(hrv.delta?.direction == .up)
        #expect(hrv.delta?.tone == .positive)

        let rhr = TodayPresentation.vital(reading(.restingHeartRate, value: 52, mean: 55, delta: -3, percent: -5, status: .below), formatter: metric)
        #expect(rhr.delta?.text == "\u{2212}3 bpm")
        #expect(rhr.delta?.direction == .down)
        #expect(rhr.delta?.tone == .positive)

        let resp = TodayPresentation.vital(reading(.respiratoryRate, value: 14.6, mean: 14.6, delta: 0, status: .within), formatter: metric)
        #expect(resp.delta?.text == "Steady")
        #expect(resp.delta?.direction == .flat)
    }

    @Test func wristTemperatureShowsDeviationAndUnits() {
        let r = reading(.wristTemperature, value: 36.7, mean: 36.49, delta: 0.21, status: .above)
        let c = TodayPresentation.vital(r, formatter: metric)
        #expect(c.value == "+0.21")
        #expect(c.unit == "°C")
        #expect(c.delta?.tone == .caution)
        let f = TodayPresentation.vital(r, formatter: imperial)
        #expect(f.unit == "°F")
    }

    @Test func missingVitalIsNotRecorded() {
        let r = VitalReading(metric: .respiratoryRate, value: nil, baseline: nil, delta: nil, deltaPercent: nil, status: .missing, trend: [])
        let d = TodayPresentation.vital(r, formatter: metric)
        #expect(d.isRecorded == false)
        #expect(d.delta == nil)
    }

    @Test func noBaselineHasNoDelta() {
        let r = VitalReading(metric: .restingHeartRate, value: 52, baseline: nil, delta: nil, deltaPercent: nil, status: .noBaseline, trend: [])
        #expect(TodayPresentation.vital(r, formatter: metric).delta == nil)
    }

    @Test func partialExplanationIgnoresBloodOxygenAlone() {
        #expect(TodayPresentation.partialExplanation(missing: [.oxygenSaturation], recovery: nil) == nil)
        let text = TodayPresentation.partialExplanation(missing: [.respiratoryRate, .wristTemperature, .oxygenSaturation], recovery: nil)
        #expect(text?.contains("respiratory rate") == true)
        #expect(text?.contains("blood oxygen") == false)
    }

    @Test func compactDuration() {
        #expect(TodayPresentation.compactDuration(8 * 3600, formatter: metric) == "8h")
        #expect(TodayPresentation.compactDuration(7.5 * 3600, formatter: metric) == "7h 30m")
    }

    @Test func dayWindowFollowsSelection() {
        let utc = TestSupport.utc
        let today = day
        let w = TodayDayWindow.containing(today, today: today, calendar: utc)
        #expect(w.days.count == 7)
        #expect(w.days.last == today)
        #expect(w.days.first == today.adding(days: -6, calendar: utc))
        let old = today.adding(days: -10, calendar: utc)
        let w2 = TodayDayWindow.containing(old, today: today, calendar: utc)
        #expect(w2.days.contains(old))
        #expect(w2.days.first == old)
        #expect(TodayDayWindow.step(today, by: 1, today: today, calendar: utc) == today)
        #expect(TodayDayWindow.step(today, by: -1, today: today, calendar: utc) == today.adding(days: -1, calendar: utc))
    }
}

@Suite("Recovery, strain and metric presentation")
struct TodayDetailPresentationTests {
    let f = VigilFormatter(units: .metric, locale: Locale(identifier: "en_US"))
    let lb = VigilFormatter(units: .imperial, locale: Locale(identifier: "en_US"))

    @Test func factorDisplay() {
        let hrv = RecoveryFactor(kind: .heartRateVariability, value: 68, baseline: 61, points: 14, isAvailable: true)
        let d = RecoveryPresentation.factor(hrv, sleepDuration: nil, formatter: f)
        #expect(d.detail == "68 ms · baseline 61")
        #expect(d.points == "+14")
        #expect(d.fraction == 0.7)
        let temp = RecoveryFactor(kind: .wristTemperature, value: 36.7, baseline: 36.49, points: -3, isAvailable: true)
        let t = RecoveryPresentation.factor(temp, sleepDuration: nil, formatter: f)
        #expect(t.points == "\u{2212}3")
        #expect(t.isNegative)
        #expect(t.detail.contains("above baseline"))
        let missing = RecoveryFactor(kind: .respiratoryRate, value: nil, baseline: nil, points: 0, isAvailable: false)
        #expect(RecoveryPresentation.factor(missing, sleepDuration: nil, formatter: f).detail == "Not recorded")
    }

    @Test func calibrationText() {
        let score = RecoveryScore(value: 60, band: .yellow, factors: [], suggestion: .maintain, message: "", suggestedStrain: 40...60,
                                  signalsUsed: 2, signalsTotal: 5, calibrationDaysRemaining: 4)
        #expect(RecoveryPresentation.calibrationText(score) == "Calibrating · 4 more nights")
        #expect(RecoveryPresentation.average([60, 70, 80]) == 70)
        #expect(RecoveryPresentation.average([]) == nil)
    }

    @Test func zoneRows() {
        let zones = HeartRateZones(maxHeartRate: 190, source: .estimated, zones: (1...5).map {
            HeartRateZone(number: $0, name: HeartRateZone.names[$0 - 1], lowerBound: 90 + $0 * 10, upperBound: 99 + $0 * 10)
        })
        let rows = StrainPresentation.zoneRows(durations: ZoneDurations(seconds: [600, 1800, 0, 0, 0]), zones: zones, formatter: f)
        #expect(rows.count == 5)
        #expect(rows[1].duration == "30m")
        #expect(rows[1].relativeFraction == 1)
        #expect(abs(rows[0].fraction - 0.25) < 0.0001)
        #expect(StrainPresentation.riskName(.productive) == "Productive")
    }

    private func series(_ metric: HealthMetric, values: [Double], baseline: Baseline?) -> MetricSeries {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = values.enumerated().map { TimeSeriesPoint(interval: DateInterval(start: start.addingTimeInterval(Double($0.offset) * 86_400), duration: 86_400), value: $0.element) }
        return MetricSeries(metric: metric, range: .month, interval: DateInterval(start: start, duration: 30 * 86_400), points: points,
                            average: values.reduce(0, +) / Double(values.count), minimum: values.min(), maximum: values.max(),
                            baseline: baseline, latest: MetricSample(date: start, value: values.last ?? 0), sourceName: "Apple Watch")
    }

    @Test func metricUnitsForEveryMetric() {
        let base = Baseline(mean: 60, standardDeviation: 5, sampleCount: 30)
        for m in HealthMetric.allCases {
            let d = MetricPresentation.display(series(m, values: [58, 60, 62], baseline: base), formatter: f)
            #expect(d.points.count == 3)
            #expect(d.average != nil)
            #expect(!d.unit.isEmpty)
            #expect(d.band != nil)
        }
    }

    @Test func wristTemperatureIsDeviation() {
        let base = Baseline(mean: 36.5, standardDeviation: 0.1, sampleCount: 30)
        let d = MetricPresentation.display(series(.wristTemperature, values: [36.4, 36.6], baseline: base), formatter: f)
        #expect(abs(d.points[1].value - 0.1) < 0.0001)
        #expect(d.average?.value == "0.00")
        #expect(d.unit == "°C")
        let dF = MetricPresentation.display(series(.wristTemperature, values: [36.4, 36.6], baseline: base), formatter: lb)
        #expect(dF.unit == "°F")
    }

    @Test func bodyMassFollowsUnits() {
        let d = MetricPresentation.display(series(.bodyMass, values: [80, 80], baseline: nil), formatter: lb)
        #expect(d.unit == "lb")
        #expect(abs(d.points[0].value - 176.37) < 0.1)
        #expect(d.band == nil)
    }

    @Test func chartScaleAndDownsample() {
        #expect(TodayChartScale.domain(values: [], band: nil) == nil)
        let d = TodayChartScale.domain(values: [10, 20], band: 5...25)!
        #expect(d.lowerBound < 5 && d.upperBound > 25)
        let points = (0..<1000).map { TodayChartPoint(date: Date(timeIntervalSince1970: Double($0)), value: Double($0)) }
        let thinned = TodayChartScale.downsample(points)
        #expect(thinned.count == TodayChartScale.maxPoints)
        #expect(thinned.last == points.last)
    }
}
