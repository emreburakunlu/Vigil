import Foundation
import Observation

/// Loading phase shared by the Progress segment models.
enum ProgressPhase: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

/// Pace-at-similar-heart-rate card. Values are canonical (seconds per km); views format them.
struct ProgressPaceContent: Hashable, Sendable {
    /// Weekly normalised pace in seconds per km, oldest first.
    var points: [ProgressPoint]
    var latestSecondsPerKilometer: Double
    /// Change in seconds per km (negative = faster); nil without enough runs.
    var changeSecondsPerKilometer: Double?
    var referenceHeartRate: Int
}

/// VO₂ max card (ml/kg/min, the same in every unit system).
struct ProgressVO2Content: Hashable, Sendable {
    var points: [ProgressPoint]
    var latest: Double
    /// Change since the first sample in the range.
    var change: Double?
    var since: Date
}

/// Training-load card.
struct ProgressLoadContent: Hashable, Sendable {
    /// Acute ÷ chronic per day (at most ~300 points).
    var ratios: [ProgressPoint]
    var current: Double?
    var risk: TrainingLoadRisk
}

/// One row of the Personal bests card.
struct ProgressPersonalBestRow: Hashable, Sendable, Identifiable {
    var category: PersonalBestCategory
    var name: String
    var date: Date?
    var valueText: String?
    var isNew: Bool
    var workoutID: UUID?
    var id: PersonalBestCategory { category }
}

/// Everything on Progress → Running that depends on the selected range. Distances are in metres and
/// paces in seconds per km: changing the unit system only re-formats, it never reloads.
struct ProgressRunningContent: Hashable, Sendable {
    /// Metres per week.
    var weeklyBars: [ProgressBar]
    /// Metres per calendar month (whole months overlapping the range).
    var monthlyBars: [ProgressBar]
    var weeklyGoalMeters: Double
    var monthlyGoalMeters: Double
    var totalMeters: Double
    var weekCount: Int
    var runCount: Int
    var tickDates: [Date]
    var monthTickDates: [Date]
    var pace: ProgressPaceContent?
    var vo2: ProgressVO2Content?
    var load: ProgressLoadContent?

    var averageMetersPerWeek: Double { totalMeters / Double(max(weekCount, 1)) }
}

/// Screen model for Progress → Running.
@MainActor
@Observable
final class ProgressRunningModel {
    private(set) var phase: ProgressPhase = .loading
    private(set) var content: ProgressRunningContent?
    /// Canonical personal bests; nil until loaded (empty when unavailable).
    private(set) var personalBests: [PersonalBest]?
    var period: ProgressPeriod = .weekly

    func load(repository: VigilRepository, range: ProgressRange) async {
        if content == nil { phase = .loading }
        do {
            let built = try await Self.buildContent(repository: repository, range: range)
            guard !Task.isCancelled else { return }
            content = built
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if content == nil { phase = .failed }
        }
    }

    /// Personal bests cover a fixed year, so they depend on new data only (not on the range or the units).
    func loadPersonalBests(repository: VigilRepository) async {
        let bests = try? await repository.personalBests()
        guard !Task.isCancelled else { return }
        if let bests { personalBests = bests } else if personalBests == nil { personalBests = [] }
    }

    // MARK: Building

    static func buildContent(repository: VigilRepository, range: ProgressRange) async throws -> ProgressRunningContent {
        let calendar = repository.calendar
        let today = repository.today
        let weeks = range.weeks
        let interval = range.interval(endingOn: today, calendar: calendar)
        let starts = ProgressAggregation.weekStarts(weeks: weeks, endingOn: today, calendar: calendar)
        let first = starts[0]
        let months = ProgressAggregation.monthStarts(from: first, through: today)
        // Whole calendar months for the Monthly toggle, so fetch from the start of the first one (a single query).
        let fetchInterval = LocalDay.interval(from: months.first ?? first, through: today, calendar: calendar)
        let source = repository.dataSource

        async let fetchedRuns = source.workouts(in: fetchInterval, kinds: [.run])
        async let vo2Samples = try? source.samples(of: .vo2Max, in: interval)
        async let loadHistory = try? repository.trainingLoad(endingOn: today, historyDays: weeks * 7)
        let runs = try await fetchedRuns

        let items = runs.map { (LocalDay($0.start, calendar: calendar), $0.distanceMeters ?? 0) }
        let weeklyMeters = ProgressAggregation.weeklySums(items, first: first, count: weeks, calendar: calendar)
        let monthlyMeters = ProgressAggregation.monthlySums(items, months: months)
        let weeklyBars = weeklyMeters.enumerated().map { index, meters in
            ProgressBar(id: index, start: starts[index].startDate(in: calendar), value: meters)
        }
        let monthlyBars = monthlyMeters.enumerated().map { index, meters in
            ProgressBar(id: index, start: months[index].startDate(in: calendar), value: meters)
        }
        let goalMeters = repository.settings.settings.goals.weeklyRunDistanceMeters

        let pace = paceContent(repository: repository, runs: runs, weeks: weeks, today: today)
        let vo2 = vo2Content(samples: await vo2Samples, calendar: calendar)
        let load = await loadHistory.map { loadContent($0, calendar: calendar) }

        return ProgressRunningContent(
            weeklyBars: weeklyBars, monthlyBars: monthlyBars,
            weeklyGoalMeters: goalMeters, monthlyGoalMeters: goalMeters * 52 / 12,
            totalMeters: weeklyMeters.reduce(0, +), weekCount: weeks,
            runCount: runs.filter { interval.contains($0.start) }.count,
            tickDates: ProgressAggregation.tickDates(weeklyBars.map(\.start)),
            monthTickDates: ProgressAggregation.tickDates(monthlyBars.map(\.start)),
            pace: pace, vo2: vo2, load: load)
    }

