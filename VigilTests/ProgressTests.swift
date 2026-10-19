import Foundation
import Testing
@testable import Vigil

@Suite("ProgressAggregation")
struct ProgressAggregationTests {
    let calendar = TestSupport.utc
    let today = LocalDay(year: 2026, month: 10, day: 19)

    @Test func weekStartsEndOnToday() {
        let starts = ProgressAggregation.weekStarts(weeks: 4, endingOn: today, calendar: calendar)
        #expect(starts.count == 4)
        #expect(starts.last == today.adding(days: -6, calendar: calendar))
        #expect(starts.first == today.adding(days: -27, calendar: calendar))
    }

    @Test func weeklySumsBucketByDay() {
        let first = ProgressAggregation.weekStarts(weeks: 2, endingOn: today, calendar: calendar)[0]
        let items: [(day: LocalDay, value: Double)] = [
            (first, 5), (first.adding(days: 6, calendar: calendar), 3), (today, 10),
            (first.adding(days: -1, calendar: calendar), 99), // before range
        ]
        #expect(ProgressAggregation.weeklySums(items, first: first, count: 2, calendar: calendar) == [8, 10])
    }

    @Test func weeklyMeansLeaveEmptyWeeksNil() {
        let first = ProgressAggregation.weekStarts(weeks: 2, endingOn: today, calendar: calendar)[0]
        let means = ProgressAggregation.weeklyMeans([(today, 4), (today, 6)], first: first, count: 2, calendar: calendar)
        #expect(means[0] == nil)
        #expect(means[1] == 5)
    }

    @Test func fourWeekBlocksAlignToNewestAndDropLeadingPartial() {
        let weekly = Array(repeating: 10.0, count: 13)
        let blocks = ProgressAggregation.blocks(of: weekly)
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { $0.sum == 40 })
        #expect(ProgressAggregation.blocks(of: [1, 2, 3]).map(\.sum) == [6])
        #expect(ProgressAggregation.blocks(of: Array(repeating: 1, count: 52)).count == 13)
    }

    @Test func downsampleCapsPointCountAndKeepsMean() {
        let points = (0..<1000).map { ProgressPoint(date: Date(timeIntervalSince1970: Double($0) * 86_400), value: 2) }
        let reduced = ProgressAggregation.downsample(points, maxCount: 300)
        #expect(reduced.count <= 300)
        #expect(reduced.allSatisfy { $0.value == 2 })
        #expect(ProgressAggregation.downsample(Array(points.prefix(10)), maxCount: 300).count == 10)
    }

    @Test func dailyMeansAverageSamplesPerDay() {
        let noon = TestSupport.referenceDate
        let samples = [MetricSample(date: noon, value: 50), MetricSample(date: noon.addingTimeInterval(60), value: 60),
                       MetricSample(date: noon.addingTimeInterval(-86_400), value: 70)]
        let daily = ProgressAggregation.dailyMeans(samples, calendar: calendar)
        #expect(daily.map(\.value) == [70, 55])
        #expect(ProgressAggregation.change(daily) == -15)
        #expect(ProgressAggregation.change([]) == nil)
    }

    @Test func tickDatesPickFirstMiddleLast() {
        let dates = (0..<5).map { Date(timeIntervalSince1970: Double($0)) }
        #expect(ProgressAggregation.tickDates(dates) == [dates[0], dates[2], dates[4]])
        #expect(ProgressAggregation.tickDates([]).isEmpty)
    }

    @Test func heatmapMarksKindsAndFuture() {
        var cal = calendar
        cal.firstWeekday = 2 // Monday; 19 Oct 2026 is a Monday
        let kinds: [LocalDay: Set<WorkoutKind>] = [
            today: [.run, .strength],
            today.adding(days: -1, calendar: cal): [.strength],
            today.adding(days: -2, calendar: cal): [.run],
        ]
        let map = ProgressAggregation.heatmap(workoutKinds: kinds, weeks: 2, today: today, calendar: cal)
        #expect(map.columns.count == 2)
        #expect(map.columns.allSatisfy { $0.count == 7 })
        #expect(map.columns[1][0].day == today)
        #expect(map.columns[1][0].kind == .both)
        #expect(map.columns[1][1].kind == .future)
        #expect(map.columns[0][6].kind == .lift)
        #expect(map.columns[0][5].kind == .run)
        #expect(map.trainingDays == 3)
    }

    @Test func loadRatiosSkipDaysWithoutChronicLoad() {
        let history = [TrainingLoadPoint(day: today, acute: 10, chronic: 0), TrainingLoadPoint(day: today.adding(days: 1, calendar: calendar), acute: 12, chronic: 10)]
        let ratios = ProgressAggregation.loadRatios(history, calendar: calendar)
        #expect(ratios.count == 1)
        #expect(ratios[0].value == 1.2)
    }
}

