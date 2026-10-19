import Foundation

// Training calendar of the mock athlete: a 21-year-old who lifts Push / Pull / Legs and runs three times a week.
//
//   Mon Push · Tue easy run · Wed Pull · Thu tempo/intervals · Fri Legs · Sat long run
//   Sun: race every 8th week, otherwise an extra lift every other week.
//
// Everything is a pure function of the day number, so repeated calls agree.

enum MockRunType: String, Sendable {
    case easy, tempo, intervals, long, race5k, race10k

    var load: Double {
        switch self {
        case .easy: 0.30
        case .tempo: 0.60
        case .intervals: 0.70
        case .long: 0.55
        case .race5k, .race10k: 0.85
        }
    }
}

struct MockRunPlan: Sendable {
    var type: MockRunType
    var title: String
    var distance: Double
    /// Whole seconds.
    var duration: TimeInterval
    /// Seconds after local midnight.
    var startSeconds: Double
    var indoor: Bool
    var averageHeartRate: Double
    var maxHeartRate: Double

    var averagePace: Double { duration / (distance / 1_000) }
}

struct MockLiftPlan: Sendable {
    var title: String
    var duration: TimeInterval
    var startSeconds: Double
    var averageHeartRate: Double
    var maxHeartRate: Double
    var load: Double
}

struct MockDayPlan: Sendable {
    var run: MockRunPlan?
    var lift: MockLiftPlan?

    /// 0–1 training stress of the day (drives next-day HRV / RHR).
    var load: Double {
        var total = 0.0
        if let run {
            total += run.type.load * min(1.4, run.duration / 2_700)
        }
        if let lift { total += lift.load * min(1.3, lift.duration / 3_600) }
        return min(1, total)
    }
}

/// A looping running course (park / seafront loop) described by cheap numbers; the heavy polyline is
/// only built when a run's details are requested.
struct MockCourse: Sendable {
    var name: String
    var centerLatitude: Double
    var centerLongitude: Double
    var lapLength: Double
    var shapeA2: Double
    var shapePhase2: Double
    var shapeA3: Double
    var shapePhase3: Double
    /// Fraction 0–1 of a lap at which the run starts.
    var startFraction: Double
    var reversed: Bool
    var altitudeBase: Double
    var altitudePhase1: Double
    var altitudePhase2: Double

    /// Altitude (m) after `distance` metres along the run; periodic in the lap length.
    func altitude(at distance: Double) -> Double {
        let u = (distance / lapLength).truncatingRemainder(dividingBy: 1)
        return altitudeBase + 17 * sin(2 * .pi * u + altitudePhase1) + 6 * sin(4 * .pi * u + altitudePhase2)
    }

    /// Total climb and descent over `distance` metres.
    func elevationChange(over distance: Double) -> (gain: Double, loss: Double) {
        var gain = 0.0, loss = 0.0
        var previous = altitude(at: 0)
        var d = 10.0
        while d <= distance + 5 {
            let a = altitude(at: min(d, distance))
            if a > previous { gain += a - previous } else { loss += previous - a }
            previous = a
            d += 10
        }
        return (gain, loss)
    }
}

extension MockHealthDataSource {
    // MARK: Fitness & illness

    /// 0 → 1 over the last 400 days: drives VO₂ max, pace, HRV and RHR trends.
    func fitness(_ dn: Int) -> Double {
        let x = 1 - Double(todayDN - dn) / 400
        return mockClamp(x + 0.025 * noise.smooth(Double(dn) / 30, key: 0, salt: 1), 0, 1)
    }

    /// 0 (healthy) … 1 (peak of a cold / flu-like dip) for the wake day `dn`.
    func illness(_ dn: Int) -> Double {
        let ago = todayDN - dn
        if scenario == .lowRecovery {
            if ago == 0 { return 0.85 }
            if ago == 1 { return 0.4 }
        }
        if ago < 6 { return 0 }
        let n = noise
        let block = Int((Double(dn) / 50).rounded(.down))
        guard n.unit(block, 301) < 0.75 else { return 0 }
        let start = block * 50 + 6 + Int(n.unit(block, 302) * 36)
        let length = 3 + Int(n.unit(block, 303) * 3)
        let k = dn - start
        let profile = [0.55, 1.0, 0.8, 0.5, 0.25]
        return (0..<length).contains(k) ? profile[k] : 0
    }

    // MARK: Plans

