import Foundation
import Observation

/// Loading phase shared by the Progress segment models.
enum ProgressPhase: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

/// Pace-at-similar-heart-rate card.
struct ProgressPaceContent: Hashable, Sendable {
    /// Weekly normalised pace in display units (seconds per km or mile), oldest first.
    var points: [ProgressPoint]
    var latest: FormattedValue
    /// "12 s/km faster", nil without enough runs.
    var changeText: String?
    var isFaster: Bool?
    var referenceHeartRate: Int
}

/// VO₂ max card.
struct ProgressVO2Content: Hashable, Sendable {
    var points: [ProgressPoint]
    var latest: FormattedValue
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

/// Everything on Progress → Running that depends on the selected range.
struct ProgressRunningContent: Hashable, Sendable {
    var weeklyBars: [ProgressBar]
    var monthlyBars: [ProgressBar]
    /// Goals in display units (km / mi).
    var weeklyGoal: Double
    var monthlyGoal: Double
    var total: FormattedValue
    var averagePerWeek: FormattedValue
    var runCount: Int
    var tickDates: [Date]
    var pace: ProgressPaceContent?
    var vo2: ProgressVO2Content?
    var load: ProgressLoadContent?
}

/// Screen model for Progress → Running.
@MainActor
@Observable
final class ProgressRunningModel {
    private(set) var phase: ProgressPhase = .loading
    private(set) var content: ProgressRunningContent?
    private(set) var personalBests: [ProgressPersonalBestRow]?
    var period: ProgressPeriod = .weekly

    func load(repository: VigilRepository, range: ProgressRange, formatter: VigilFormatter) async {
        if content == nil { phase = .loading }
        do {
            content = try await Self.buildContent(repository: repository, range: range, formatter: formatter)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if content == nil { phase = .failed }
        }
    }

    /// Personal bests cover a fixed year, so they load once per screen model (and when units change).
    func loadPersonalBests(repository: VigilRepository, formatter: VigilFormatter) async {
        guard let bests = try? await repository.personalBests() else {
            if personalBests == nil { personalBests = Self.personalBestRows([], formatter: formatter, today: repository.today, calendar: repository.calendar) }
            return
        }
        personalBests = Self.personalBestRows(bests, formatter: formatter, today: repository.today, calendar: repository.calendar)
    }

    // MARK: Building

    static func buildContent(repository: VigilRepository, range: ProgressRange, formatter: VigilFormatter) async throws -> ProgressRunningContent {
        let calendar = repository.calendar
        let today = repository.today
        let weeks = range.weeks
        let interval = range.interval(endingOn: today, calendar: calendar)
        let starts = ProgressAggregation.weekStarts(weeks: weeks, endingOn: today, calendar: calendar)
        let first = starts[0]

        let runs = try await repository.dataSource.workouts(in: interval, kinds: [.run])
        let weeklyMeters = ProgressAggregation.weeklySums(
            runs.map { (LocalDay($0.start, calendar: calendar), $0.distanceMeters ?? 0) }, first: first, count: weeks, calendar: calendar)
        let weeklyBars = weeklyMeters.enumerated().map { index, meters in
            ProgressBar(id: index, start: starts[index].startDate(in: calendar), value: formatter.displayDistance(meters: meters))
        }
        let monthlyBars = ProgressAggregation.blocks(of: weeklyMeters).enumerated().map { index, block in
            ProgressBar(id: index, start: starts[block.firstWeek].startDate(in: calendar), value: formatter.displayDistance(meters: block.sum))
        }
        let totalMeters = weeklyMeters.reduce(0, +)
        let goalMeters = repository.settings.settings.goals.weeklyRunDistanceMeters

        let pace = try await paceContent(repository: repository, weeks: weeks, today: today, formatter: formatter)
        let vo2 = await vo2Content(repository: repository, interval: interval, formatter: formatter)
        let load = try? await loadContent(repository: repository, weeks: weeks, today: today)

        return ProgressRunningContent(
            weeklyBars: weeklyBars, monthlyBars: monthlyBars,
            weeklyGoal: formatter.displayDistance(meters: goalMeters), monthlyGoal: formatter.displayDistance(meters: goalMeters * 4),
            total: formatter.distance(meters: totalMeters, fractionDigits: 0),
            averagePerWeek: formatter.distance(meters: totalMeters / Double(weeks), fractionDigits: 1),
            runCount: runs.count,
            tickDates: ProgressAggregation.tickDates(weeklyBars.map(\.start)),
            pace: pace, vo2: vo2, load: load)
    }

    private static func paceContent(repository: VigilRepository, weeks: Int, today: LocalDay, formatter: VigilFormatter) async throws -> ProgressPaceContent? {
        guard let trend = try await repository.aerobicEfficiency(endingOn: today, weeks: weeks), trend.points.count >= 2,
              let last = trend.points.last else { return nil }
        let calendar = repository.calendar
        let points = trend.points.map {
            ProgressPoint(date: $0.weekStart.startDate(in: calendar), value: formatter.displayPace(secondsPerKilometer: $0.paceSecondsPerKilometer))
        }
        var changeText: String?
        var isFaster: Bool?
        if let change = trend.paceChangeSecondsPerKilometer, abs(change) >= 1 {
            let amount = formatter.paceDifference(secondsPerKilometer: change).text
            isFaster = change < 0
            changeText = change < 0 ? String(localized: "\(amount) faster") : String(localized: "\(amount) slower")
        }
        return ProgressPaceContent(points: points, latest: formatter.pace(secondsPerKilometer: last.paceSecondsPerKilometer),
                                   changeText: changeText, isFaster: isFaster, referenceHeartRate: Int(trend.referenceHeartRate.rounded()))
    }

    private static func vo2Content(repository: VigilRepository, interval: DateInterval, formatter: VigilFormatter) async -> ProgressVO2Content? {
        guard let samples = try? await repository.dataSource.samples(of: .vo2Max, in: interval), !samples.isEmpty else { return nil }
        let calendar = repository.calendar
        let daily = ProgressAggregation.dailyMeans(samples, calendar: calendar)
        guard let latest = daily.last, let firstPoint = daily.first else { return nil }
        let points = ProgressAggregation.downsample(daily)
        return ProgressVO2Content(points: points, latest: formatter.vo2Max(latest.value),
                                  change: ProgressAggregation.change(daily), since: firstPoint.date)
    }

    private static func loadContent(repository: VigilRepository, weeks: Int, today: LocalDay) async throws -> ProgressLoadContent {
        let load = try await repository.trainingLoad(endingOn: today, historyDays: weeks * 7)
        let ratios = ProgressAggregation.downsample(ProgressAggregation.loadRatios(load.history, calendar: repository.calendar))
        return ProgressLoadContent(ratios: ratios, current: load.ratio, risk: load.risk)
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