@MainActor
@Suite("ProgressModels")
struct ProgressModelTests {
    func container(_ scenario: MockScenario = .standard) -> AppContainer {
        AppContainer(configuration: LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory, skipOnboarding: true, resetData: false),
                     calendar: TestSupport.utc, now: { TestSupport.referenceDate })
    }

    @Test func runningContentRespectsRangeAndUnits() async throws {
        let c = container()
        let metric = try await ProgressRunningModel.buildContent(repository: c.repository, range: .threeMonths, formatter: VigilFormatter(units: .metric, locale: TestSupport.enUS))
        let imperial = try await ProgressRunningModel.buildContent(repository: c.repository, range: .threeMonths, formatter: VigilFormatter(units: .imperial, locale: TestSupport.enUS))
        #expect(metric.weeklyBars.count == 13)
        #expect(metric.total.unit == "km")
        #expect(imperial.total.unit == "mi")
        let km = metric.weeklyBars.reduce(0) { $0 + $1.value }
        let mi = imperial.weeklyBars.reduce(0) { $0 + $1.value }
        #expect(abs(km / 1.609344 - mi) < 0.001)
        #expect(metric.weeklyGoal == 25)
    }

    @Test func oneYearLoadsQuicklyAndIsDownsampled() async throws {
        let c = container()
        let clock = ContinuousClock()
        var content: ProgressRunningContent?
        let elapsed = try await clock.measure {
            content = try await ProgressRunningModel.buildContent(repository: c.repository, range: .oneYear, formatter: VigilFormatter(locale: TestSupport.enUS))
        }
        #expect(content?.weeklyBars.count == 52)
        #expect((content?.load?.ratios.count ?? 0) <= 300)
        #expect(elapsed < .seconds(3))
    }

    @Test func personalBestRowsListEveryCategory() {
        let id = UUID()
        let best = PersonalBest(category: .fiveKilometers, duration: 1562, distanceMeters: 5000, date: TestSupport.referenceDate, workoutID: id, isNew: true)
        let rows = ProgressRunningModel.personalBestRows([best], formatter: VigilFormatter(locale: TestSupport.enUS), today: LocalDay(TestSupport.referenceDate, calendar: TestSupport.utc), calendar: TestSupport.utc)
        #expect(rows.count == PersonalBestCategory.allCases.count)
        let five = rows.first { $0.category == .fiveKilometers }
        #expect(five?.valueText == "26:02")
        #expect(five?.isNew == true)
        #expect(five?.workoutID == id)
        #expect(rows.first { $0.category == .marathon }?.workoutID == nil)
    }

    @Test func liftingContentCountsSessions() async throws {
        let c = container()
        let content = try await ProgressLiftingModel.buildContent(repository: c.repository, range: .threeMonths)
        #expect(content.sessions.count == 13)
        #expect(Int(content.sessions.reduce(0) { $0 + $1.value }) == content.totalSessions)
        #expect(content.heatmap.columns.count == 13)
    }

    @Test func bodyContentConvertsWeightToDisplayUnits() async throws {
        let c = container()
        let metric = try await ProgressBodyModel.buildContent(repository: c.repository, range: .threeMonths, formatter: VigilFormatter(units: .metric, locale: TestSupport.enUS))
        let imperial = try await ProgressBodyModel.buildContent(repository: c.repository, range: .threeMonths, formatter: VigilFormatter(units: .imperial, locale: TestSupport.enUS))
        let kg = try #require(metric.cards.first { $0.metric == .bodyMass }?.points.last?.value)
        let lb = try #require(imperial.cards.first { $0.metric == .bodyMass }?.points.last?.value)
        #expect(abs(kg / 0.45359237 - lb) < 0.01)
    }

    @Test func emptyScenarioProducesNoCards() async throws {
        let c = container(.empty)
        let content = try await ProgressBodyModel.buildContent(repository: c.repository, range: .fourWeeks, formatter: VigilFormatter(locale: TestSupport.enUS))
        #expect(content.cards.isEmpty)
        #expect(content.recoveryLoad.isEmpty)
    }
}