    func plan(dn: Int) -> MockDayPlan {
        var plan = MockDayPlan()
        guard hasData, illness(dn) <= 0.3 else { return plan }
        let ago = todayDN - dn
        if scenario == .lowRecovery && ago <= 1 { return plan }
        let n = noise
        let weekday = mockWeekday(dn)
        let week = Int((Double(dn) / 7).rounded(.down))
        let x = fitness(dn)

        var runType: MockRunType?
        switch weekday {
        case 2: if n.unit(dn, 101) >= 0.07 { runType = .easy }
        case 4: if n.unit(dn, 101) >= 0.08 { runType = week % 2 == 0 ? .tempo : .intervals }
        case 6: if n.unit(dn, 101) >= 0.06 { runType = .long }
        case 0: if week % 8 == 3 { runType = (week / 8) % 2 == 0 ? .race5k : .race10k }
        default: break
        }
        if let runType, !(scenario == .noRunsThisWeek && ago < 7) {
            plan.run = makeRun(type: runType, dn: dn, weekday: weekday, week: week, fitness: x)
        }

        var liftTitle: String?
        switch weekday {
        case 1: if n.unit(dn, 102) >= 0.08 { liftTitle = "Push Day" }
        case 3: if n.unit(dn, 102) >= 0.08 { liftTitle = "Pull Day" }
        case 5: if n.unit(dn, 102) >= 0.08 { liftTitle = "Leg Day" }
        case 0: if runType == nil, week % 2 == 0, n.unit(dn, 102) < 0.8 { liftTitle = (week / 2) % 2 == 0 ? "Push Day" : "Pull Day" }
        default: break
        }
        if let liftTitle, !(scenario == .noLiftsThisWeek && ago < 7) {
            let avg = n.value(dn, 120, 112, 133)
            plan.lift = MockLiftPlan(
                title: liftTitle,
                duration: (n.value(dn, 121, 50, 75) * 60).rounded(),
                startSeconds: weekday == 0 ? 11 * 3_600 + n.value(dn, 122, 0, 1_800) : 18 * 3_600 + 900 + n.value(dn, 122, 0, 2_700),
                averageHeartRate: avg.rounded(),
                maxHeartRate: (avg + n.value(dn, 123, 26, 38)).rounded(),
                load: liftTitle == "Leg Day" ? 0.55 : 0.42)
        }
        return plan
    }

    private func makeRun(type: MockRunType, dn: Int, weekday: Int, week: Int, fitness x: Double) -> MockRunPlan {
        let n = noise
        let u = n.unit(dn, 110)
        let pace: Double
        var distance: Double
        let avg: Double
        let maxExtra: Double
        let title: String
        var start = 17.5 * 3_600 + n.value(dn, 114, 0, 2_700)
        switch type {
        case .easy:
            distance = 5_000 + 3_000 * u
            pace = 340 - 28 * x + 7 * n.gauss(dn, 111)
            avg = 143 + 8 * n.unit(dn, 112) - 3 * x
            maxExtra = 20 + 8 * n.unit(dn, 113)
            title = "Easy Run"
        case .tempo:
            distance = 6_500 + 2_000 * u
            pace = 300 - 24 * x + 5 * n.gauss(dn, 111)
            avg = 160 + 6 * n.unit(dn, 112) - 3 * x
            maxExtra = 17 + 7 * n.unit(dn, 113)
            title = "Tempo Run"
        case .intervals:
            distance = 6_000 + 1_800 * u
            pace = 305 - 24 * x + 5 * n.gauss(dn, 111)
            avg = 158 + 6 * n.unit(dn, 112) - 3 * x
            maxExtra = 22 + 8 * n.unit(dn, 113)
            title = "Intervals"
        case .long:
            let cycle = 0.5 + 0.5 * sin(Double(week) * 0.9)
            distance = 12_000 + 6_000 * (0.45 * cycle + 0.55 * u)
            pace = 352 - 28 * x + 6 * n.gauss(dn, 111)
            avg = 147 + 7 * n.unit(dn, 112) - 3 * x
            maxExtra = 22 + 8 * n.unit(dn, 113)
            title = "Long Run"
            start = 9.5 * 3_600 + n.value(dn, 114, 0, 1_800)
        case .race5k:
            distance = 5_000 * (1.002 + 0.006 * u)
            pace = 268 - 26 * x + 3 * n.gauss(dn, 111)
            avg = 174 + 4 * n.unit(dn, 112)
            maxExtra = 13 + 5 * n.unit(dn, 113)
            title = "5K Race"
            start = 10 * 3_600
        case .race10k:
            distance = 10_000 * (1.002 + 0.006 * u)
            pace = 280 - 26 * x + 3 * n.gauss(dn, 111)
            avg = 170 + 4 * n.unit(dn, 112)
            maxExtra = 13 + 5 * n.unit(dn, 113)
            title = "10K Race"
            start = 10 * 3_600
        }
        distance = (distance / 10).rounded() * 10
        let indoor = type == .easy && n.unit(dn, 115) < 0.05
        return MockRunPlan(type: type, title: title, distance: distance,
                           duration: (distance / 1_000 * pace).rounded(), startSeconds: start.rounded(),
                           indoor: indoor, averageHeartRate: avg.rounded(), maxHeartRate: (avg + maxExtra).rounded())
    }

    func course(dn: Int) -> MockCourse {
        let n = noise
        let places: [(String, Double, Double)] = [
            ("Fenerbahçe Park", 40.9672, 29.0356),
            ("Caddebostan Coast", 40.9626, 29.0614),
            ("Yoğurtçu Park", 40.9937, 29.0336),
        ]
        let place = places[min(2, Int(n.unit(dn, 130) * 3))]
        return MockCourse(name: place.0, centerLatitude: place.1, centerLongitude: place.2,
                          lapLength: n.value(dn, 131, 2_600, 4_400),
                          shapeA2: n.value(dn, 132, 0.12, 0.22), shapePhase2: n.value(dn, 133, 0, 6.28),
                          shapeA3: n.value(dn, 134, 0.04, 0.10), shapePhase3: n.value(dn, 135, 0, 6.28),
                          startFraction: n.unit(dn, 136), reversed: n.unit(dn, 137) < 0.5,
                          altitudeBase: n.value(dn, 138, 25, 70),
                          altitudePhase1: n.value(dn, 139, 0, 6.28), altitudePhase2: n.value(dn, 140, 0, 6.28))
    }
}
