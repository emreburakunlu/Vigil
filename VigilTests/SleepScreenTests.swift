import Foundation
import Testing
@testable import Vigil

@Suite("Sleep screens")
struct SleepScreenTests {
    var calendar: Calendar {
        var c = TestSupport.utc
        c.locale = TestSupport.enUS
        c.firstWeekday = 2
        return c
    }

    let t0 = TestSupport.referenceDate

    func seg(_ stage: SleepStage, _ startMin: Double, _ endMin: Double) -> SleepSegment {
        SleepSegment(stage: stage, start: t0.addingTimeInterval(startMin * 60), end: t0.addingTimeInterval(endMin * 60), source: nil)
    }

    @Test func hypnogramPlacesBarsAtTrueTimes() throws {
        let layout = try #require(SleepHypnogramLayout(segments: [seg(.awake, 0, 10), seg(.core, 10, 60), seg(.deep, 60, 100)]))
        #expect(layout.bars.count == 3)
        #expect(layout.bars[1].lane == 2)
        #expect(abs(layout.bars[1].start - 0.1) < 1e-9)
        #expect(abs(layout.bars[2].end - 1) < 1e-9)
        #expect(layout.links.map(\.toLane) == [2, 3])
        #expect(SleepHypnogramLayout(segments: []) == nil)
        #expect(SleepHypnogramLayout(segments: [seg(.inBed, 0, 60)]) == nil)
    }

    @Test func hypnogramTicksAreWholeHours() throws {
        let layout = try #require(SleepHypnogramLayout(segments: [seg(.core, 0, 480)]))
        let ticks = layout.ticks(calendar: calendar)
        #expect(!ticks.isEmpty)
        for tick in ticks {
            #expect(calendar.component(.minute, from: tick.date) == 0)
            #expect(calendar.component(.hour, from: tick.date) % 2 == 0)
        }
    }

    @Test func targetCaptionWording() {
        let f = VigilFormatter(units: .metric, locale: TestSupport.enUS)
        #expect(SleepFormat.targetCaption(difference: -18 * 60, target: 8 * 3600, formatter: f) == "18 min short of your 8h target")
        #expect(SleepFormat.targetCaption(difference: -70 * 60, target: 8 * 3600, formatter: f) == "1h 10m short of your 8h target")
        #expect(SleepFormat.targetCaption(difference: 20 * 60, target: 8 * 3600, formatter: f) == "20 min over your 8h target")
    }

    @Test func timesKeepLeadingZeroIn24HourLocales() {
        let gb = VigilFormatter(units: .metric, locale: Locale(identifier: "en_GB"))
        let us = VigilFormatter(units: .metric, locale: TestSupport.enUS)
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 7, minute: 4))!
        #expect(SleepFormat.time(early, formatter: gb, calendar: calendar) == "07:04")
        #expect(SleepFormat.time(early, formatter: us, calendar: calendar).contains("7:04"))
    }

    @Test func minutesAfterSixWrapsPastMidnight() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 0, minute: 30))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 22, minute: 58))!
        #expect(SleepFormat.minutesAfterSix(late, calendar: calendar) == 390)
        #expect(SleepFormat.minutesAfterSix(early, calendar: calendar) == 298)
    }

    func points(_ asleepHours: [Double?]) -> [SleepTrendPoint] {
        asleepHours.enumerated().map { i, h in
            SleepTrendPoint(day: LocalDay(year: 2026, month: 10, day: 1 + i), asleep: h.map { $0 * 3600 },
                            score: h.map { Int($0 * 10) }, bedtimeMinutes: h.map { _ in 300 + Double(i) * 10 },
                            wakeMinutes: h.map { _ in 780 + Double(i) * 10 })
        }
    }

    @Test func durationTrendAveragesAndSkipsMissing() {
        let f = VigilFormatter(units: .metric, locale: TestSupport.enUS)
        let chart = SleepTrendChart.make(points: points([7, nil, 8, 9]), range: .sevenDays, metric: .duration,
                                         target: 8 * 3600, calendar: calendar, formatter: f)
        #expect(chart.headline == "8h 00m")
        #expect(chart.bars.count == 4)
        #expect(chart.bars[1] == nil)
        #expect(chart.bars[0]?.tone == .shortOfTarget)
        #expect(chart.bars[2]?.tone == .metTarget)
        #expect(chart.ticks.count == 3)
    }

    @Test func consistencyHeadlineIsBedtimeSpread() {
        let f = VigilFormatter(units: .metric, locale: TestSupport.enUS)
        let chart = SleepTrendChart.make(points: points([8, 8, 8]), range: .sevenDays, metric: .consistency,
                                         target: 8 * 3600, calendar: calendar, formatter: f)
        // bedtimes 300, 310, 320 -> population SD ~8.16 min
        #expect(chart.headline == "± 8 min")
        #expect(chart.bars.allSatisfy { $0?.tone == .window })
    }

    @Test func emptyTrendHasPlaceholderHeadline() {
        let f = VigilFormatter(units: .metric, locale: TestSupport.enUS)
        let chart = SleepTrendChart.make(points: points([nil, nil]), range: .sevenDays, metric: .score,
                                         target: 8 * 3600, calendar: calendar, formatter: f)
        #expect(chart.headline == "–")
    }

    @Test func calendarMonthLayoutAndSummary() {
        let today = LocalDay(year: 2026, month: 10, day: 19)
        let history = [
            SleepNightSummary(day: LocalDay(year: 2026, month: 10, day: 1), asleep: 8 * 3600, score: 80),
            SleepNightSummary(day: LocalDay(year: 2026, month: 10, day: 2), asleep: 7 * 3600, score: 90),
            SleepNightSummary(day: LocalDay(year: 2026, month: 10, day: 3), asleep: nil, score: nil)
        ]
        let month = SleepCalendarMonth(first: LocalDay(year: 2026, month: 10, day: 9), history: history, target: 8 * 3600,
                                       today: today, selected: nil, calendar: calendar)
        // 1 Oct 2026 is a Thursday; Monday-first grid -> 3 blanks.
        #expect(month.cells.prefix(3).allSatisfy { $0.kind == .blank })
        #expect(month.cells.count == 3 + 31)
        #expect(month.summary.recordedNights == 2)
        #expect(month.summary.averageScore == 85)
        #expect(month.summary.nightsAtTarget == 1)
        #expect(month.summary.bestScore == 90)
        #expect(month.summary.bestDay == LocalDay(year: 2026, month: 10, day: 2))
        #expect(month.cells.last?.kind == .future)
        #expect(month.cells[5].kind == .missing)
    }

    @Test func insightsKeepSleepDomainOnly() {
        let items = SleepInsightItem.make(from: [
            Insight(id: "sleep.bedtimeSpread", domain: .sleep, text: "a", priority: 1),
            Insight(id: "recovery.hrvTrend", domain: .recovery, text: "b", priority: 9),
            Insight(id: "sleep.goodStreak", domain: .sleep, text: "c", priority: 5)
        ])
        #expect(items.map(\.text) == ["c", "a"])
    }
}
