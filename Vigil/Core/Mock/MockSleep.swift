import Foundation

/// Cheap description of a night (no segments yet): used by vitals and heart-rate generation too.
struct MockSleepPlan: Sendable {
    var day: LocalDay
    var inBedStart: Date
    var sleepStart: Date
    var sleepEnd: Date
    var inBedEnd: Date
    /// Seconds asleep and seconds awake between `sleepStart` and `sleepEnd`.
    var asleep: TimeInterval
    var awake: TimeInterval
    var isBad: Bool

    var asleepHours: Double { asleep / 3_600 }
}

extension MockHealthDataSource {
    /// Design hero values: the "today" night looks like the reference screens (7h42m, HRV 62, RHR 52).
    func isHero(_ dn: Int) -> Bool {
        dn == todayDN && scenario != .lowRecovery
    }

    func sleepPlan(day: LocalDay, dn: Int) -> MockSleepPlan {
        let n = noise
        let weekday = mockWeekday(dn)
        let weekend = weekday == 6 || weekday == 0
        let sev = illness(dn)
        let hero = isHero(dn)
        let prevLoad = plan(dn: dn - 1).load
        let bad = !hero && (n.unit(dn, 201) < 0.07 || (scenario == .lowRecovery && dn == todayDN))

        let asleepMin: Double
        let awakeMin: Double
        let latencyMin: Double
        let tailMin: Double
        if hero {
            asleepMin = 462; awakeMin = 14; latencyMin = 11; tailMin = 6
        } else if bad {
            asleepMin = 270 + 70 * n.unit(dn, 202)
            awakeMin = 28 + 30 * n.unit(dn, 204)
            latencyMin = 20 + 15 * n.unit(dn, 205)
            tailMin = 4 + 6 * n.unit(dn, 206)
        } else {
            asleepMin = mockClamp(430 + (weekend ? 30 : 0) + 32 * n.gauss(dn, 203) + 18 * prevLoad + 35 * sev, 375, 520)
            let u = n.unit(dn, 204)
            awakeMin = 10 + 14 * u * u
            latencyMin = 9 + 10 * n.unit(dn, 205)
            tailMin = 4 + 6 * n.unit(dn, 206)
        }
        let inBed = latencyMin + asleepMin + awakeMin + tailMin
        // Preferred wake time (minutes after midnight): 06:45–07:35 weekdays, 07:30–08:30 weekends.
        let preferred = hero ? 425 : (weekend ? 450 + 60 * n.unit(dn, 207) : 405 + 50 * n.unit(dn, 207))
        // Keep bedtime within 22:30–00:30 (minutes -90 … 30) and wake within 06:30–08:30 where possible.
        let lo = max(390, inBed - 90 - tailMin)
        let hi = min(510, inBed + 30 - tailMin)
        let wake = lo <= hi ? mockClamp(preferred, lo, hi) : hi

        let midnight = day.startDate(in: calendar)
        let sleepEnd = midnight.addingTimeInterval((wake * 60).rounded())
        let inBedEnd = sleepEnd.addingTimeInterval((tailMin * 60).rounded())
        let sleepStart = sleepEnd.addingTimeInterval(-((asleepMin + awakeMin) * 60).rounded())
        let inBedStart = sleepStart.addingTimeInterval(-(latencyMin * 60).rounded())
        return MockSleepPlan(day: day, inBedStart: inBedStart, sleepStart: sleepStart, sleepEnd: sleepEnd, inBedEnd: inBedEnd,
                             asleep: (asleepMin * 60).rounded(), awake: (awakeMin * 60).rounded(), isBad: bad)
    }

    /// The primary night (and occasionally a Sunday nap) for the wake day `day`.
    func nights(for day: LocalDay) -> [SleepNight] {
        let dn = day.mockDayNumber
        guard hasData, dn <= todayDN, dn >= firstDN else { return [] }
        if scenario == .noSleepLastNight && dn == todayDN { return [] }
        let plan = sleepPlan(day: day, dn: dn)
        var result: [SleepNight] = []
        if plan.sleepEnd <= referenceDate {
            result.append(primaryNight(plan, dn: dn))
        }
        if let nap = nap(day: day, dn: dn), nap.sleepEnd <= referenceDate {
            result.append(nap)
        }
        return result
    }

