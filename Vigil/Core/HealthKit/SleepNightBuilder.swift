import Foundation

/// One `HKCategorySample` of sleep analysis flattened to a Sendable value (input of `SleepNightBuilder`).
struct RawSleepSample: Hashable, Sendable {
    var stage: SleepStage
    var start: Date
    var end: Date
    var source: DataSourceInfo
    /// Higher wins where samples from different sources overlap (see `SleepSourcePriority`).
    var priority: Int

    init(stage: SleepStage, start: Date, end: Date, source: DataSourceInfo, priority: Int) {
        self.stage = stage
        self.start = start
        self.end = end
        self.source = source
        self.priority = priority
    }
}

/// Which source wins when sleep samples overlap.
enum SleepSourcePriority {
    /// Apple Watch: real stage data — always preferred.
    static let appleWatch = 30
    /// Third-party trackers (rings, bed sensors, sleep apps).
    static let thirdParty = 20
    /// Other Apple sources (iPhone sleep schedule / Health app).
    static let otherApple = 10
    /// Manually entered in Health.
    static let userEntered = 0

    static func priority(isAppleWatch: Bool, isAppleBundle: Bool, isUserEntered: Bool) -> Int {
        if isUserEntered { return userEntered }
        if isAppleWatch { return appleWatch }
        return isAppleBundle ? otherApple : thirdParty
    }
}

/// Turns raw sleep-analysis samples from any number of sources into `SleepNight`s. Pure and deterministic.
///
/// Algorithm:
///  1. **Timeline merge.** Stage samples (everything except `.inBed`) are cut into elementary intervals at
///     every sample boundary. Each interval takes the stage of the highest-priority covering sample
///     (Apple Watch > third party > iPhone > manual; ties → more specific stage: REM/core/deep > unspecified >
///     awake). Overlaps are therefore never double counted. Adjacent intervals with the same stage and
///     source are joined into one `SleepSegment`.
///  2. **Sessions.** Segments and in-bed samples are clustered; a gap longer than `sessionGap` (2 h) starts a
///     new session. Sessions with less than `minimumAsleep` asleep are dropped.
///  3. **Night shape.** `sleepStart`/`sleepEnd` = first/last asleep moment; awake outside that window is
///     dropped (it is sleep latency / lying in bed). The in-bed window is the union of in-bed samples and the
///     asleep window, or the asleep window alone when there are no in-bed samples.
///  4. **Day & primary.** A session belongs to `LocalDay(sleepEnd)` (the wake day). Per wake day the session
///     with the most sleep is primary, unless it is a *daytime nap* (asleep < `napMaximumAsleep`, started at
///     or after `napEarliestStartHour` and ended by `napLatestEndHour` on the same local day). All other
///     sessions are returned as naps (`isPrimary == false`).
///
/// All durations are absolute (`Date` arithmetic), so DST transitions never distort them; only the day
/// assignment and the nap wall-clock checks use `calendar`.
struct SleepNightBuilder: Sendable {
    var calendar: Calendar
    /// Gap that splits two sleep sessions.
    var sessionGap: TimeInterval = 2 * 3600
    /// Sessions with less sleep than this are ignored (noise, watch taken off).
    var minimumAsleep: TimeInterval = 10 * 60
    /// Longest sleep that can still be classified as a daytime nap.
    var napMaximumAsleep: TimeInterval = 3 * 3600
    /// Daytime window (local hours) for naps: start ≥ 10:00, end ≤ 20:00.
    var napEarliestStartHour = 10
    var napLatestEndHour = 20

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Nights whose wake-up (`sleepEnd`) falls in `[interval.start, interval.end)`, oldest first.
    func nights(from samples: [RawSleepSample], wakingIn interval: DateInterval) -> [SleepNight] {
        nights(from: samples).filter { $0.sleepEnd >= interval.start && $0.sleepEnd < interval.end }
    }

    /// All nights (primary and naps) found in `samples`, ordered by `sleepEnd`.
    func nights(from samples: [RawSleepSample]) -> [SleepNight] {
        let valid = samples.filter { $0.end > $0.start }
        let inBed = valid.filter { $0.stage == .inBed }
        let segments = Self.mergeTimeline(valid.filter { $0.stage != .inBed })
        let sessions = cluster(segments: segments, inBed: inBed)

        let candidates = sessions.compactMap(makeNight)
        let byDay = Dictionary(grouping: candidates.indices) { candidates[$0].day }
        var result = candidates
        for (day, indices) in byDay {
            let primaryIndex = indices
                .filter { !isDaytimeNap(candidates[$0]) }
                .max { lhs, rhs in
                    let a = candidates[lhs], b = candidates[rhs]
                    return a.asleepDuration == b.asleepDuration ? a.sleepEnd < b.sleepEnd : a.asleepDuration < b.asleepDuration
                }
            for index in indices {
                result[index].isPrimary = index == primaryIndex
                result[index].id = index == primaryIndex ? "\(day.isoString)-primary" : napID(day: day, start: result[index].sleepStart)
            }
        }
        return result.sorted { $0.sleepEnd < $1.sleepEnd }
    }

    // MARK: Timeline merge

