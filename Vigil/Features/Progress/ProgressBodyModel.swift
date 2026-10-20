import Foundation
import Observation

/// One trend card on Progress → Body.
struct ProgressBodyCard: Hashable, Sendable, Identifiable {
    var metric: HealthMetric
    /// Daily means in canonical units (kg, bpm, ms), at most ~300 points. Views convert for display.
    var points: [ProgressPoint]
    var latest: Double
    /// Change from the first to the last day, canonical units.
    var change: Double?
    /// Whether the change is good (true), bad (false) or neutral/unknown (nil).
    var changeIsGood: Bool?
    /// 30-day baseline band in canonical units.
    var band: ClosedRange<Double>?
    var id: HealthMetric { metric }
}

/// A day on the Recovery vs. training load chart.
struct ProgressRecoveryLoadDay: Hashable, Sendable, Identifiable {
    var date: Date
    /// Recovery 0–100, nil when not computed.
    var recovery: Double?
    /// Daily training load scaled to 0–100 against the busiest day shown.
    var load: Double
    var id: Date { date }
}

struct ProgressBodyContent: Hashable, Sendable {
    /// Weight, resting HR, HRV; metrics without samples are omitted.
    var cards: [ProgressBodyCard]
    var tickDates: [Date]
    var recoveryLoad: [ProgressRecoveryLoadDay]
    var recoveryLoadTicks: [Date]
}

/// Screen model for Progress → Body.
@MainActor
@Observable
final class ProgressBodyModel {
    private(set) var phase: ProgressPhase = .loading
    private(set) var content: ProgressBodyContent?

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

    static let metrics: [HealthMetric] = [.bodyMass, .restingHeartRate, .heartRateVariability]

    static func buildContent(repository: VigilRepository, range: ProgressRange) async throws -> ProgressBodyContent {
        let calendar = repository.calendar
        let today = repository.today
        let interval = range.interval(endingOn: today, calendar: calendar)
        let baselines = repository.summaries.latest()?.baselines

        var cards: [ProgressBodyCard] = []
        for metric in metrics {
            let samples = try await repository.dataSource.samples(of: metric, in: interval)
            let daily = ProgressAggregation.dailyMeans(samples, calendar: calendar)
            guard let last = daily.last else { continue }
            let change = ProgressAggregation.change(daily)
            let band = baselines?[metric].flatMap { $0.isEstablished ? $0.normalRange.lowerBound...$0.normalRange.upperBound : nil }
            var isGood: Bool?
            if let change, let better = metric.higherIsBetter, abs(change) > 0 { isGood = (change > 0) == better }
            cards.append(ProgressBodyCard(metric: metric, points: ProgressAggregation.downsample(daily), latest: last.value,
                                          change: change, changeIsGood: isGood, band: band))
        }

        // Recovery vs. load: cached summaries only (≈ 90 days), capped to the range.
        let days = min(range.weeks * 7, 90)
        let start = today.adding(days: -(days - 1), calendar: calendar)
        let summaries = (try? await repository.ensuredSummaries(from: start, through: today)) ?? []
        let maxLoad = max(summaries.compactMap { $0.strain?.trainingLoad }.max() ?? 0, 1)
        // Days with neither a recovery score nor training are empty placeholders, not data.
        let recoveryLoad = summaries.filter { $0.recovery != nil || ($0.strain?.trainingLoad ?? 0) > 0 }.map {
            ProgressRecoveryLoadDay(date: $0.day.startDate(in: calendar), recovery: $0.recovery.map { Double($0.value) },
                                    load: ($0.strain?.trainingLoad ?? 0) / maxLoad * 100)
        }
        return ProgressBodyContent(cards: cards, tickDates: ProgressAggregation.tickDates(cards.first?.points.map(\.date) ?? []),
                                   recoveryLoad: recoveryLoad, recoveryLoadTicks: ProgressAggregation.tickDates(recoveryLoad.map(\.date)))
    }

    static func changeText(_ metric: HealthMetric, _ change: Double, _ formatter: VigilFormatter) -> String {
        switch metric {
        case .bodyMass: formatter.weightChange(kilograms: change).text
        case .heartRateVariability: FormattedValue(value: formatter.signed(change, fractionDigits: 0), unit: "ms").text
        default: FormattedValue(value: formatter.signed(change, fractionDigits: 0), unit: "bpm").text
        }
    }
}