    private static func paceContent(repository: VigilRepository, runs: [Workout], weeks: Int, today: LocalDay) -> ProgressPaceContent? {
        guard let trend = repository.aerobicEfficiency(runs: runs, endingOn: today, weeks: weeks), trend.points.count >= 2,
              let last = trend.points.last else { return nil }
        let calendar = repository.calendar
        let points = trend.points.map {
            ProgressPoint(date: $0.weekStart.startDate(in: calendar), value: $0.paceSecondsPerKilometer)
        }
        return ProgressPaceContent(points: points, latestSecondsPerKilometer: last.paceSecondsPerKilometer,
                                   changeSecondsPerKilometer: trend.paceChangeSecondsPerKilometer,
                                   referenceHeartRate: Int(trend.referenceHeartRate.rounded()))
    }

    private static func vo2Content(samples: [MetricSample]?, calendar: Calendar) -> ProgressVO2Content? {
        guard let samples, !samples.isEmpty else { return nil }
        let daily = ProgressAggregation.dailyMeans(samples, calendar: calendar)
        guard let latest = daily.last, let firstPoint = daily.first else { return nil }
        return ProgressVO2Content(points: ProgressAggregation.downsample(daily), latest: latest.value,
                                  change: ProgressAggregation.change(daily), since: firstPoint.date)
    }

    private static func loadContent(_ load: TrainingLoad, calendar: Calendar) -> ProgressLoadContent {
        let ratios = ProgressAggregation.downsample(ProgressAggregation.loadRatios(load.history, calendar: calendar))
        return ProgressLoadContent(ratios: ratios, current: load.ratio, risk: load.risk)
    }

    /// "12 s/km faster" / "12 s/km slower"; nil when the change is under a second.
    static func paceChangeText(_ change: Double?, formatter: VigilFormatter) -> (text: String, isFaster: Bool)? {
        guard let change, abs(change) >= 1 else { return nil }
        let amount = formatter.paceDifference(secondsPerKilometer: change).text
        return (change < 0 ? String(localized: "\(amount) faster") : String(localized: "\(amount) slower"), change < 0)
    }

    static func personalBestRows(_ bests: [PersonalBest], formatter: VigilFormatter, today: LocalDay, calendar: Calendar) -> [ProgressPersonalBestRow] {
        PersonalBestCategory.allCases.map { category in
            let name = Self.name(of: category)
            guard let best = bests.first(where: { $0.category == category }) else {
                return ProgressPersonalBestRow(category: category, name: name, date: nil, valueText: nil, isNew: false, workoutID: nil)
            }
            let value: String
            if let duration = best.duration {
                value = VigilFormatter.duration(duration, style: .clock)
            } else {
                value = formatter.distance(meters: best.distanceMeters, fractionDigits: 1).text
            }
            return ProgressPersonalBestRow(category: category, name: name, date: best.date, valueText: value,
                                           isNew: best.isNew, workoutID: best.workoutID)
        }
    }

    static func name(of category: PersonalBestCategory) -> String {
        switch category {
        case .oneKilometer: String(localized: "Fastest 1K")
        case .fiveKilometers: String(localized: "Fastest 5K")
        case .tenKilometers: String(localized: "Fastest 10K")
        case .halfMarathon: String(localized: "Half marathon")
        case .marathon: String(localized: "Marathon")
        case .longestRun: String(localized: "Longest run")
        }
    }

    /// Plain-English label for a training-load risk band.
    static func riskTitle(_ risk: TrainingLoadRisk) -> String {
        switch risk {
        case .detraining: String(localized: "Detraining")
        case .productive: String(localized: "Productive")
        case .caution: String(localized: "Building fast")
        case .high: String(localized: "Too much, too fast")
        }
    }
}