    /// Merges overlapping stage samples into a non-overlapping, ordered timeline (see type docs, step 1).
    static func mergeTimeline(_ samples: [RawSleepSample]) -> [SleepSegment] {
        let sorted = samples.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        let boundaries = Array(Set(sorted.flatMap { [$0.start, $0.end] })).sorted()

        var segments: [SleepSegment] = []
        var active: [RawSleepSample] = []
        var next = 0
        for (from, to) in zip(boundaries, boundaries.dropFirst()) {
            active.removeAll { $0.end <= from }
            while next < sorted.count, sorted[next].start <= from {
                if sorted[next].end > from { active.append(sorted[next]) }
                next += 1
            }
            guard let winner = active.max(by: { wins($1, over: $0) }) else { continue }
            if var last = segments.last, last.end == from, last.stage == winner.stage, last.source == winner.source {
                last.end = to
                segments[segments.count - 1] = last
            } else {
                segments.append(SleepSegment(stage: winner.stage, start: from, end: to, source: winner.source))
            }
        }
        return segments
    }

    /// Strict ordering used to pick the visible sample: priority, then stage specificity, then a
    /// deterministic source-name tiebreak.
    static func wins(_ a: RawSleepSample, over b: RawSleepSample) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        if specificity(a.stage) != specificity(b.stage) { return specificity(a.stage) > specificity(b.stage) }
        if a.source.name != b.source.name { return a.source.name < b.source.name }
        return a.start < b.start
    }

    private static func specificity(_ stage: SleepStage) -> Int {
        switch stage {
        case .rem, .core, .deep: 3
        case .asleepUnspecified: 2
        case .awake: 1
        case .inBed: 0
        }
    }

    // MARK: Sessions

    private struct Session {
        var segments: [SleepSegment] = []
        var inBed: [RawSleepSample] = []
        var end: Date
    }

    private func cluster(segments: [SleepSegment], inBed: [RawSleepSample]) -> [Session] {
        enum Item { case segment(SleepSegment), inBed(RawSleepSample) }
        let items: [(start: Date, end: Date, item: Item)] =
            (segments.map { ($0.start, $0.end, Item.segment($0)) } + inBed.map { ($0.start, $0.end, Item.inBed($0)) })
            .sorted { $0.start < $1.start }

        var sessions: [Session] = []
        for entry in items {
            if sessions.isEmpty || entry.start.timeIntervalSince(sessions[sessions.count - 1].end) > sessionGap {
                sessions.append(Session(end: entry.end))
            }
            let index = sessions.count - 1
            switch entry.item {
            case .segment(let segment): sessions[index].segments.append(segment)
            case .inBed(let sample): sessions[index].inBed.append(sample)
            }
            sessions[index].end = max(sessions[index].end, entry.end)
        }
        return sessions
    }

    private func makeNight(_ session: Session) -> SleepNight? {
        let asleep = session.segments.filter(\.stage.isAsleep)
        guard let sleepStart = asleep.map(\.start).min(), let sleepEnd = asleep.map(\.end).max() else { return nil }

        let segments: [SleepSegment] = session.segments.compactMap { segment in
            let start = max(segment.start, sleepStart), end = min(segment.end, sleepEnd)
            guard end > start else { return nil }
            var clipped = segment
            clipped.start = start
            clipped.end = end
            return clipped
        }.sorted { $0.start < $1.start }

        var durations = SleepStageDurations()
        for segment in segments {
            switch segment.stage {
            case .awake: durations.awake += segment.duration
            case .rem: durations.rem += segment.duration
            case .core: durations.core += segment.duration
            case .deep: durations.deep += segment.duration
            case .asleepUnspecified: durations.unspecified += segment.duration
            case .inBed: break
            }
        }
        guard durations.asleep >= minimumAsleep else { return nil }

        // Count maximal awake runs (adjacent awake segments from different sources are one interruption).
        var interruptions = 0
        var previous: SleepSegment?
        for segment in segments {
            if segment.stage == .awake, !(previous?.stage == .awake && previous?.end == segment.start) {
                interruptions += 1
            }
            previous = segment
        }

        let inBedStart = min(session.inBed.map(\.start).min() ?? sleepStart, sleepStart)
        let inBedEnd = max(session.inBed.map(\.end).max() ?? sleepEnd, sleepEnd)

        var sources: [DataSourceInfo] = []
        let ranked = segments.compactMap(\.source) + session.inBed.sorted { $0.priority > $1.priority }.map(\.source)
        for source in ranked where !sources.contains(source) { sources.append(source) }
        // Order by contribution: the source of the most asleep time first.
        let asleepBySource = Dictionary(grouping: segments.filter(\.stage.isAsleep), by: { $0.source })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        sources.sort { lhs, rhs in
            let a = asleepBySource[lhs] ?? 0, b = asleepBySource[rhs] ?? 0
            return a == b ? lhs.name < rhs.name : a > b
        }

        let day = LocalDay(sleepEnd, calendar: calendar)
        return SleepNight(id: "\(day.isoString)-primary", day: day, isPrimary: true,
                          inBedStart: inBedStart, inBedEnd: inBedEnd, sleepStart: sleepStart, sleepEnd: sleepEnd,
                          segments: segments, stageDurations: durations, interruptions: interruptions, sources: sources)
    }

    // MARK: Primary vs nap

    func isDaytimeNap(_ night: SleepNight) -> Bool {
        guard night.asleepDuration < napMaximumAsleep else { return false }
        guard LocalDay(night.sleepStart, calendar: calendar) == LocalDay(night.sleepEnd, calendar: calendar) else { return false }
        let start = calendar.dateComponents([.hour, .minute], from: night.sleepStart)
        let end = calendar.dateComponents([.hour, .minute], from: night.sleepEnd)
        let startMinutes = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let endMinutes = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        return startMinutes >= napEarliestStartHour * 60 && endMinutes <= napLatestEndHour * 60
    }

    private func napID(day: LocalDay, start: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: start)
        return "\(day.isoString)-nap-" + String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
