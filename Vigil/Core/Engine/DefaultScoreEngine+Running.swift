import Foundation

extension DefaultScoreEngine {
    /// Tunable constants of personal bests and aerobic efficiency.
    enum Running {
        /// A personal best is "NEW" when set within this window before `asOf`.
        static let newWindow: TimeInterval = 7 * 86_400
        /// Aerobic efficiency: qualifying runs are at least this long / far.
        static let minimumDistance = 2_000.0
        static let minimumDuration: TimeInterval = 15 * 60
        /// Runs whose average HR is within ± this many bpm of the reference count as "similar HR".
        static let similarHeartRateWindow = 10.0
        static let minimumRuns = 4
        static let minimumSpanDays = 14.0
    }

    // MARK: Personal bests

    /// Personal bests across `runs`.
    ///
    /// Distance categories (1K, 5K, 10K, half, marathon) use the fastest contiguous segment of that
    /// distance inside any run's cumulative-distance timeline (`BestEffortFinder`, exact two-pointer
    /// search with interpolation, GPS spikes > 10 m/s capped). Runs without a timeline fall back to
    /// their average pace × distance when they are at least that long — a conservative estimate,
    /// since the fastest segment can never be slower than the run's average. Timelines ending up to
    /// 0.5 % short of a category (watch-measured "5K" that reads 4.98 km) count, scaled to the full distance.
    /// Longest run = greatest total distance. Ties go to the earlier run. `isNew` when the run started
    /// within the 7 days before `asOf` (and not after it).
    func personalBests(runs: [RunEffortInput], asOf: Date) -> [PersonalBest] {
        let newCutoff = asOf.addingTimeInterval(-Running.newWindow)
        let ordered = runs.filter { $0.workout.kind == .run }.sorted {
            ($0.workout.start, $0.workout.id.uuidString) < ($1.workout.start, $1.workout.id.uuidString)
        }
        struct Prepared {
            var workout: Workout
            var timeline: BestEffortFinder.Timeline?
            var distance: Double
        }
        let prepared: [Prepared] = ordered.compactMap { run in
            let timeline = run.cumulativeDistance.count >= 2 ? BestEffortFinder.timeline(from: run.cumulativeDistance) : nil
            let distance = max(run.workout.distanceMeters ?? 0, timeline?.totalDistance ?? 0)
            return distance > 0 ? Prepared(workout: run.workout, timeline: timeline, distance: distance) : nil
        }

        var bests: [PersonalBest] = []
        for category in PersonalBestCategory.allCases {
            var best: PersonalBest?
            for run in prepared {
                let isNew = run.workout.start >= newCutoff && run.workout.start <= asOf
                if let target = category.distanceMeters {
                    let time: TimeInterval?
                    if let timeline = run.timeline, timeline.totalDistance >= target * 0.995 {
                        time = BestEffortFinder.fastest(min(target, timeline.totalDistance), in: timeline)
                            .map { $0 * target / min(target, timeline.totalDistance) }
                    } else if run.distance >= target, run.workout.duration > 0 {
                        time = run.workout.duration * target / run.distance
                    } else {
                        time = nil
                    }
                    guard let time, time > 0 else { continue }
                    if best.map({ time < ($0.duration ?? .infinity) }) ?? true {
                        best = PersonalBest(category: category, duration: time, distanceMeters: target, date: run.workout.start,
                                            workoutID: run.workout.id, isNew: isNew)
                    }
                } else if best.map({ run.distance > $0.distanceMeters }) ?? true {
                    best = PersonalBest(category: category, duration: nil, distanceMeters: run.distance, date: run.workout.start,
                                        workoutID: run.workout.id, isNew: isNew)
                }
            }
            if let best { bests.append(best) }
        }
        return bests
    }

    // MARK: Aerobic efficiency

    /// Pace at a similar heart rate (aerobic efficiency) over the `weeks` weeks ending on `day`.
    ///
    /// 1. Qualifying runs: outdoor or indoor runs with average HR, ≥ 2 km and ≥ 15 min.
    /// 2. Reference HR = median average HR of those runs (rounded); only runs within ± 10 bpm are kept.
    /// 3. Each run's pace is normalised to the reference with the efficiency-factor ratio
    ///    (speed ∝ HR): pace × average HR ÷ reference HR.
    /// 4. Points: mean normalised pace per 7-day bucket ending on `day`.
    /// 5. Change: least-squares slope of normalised pace vs. days × the span from first to last run
    ///    (negative = faster). Needs ≥ 4 runs spanning ≥ 14 days; otherwise nil.
    func aerobicEfficiency(runs: [Workout], endingOn day: LocalDay, weeks: Int) -> AerobicEfficiencyTrend? {
        let weeks = max(1, weeks)
        let first = day.adding(days: -(weeks * 7 - 1), calendar: calendar)
        let candidates = runs.filter { run in
            let runDay = LocalDay(run.start, calendar: calendar)
            guard run.kind == .run, runDay >= first, runDay <= day,
                  let hr = run.averageHeartRate, hr.isFinite, hr > 0,
                  let distance = run.distanceMeters, distance >= Running.minimumDistance,
                  run.duration >= Running.minimumDuration else { return false }
            return true
        }
        guard candidates.count >= Running.minimumRuns,
              let median = EngineMath.median(candidates.compactMap(\.averageHeartRate)) else { return nil }
        let reference = median.rounded()
        struct Entry { var day: LocalDay; var offset: Double; var pace: Double }
        let entries: [Entry] = candidates.compactMap { run in
            guard let hr = run.averageHeartRate, abs(hr - reference) <= Running.similarHeartRateWindow,
                  let pace = run.averagePaceSecondsPerKilometer else { return nil }
            let runDay = LocalDay(run.start, calendar: calendar)
            return Entry(day: runDay, offset: Double(first.days(to: runDay, calendar: calendar)), pace: pace * hr / reference)
        }.sorted { ($0.offset, $0.pace) < ($1.offset, $1.pace) }
        guard entries.count >= Running.minimumRuns else { return nil }

        let points: [AerobicEfficiencyPoint] = (0..<weeks).compactMap { week in
            let bucket = entries.filter { Int($0.offset) / 7 == week }
            guard let mean = EngineMath.mean(bucket.map(\.pace)) else { return nil }
            return AerobicEfficiencyPoint(weekStart: first.adding(days: week * 7, calendar: calendar),
                                          paceSecondsPerKilometer: mean, runCount: bucket.count)
        }
        let span = (entries.last?.offset ?? 0) - (entries.first?.offset ?? 0)
        let change = span >= Running.minimumSpanDays
            ? EngineMath.slope(x: entries.map(\.offset), y: entries.map(\.pace)).map { $0 * span }
            : nil
        return AerobicEfficiencyTrend(referenceHeartRate: reference, points: points,
                                      paceChangeSecondsPerKilometer: change, runsUsed: entries.count)
    }
}
