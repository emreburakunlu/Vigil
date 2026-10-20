import Foundation
import Observation

/// What a night screen is showing.
enum SleepPhase: Equatable, Sendable {
    case loading
    case loaded(SleepNightPresentation)
    /// No primary night recorded for the day.
    case empty
    case failed
}

/// A sleep-domain insight ready to show.
struct SleepInsightItem: Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var systemImage: String

    static func make(from insights: [Insight], limit: Int = 3) -> [SleepInsightItem] {
        insights
            .filter { $0.domain == .sleep }
            .sorted { $0.priority > $1.priority }
            .prefix(limit)
            .map { SleepInsightItem(id: $0.id, text: $0.text, systemImage: icon(forRule: $0.id)) }
    }

    static func icon(forRule id: String) -> String {
        if id.hasPrefix("sleep.bedtime") { return "clock" }
        if id.hasPrefix("sleep.earlyBedtime") { return "sun.max" }
        if id.hasPrefix("sleep.restDay") { return "chart.line.uptrend.xyaxis" }
        if id.hasPrefix("sleep.lateWorkout") { return "figure.run" }
        if id.hasPrefix("sleep.goodStreak") { return "star" }
        return "sparkles"
    }
}

/// Sleep tab model: the selected night, debt, insights and the 7/30/90-day trends.
@MainActor
@Observable
final class SleepModel {
    private(set) var phase: SleepPhase = .loading
    private(set) var debt: SleepDebt?
    private(set) var insights: [SleepInsightItem] = []
    private(set) var chart: SleepTrendChart?
    private(set) var history: [SleepNightSummary] = []

    var range: SleepTrendRange = .thirtyDays { didSet { rebuildChart() } }
    var metric: SleepTrendMetric = .duration { didSet { rebuildChart() } }

    private var points: [SleepTrendPoint] = []
    private var target: TimeInterval = 8 * 3600
    private var formatter = VigilFormatter()
    private var calendar = Calendar.current

    /// Loads the night, debt and insights for `day`.
    func loadNight(repository: VigilRepository, formatter: VigilFormatter, day: LocalDay) async {
        self.formatter = formatter
        calendar = repository.calendar
        phase = .loading
        do {
            async let debtResult = try? await repository.sleepDebt(endingOn: day)
            async let insightsResult = try? await repository.insights(for: day)
            let detail = try await repository.sleepNightDetail(endingOn: day)
            let loadedDebt = await debtResult
            let loadedInsights = await insightsResult ?? []
            if Task.isCancelled { return }
            debt = loadedDebt
            insights = SleepInsightItem.make(from: loadedInsights)
            if let detail {
                phase = .loaded(SleepNightPresentation(detail: detail, formatter: formatter, calendar: repository.calendar))
            } else {
                phase = .empty
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            phase = .failed
        }
    }

    /// Loads 90 days of history for the trends (once per day change of "today").
    func loadTrends(repository: VigilRepository, formatter: VigilFormatter) async {
        self.formatter = formatter
        calendar = repository.calendar
        target = repository.settings.settings.goals.sleepTarget
        let today = repository.today
        let start = today.adding(days: -(SleepTrendRange.ninetyDays.days - 1), calendar: repository.calendar)
        guard let trend = try? await repository.sleepTrend(from: start, through: today) else { return }
        if Task.isCancelled { return }
        history = trend.summaries
        points = SleepTrendChart.points(history: trend.summaries, nights: trend.nights, calendar: repository.calendar)
        rebuildChart()
    }

    private func rebuildChart() {
        guard !points.isEmpty else { return }
        chart = SleepTrendChart.make(points: points, range: range, metric: metric, target: target, calendar: calendar, formatter: formatter)
    }

    /// The latest day before `day` with a recorded night ("See the night before"); falls back to the previous day.
    func previousRecordedDay(before day: LocalDay) -> LocalDay {
        history.last { $0.day < day && $0.asleep != nil }?.day ?? day.adding(days: -1, calendar: calendar)
    }
}

/// Sleep Night screen model (any past night).
@MainActor
@Observable
final class SleepNightScreenModel {
    private(set) var phase: SleepPhase = .loading

    func load(repository: VigilRepository, formatter: VigilFormatter, day: LocalDay) async {
        phase = .loading
        do {
            let detail = try await repository.sleepNightDetail(endingOn: day)
            if Task.isCancelled { return }
            if let detail {
                phase = .loaded(SleepNightPresentation(detail: detail, formatter: formatter, calendar: repository.calendar))
            } else {
                phase = .empty
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            phase = .failed
        }
    }
}

/// Calendar screen model.
@MainActor
@Observable
final class SleepCalendarModel {
    private(set) var month: SleepCalendarMonth?
    private(set) var failed = false

    func load(repository: VigilRepository, first: LocalDay, selected: LocalDay?) async {
        failed = false
        let last = SleepCalendarMonth.lastOfMonth(first, calendar: repository.calendar)
        do {
            let history = try await repository.sleepHistory(from: first, through: last)
            if Task.isCancelled { return }
            month = SleepCalendarMonth(first: first, history: history, target: repository.settings.settings.goals.sleepTarget,
                                       today: repository.today, selected: selected, calendar: repository.calendar)
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