    private func primaryNight(_ plan: MockSleepPlan, dn: Int) -> SleepNight {
        let segments = nightSegments(plan, dn: dn)
        var durations = SleepStageDurations()
        var interruptions = 0
        for s in segments {
            switch s.stage {
            case .awake: durations.awake += s.duration; interruptions += 1
            case .rem: durations.rem += s.duration
            case .core: durations.core += s.duration
            case .deep: durations.deep += s.duration
            case .asleepUnspecified: durations.unspecified += s.duration
            case .inBed: break
            }
        }
        return SleepNight(id: "\(plan.day.isoString)-primary", day: plan.day, isPrimary: true,
                          inBedStart: plan.inBedStart, inBedEnd: plan.inBedEnd,
                          sleepStart: plan.sleepStart, sleepEnd: plan.sleepEnd,
                          segments: segments, stageDurations: durations,
                          interruptions: interruptions, sources: [Self.watch])
    }

    /// ~90-minute cycles: light → deep → light → REM, deep shrinking and REM growing through the night,
    /// with brief awakenings between cycles. Asleep and awake totals match the plan exactly.
    private func nightSegments(_ plan: MockSleepPlan, dn: Int) -> [SleepSegment] {
        let n = noise
        let asleep = plan.asleep, awake = plan.awake
        let cycles = max(2, Int(((asleep + awake) / 5_400).rounded()))
        let deepShare = (0.14 + 0.07 * n.unit(dn, 210)) * (plan.isBad ? 0.7 : 1)
        let remShare = 0.20 + 0.06 * n.unit(dn, 211)
        let deepTotal = asleep * deepShare
        let remTotal = asleep * remShare
        let coreTotal = asleep - deepTotal - remTotal

        func weights(_ f: (Int) -> Double) -> [Double] {
            let raw = (0..<cycles).map(f)
            let sum = raw.reduce(0, +)
            return raw.map { $0 / sum }
        }
        let deepW = weights { exp(-0.9 * Double($0)) * (0.85 + 0.3 * n.unit(dn, 220, $0)) }
        let remW = weights { (1 + 0.55 * Double($0)) * (0.85 + 0.3 * n.unit(dn, 230, $0)) }
        let coreW = weights { 0.9 + 0.2 * n.unit(dn, 235, $0) }

        // Which cycle boundaries carry an awakening.
        let events = max(1, min(cycles - 1, Int((awake / 240).rounded())))
        let ranked = (0..<(cycles - 1)).sorted { n.unit(dn, 240, $0) < n.unit(dn, 240, $1) }
        let awakeAfter = Set(ranked.prefix(events))
        let awakeEach = awake / Double(events)

        var segments: [SleepSegment] = []
        var t = plan.sleepStart
        func add(_ stage: SleepStage, _ length: TimeInterval) {
            guard length > 0 else { return }
            let end = t.addingTimeInterval(length)
            if let last = segments.last, last.stage == stage {
                segments[segments.count - 1].end = end
            } else {
                segments.append(SleepSegment(stage: stage, start: t, end: end, source: Self.watch))
            }
            t = end
        }
        for i in 0..<cycles {
            var deep = deepTotal * deepW[i]
            let core = coreTotal * coreW[i]
            var core2 = core * 0.45
            if deep < 120 { core2 += deep; deep = 0 }
            add(.core, core * 0.55)
            add(.deep, deep)
            add(.core, core2)
            add(.rem, remTotal * remW[i])
            if awakeAfter.contains(i) { add(.awake, awakeEach) }
        }
        if !segments.isEmpty { segments[segments.count - 1].end = plan.sleepEnd }
        return segments
    }

    private func nap(day: LocalDay, dn: Int) -> SleepNight? {
        guard mockWeekday(dn) == 0, !isHero(dn), noise.unit(dn, 250) < 0.12 else { return nil }
        let start = day.startDate(in: calendar).addingTimeInterval(14 * 3_600 + noise.value(dn, 251, 0, 1_200).rounded())
        let asleep = (noise.value(dn, 252, 22, 40) * 60).rounded()
        let sleepStart = start.addingTimeInterval(180)
        let sleepEnd = sleepStart.addingTimeInterval(asleep)
        var durations = SleepStageDurations()
        durations.core = asleep
        return SleepNight(id: "\(day.isoString)-nap", day: day, isPrimary: false,
                          inBedStart: start, inBedEnd: sleepEnd.addingTimeInterval(120),
                          sleepStart: sleepStart, sleepEnd: sleepEnd,
                          segments: [SleepSegment(stage: .core, start: sleepStart, end: sleepEnd, source: Self.watch)],
                          stageDurations: durations, interruptions: 0, sources: [Self.watch])
    }
}
