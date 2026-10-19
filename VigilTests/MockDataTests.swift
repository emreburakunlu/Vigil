import Foundation
import Testing
@testable import Vigil

private func source(_ scenario: MockScenario = .standard, seed: UInt64 = 2026) -> MockHealthDataSource {
    MockHealthDataSource(scenario: scenario, referenceDate: TestSupport.referenceDate, calendar: TestSupport.utc,
                         historyDays: 400, seed: seed, latency: nil)
}

private func interval(days: Int, of s: MockHealthDataSource) -> DateInterval {
    DateInterval(start: s.referenceDate.addingTimeInterval(-Double(days) * 86_400), end: s.referenceDate)
}

private func haversine(_ a: RouteLocation, _ b: RouteLocation) -> Double {
    let r = 6_371_000.0
    let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
    let dp = p2 - p1, dl = (b.longitude - a.longitude) * .pi / 180
    let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
    return 2 * r * asin(h.squareRoot())
}

private func mean<S: Collection>(_ values: S) -> Double where S.Element == Double { values.reduce(0, +) / Double(max(values.count, 1)) }

@Suite("Mock data: determinism")
struct MockDeterminismTests {
    @Test func sameSeedSameData() async throws {
        let a = source(), b = source()
        let range = interval(days: 120, of: a)
        #expect(try await a.sleepNights(in: range) == b.sleepNights(in: range))
        #expect(try await a.dailyVitals(in: range) == b.dailyVitals(in: range))
        #expect(try await a.dailyActivity(in: range) == b.dailyActivity(in: range))
        #expect(try await a.workouts(in: range, kinds: nil) == b.workouts(in: range, kinds: nil))
        #expect(try await a.heartRateSamples(in: interval(days: 3, of: a)) == b.heartRateSamples(in: interval(days: 3, of: b)))
        let run = try #require(try await a.workouts(in: range, kinds: [.run]).first)
        #expect(try await a.runDetails(for: run.id) == b.runDetails(for: run.id))
    }

    @Test func differentSeedDiffers() async throws {
        let a = source(seed: 1), b = source(seed: 2)
        let range = interval(days: 30, of: a)
        #expect(try await a.dailyVitals(in: range) != b.dailyVitals(in: range))
    }

    @Test func daysAreStableRegardlessOfQueryWindow() async throws {
        let s = source()
        let wide = try await s.dailyVitals(in: interval(days: 90, of: s))
        let narrow = try await s.dailyVitals(in: interval(days: 20, of: s))
        #expect(Array(wide.suffix(narrow.count)) == narrow)
        let wideWorkouts = try await s.workouts(in: interval(days: 90, of: s), kinds: nil)
        let narrowWorkouts = try await s.workouts(in: interval(days: 20, of: s), kinds: nil)
        #expect(narrowWorkouts.allSatisfy { wideWorkouts.contains($0) })
    }

    @Test func workoutLookupRoundTrips() async throws {
        let s = source()
        for workout in try await s.workouts(in: interval(days: 30, of: s), kinds: nil) {
            #expect(try await s.workout(id: workout.id) == workout)
        }
        #expect(try await s.workout(id: UUID()) == nil)
        await #expect(throws: HealthDataError.notFound) { try await s.runDetails(for: UUID()) }
    }

    @Test func dayNumberRoundTrip() {
        for dn in stride(from: -800, through: 25_000, by: 37) {
            #expect(LocalDay(mockDayNumber: dn).mockDayNumber == dn)
        }
        #expect(LocalDay(year: 1970, month: 1, day: 1).mockDayNumber == 0)
        #expect(mockWeekday(LocalDay(year: 2026, month: 10, day: 19).mockDayNumber) == 1) // Monday
    }
}

@Suite("Mock data: scenarios")
struct MockScenarioTests {
    @Test func standardHasAYearOfData() async throws {
        let s = source()
        let year = interval(days: 365, of: s)
        let nights = try await s.sleepNights(in: year).filter(\.isPrimary)
        #expect(nights.count >= 355)
        #expect(try await s.dailyVitals(in: year).count >= 355)
        #expect(try await s.dailyActivity(in: year).count >= 364)
        #expect(try await s.workouts(in: year, kinds: [.run]).count > 120)
        #expect(try await s.workouts(in: year, kinds: [.strength]).count > 140)
        #expect(try await s.samples(of: .vo2Max, in: year).count > 100)
        #expect(try await s.samples(of: .bodyMass, in: year).count >= 50)
        #expect(await s.authorizationStatus() == .requested)
    }

    @Test func newUserHasThreeDays() async throws {
        let s = source(.newUser)
        #expect(await s.authorizationStatus() == .notDetermined)
        try await s.requestAuthorization()
        #expect(await s.authorizationStatus() == .requested)
        let all = interval(days: 400, of: s)
        let vitals = try await s.dailyVitals(in: all)
        #expect(vitals.count <= 3 && vitals.count >= 2)
        let activity = try await s.dailyActivity(in: all)
        #expect(activity.count == 3)
        #expect(try await s.sleepNights(in: all).count <= 3)
    }

    @Test func deniedAndEmptyReturnNothing() async throws {
        for scenario in [MockScenario.healthAccessDenied, .empty] {
            let s = source(scenario)
            let all = interval(days: 400, of: s)
            #expect(try await s.sleepNights(in: all).isEmpty)
            #expect(try await s.dailyVitals(in: all).isEmpty)
            #expect(try await s.dailyActivity(in: all).isEmpty)
            #expect(try await s.workouts(in: all, kinds: nil).isEmpty)
            #expect(try await s.heartRateSamples(in: all).isEmpty)
            #expect(try await s.samples(of: .vo2Max, in: all).isEmpty)
            #expect(try await s.samples(of: .bodyMass, in: all).isEmpty)
            #expect(try await s.characteristics().latestBodyMass == nil)
        }
    }

    @Test func noSleepLastNight() async throws {
        let s = source(.noSleepLastNight)
        let today = LocalDay(s.referenceDate, calendar: s.calendar)
        let nights = try await s.sleepNights(in: interval(days: 10, of: s))
        #expect(nights.allSatisfy { $0.day != today })
        #expect(nights.contains { $0.day == today.adding(days: -1, calendar: s.calendar) })
        let todayVitals = try await s.dailyVitals(in: interval(days: 1, of: s)).last
        #expect(todayVitals?.respiratoryRate == nil)
    }

    @Test func noRunsThisWeek() async throws {
        let s = source(.noRunsThisWeek)
        let week = try await s.workouts(in: interval(days: 6, of: s), kinds: [.run])
        #expect(week.isEmpty)
        #expect(!(try await s.workouts(in: interval(days: 30, of: s), kinds: [.run]).isEmpty))
        #expect(!(try await s.workouts(in: interval(days: 6, of: s), kinds: [.strength]).isEmpty))
    }

    @Test func noLiftsThisWeek() async throws {
        let s = source(.noLiftsThisWeek)
        #expect(try await s.workouts(in: interval(days: 6, of: s), kinds: [.strength]).isEmpty)
        #expect(!(try await s.workouts(in: interval(days: 30, of: s), kinds: [.strength]).isEmpty))
    }

    @Test func partialDataLacksTemperatureOxygenAndPower() async throws {
        let s = source(.partialData)
        let vitals = try await s.dailyVitals(in: interval(days: 30, of: s))
        #expect(!vitals.isEmpty)
        #expect(vitals.allSatisfy { $0.wristTemperature == nil && $0.oxygenSaturation == nil })
        #expect(vitals.allSatisfy { $0.heartRateVariability != nil && $0.restingHeartRate != nil })
        let run = try #require(try await s.workouts(in: interval(days: 30, of: s), kinds: [.run]).first { $0.hasRoute })
        let details = try await s.runDetails(for: run.id)
        #expect(details.power.isEmpty && details.form.power == nil)
        #expect(details.form.cadence != nil)
    }

    @Test func lowRecoveryTodayLooksSick() async throws {
        let s = source(.lowRecovery)
        let normal = source()
        let all = try await s.dailyVitals(in: interval(days: 60, of: s))
        let today = try #require(all.last)
        let reference = try await normal.dailyVitals(in: interval(days: 60, of: normal))
        let baseline = reference.dropLast(3).suffix(30)
        #expect(today.heartRateVariability! < mean(baseline.compactMap(\.heartRateVariability)) - 12)
        #expect(today.restingHeartRate! > mean(baseline.compactMap(\.restingHeartRate)) + 5)
        #expect(today.wristTemperature! > mean(baseline.compactMap(\.wristTemperature)) + 0.4)
        let night = try #require(try await s.sleepNights(in: interval(days: 1, of: s)).last)
        #expect(night.asleepDuration < 6.5 * 3_600)
        #expect(try await s.workouts(in: interval(days: 2, of: s), kinds: nil).isEmpty)
    }

    @Test func everyScenarioRespondsToEveryCall() async throws {
        for scenario in MockScenario.allCases {
            let s = source(scenario)
            let range = interval(days: 14, of: s)
            _ = try await s.characteristics()
            _ = try await s.sleepNights(in: range)
            _ = try await s.dailyVitals(in: range)
            _ = try await s.dailyActivity(in: range)
            _ = try await s.heartRateSamples(in: range)
            for metric in HealthMetric.allCases { _ = try await s.samples(of: metric, in: range) }
            for run in try await s.workouts(in: range, kinds: [.run]) { _ = try await s.runDetails(for: run.id) }
        }
    }

    @Test func nothingExistsAfterReferenceDate() async throws {
        let s = MockHealthDataSource(scenario: .standard, referenceDate: TestSupport.referenceDate.addingTimeInterval(-5 * 3_600),
                                     calendar: TestSupport.utc, latency: nil)
        let future = DateInterval(start: s.referenceDate.addingTimeInterval(-86_400), end: s.referenceDate.addingTimeInterval(10 * 86_400))
        #expect(try await s.sleepNights(in: future).allSatisfy { $0.sleepEnd <= s.referenceDate })
        #expect(try await s.workouts(in: future, kinds: nil).allSatisfy { $0.end <= s.referenceDate })
        #expect(try await s.heartRateSamples(in: future).allSatisfy { $0.date <= s.referenceDate })
        #expect(try await s.samples(of: .vo2Max, in: future).allSatisfy { $0.date <= s.referenceDate })
    }

    @Test func latencyDelaysCalls() async throws {
        let s = MockHealthDataSource(referenceDate: TestSupport.referenceDate, calendar: TestSupport.utc, latency: 60...60)
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { _ = try await s.dailyVitals(in: interval(days: 3, of: s)) }
        #expect(elapsed >= .milliseconds(50))
    }
}

@Suite("Mock data: realism")
struct MockRealismTests {
    @Test func nightsAreRealisticAndDoNotOverlap() async throws {
        let s = source()
        let nights = try await s.sleepNights(in: interval(days: 400, of: s))
        let primary = nights.filter(\.isPrimary)
        let cal = s.calendar
        for night in nights {
            #expect(night.sleepStart < night.sleepEnd)
            #expect(night.inBedStart <= night.sleepStart && night.sleepEnd <= night.inBedEnd)
            #expect(abs(night.stageDurations.asleep + night.stageDurations.awake - night.sleepEnd.timeIntervalSince(night.sleepStart)) < 1)
            #expect(night.segments.first?.start == night.sleepStart && night.segments.last?.end == night.sleepEnd)
            for (a, b) in zip(night.segments, night.segments.dropFirst()) {
                #expect(a.end == b.start)
                #expect(a.stage != b.stage)
            }
        }
        for (a, b) in zip(nights, nights.dropFirst()) { #expect(a.inBedEnd <= b.inBedStart) }
        #expect(Set(nights.map(\.id)).count == nights.count)

        // Bedtime 22:30–00:30 and wake 06:30–08:30 on regular nights; occasional short nights allowed.
        var irregular = 0
        for night in primary {
            let bed = cal.dateComponents([.hour, .minute], from: night.inBedStart)
            let bedMinutes = (bed.hour! * 60 + bed.minute!) // 22:30 = 1350, 00:30 = 30
            let wake = cal.dateComponents([.hour, .minute], from: night.sleepEnd)
            let wakeMinutes = wake.hour! * 60 + wake.minute!
            let bedOK = bedMinutes >= 1_350 || bedMinutes <= 30
            if !bedOK || !(385...515).contains(wakeMinutes) { irregular += 1 }
            #expect(night.asleepDuration > 4 * 3_600 && night.asleepDuration < 9.5 * 3_600)
            #expect(night.efficiency > 0.7 && night.efficiency <= 0.97)
            #expect(night.hasStages)
        }
        #expect(irregular <= primary.count / 12)
        let regular = primary.map(\.efficiency).sorted()
        #expect(regular[regular.count / 2] > 0.88 && regular[regular.count / 2] < 0.96)
        #expect(mean(primary.map { $0.asleepDuration / 3_600 }) > 6.9 && mean(primary.map { $0.asleepDuration / 3_600 }) < 7.8)
        #expect(nights.contains { !$0.isPrimary })
    }

    @Test func deepSleepFrontLoadedAndRemBackLoaded() async throws {
        let s = source()
        let nights = try await s.sleepNights(in: interval(days: 120, of: s)).filter(\.isPrimary)
        var deepFirstHalf = 0.0, deepTotal = 0.0, remSecondHalf = 0.0, remTotal = 0.0
        for night in nights {
            let mid = night.sleepStart.addingTimeInterval(night.sleepEnd.timeIntervalSince(night.sleepStart) / 2)
            for seg in night.segments where seg.stage == .deep || seg.stage == .rem {
                let early = max(0, min(seg.end, mid).timeIntervalSince(seg.start))
                if seg.stage == .deep { deepFirstHalf += early; deepTotal += seg.duration } else { remSecondHalf += seg.duration - early; remTotal += seg.duration }
            }
        }
        #expect(deepFirstHalf / deepTotal > 0.6)
        #expect(remSecondHalf / remTotal > 0.6)
    }

    @Test func vitalsStayInPhysiologicalRanges() async throws {
        let s = source()
        let vitals = try await s.dailyVitals(in: interval(days: 400, of: s))
        let normalDays = vitals.filter { ($0.wristTemperature ?? 0) < 36.75 && ($0.restingHeartRate ?? 99) <= 59 }
        #expect(normalDays.count > vitals.count * 8 / 10)
        for v in vitals {
            #expect((30...80).contains(v.heartRateVariability!))
            #expect((46...70).contains(v.restingHeartRate!))
            #expect((13...18.5).contains(v.respiratoryRate!))
            #expect((36.0...37.5).contains(v.wristTemperature!))
            #expect((95...99).contains(v.oxygenSaturation!))
        }
        for v in normalDays {
            #expect((40...79).contains(v.heartRateVariability!))
            #expect((47...59).contains(v.restingHeartRate!))
            #expect((13...16.01).contains(v.respiratoryRate!))
            #expect(abs(v.wristTemperature! - 36.45) < 0.6)
        }
        // Illness-like dips exist: temperature + RHR + respiratory rate up, HRV down.
        let dips = vitals.filter { $0.wristTemperature! > 36.95 }
        #expect(dips.count >= 3)
        #expect(dips.allSatisfy { $0.restingHeartRate! > 55 && $0.respiratoryRate! > 15 && $0.heartRateVariability! < 55 })
    }

    @Test func hardTrainingAndShortSleepLowerNextDayHRV() async throws {
        let s = source()
        let range = interval(days: 400, of: s)
        let vitals = try await s.dailyVitals(in: range).filter { ($0.restingHeartRate ?? 0) < 60 }
        let workouts = try await s.workouts(in: range, kinds: nil)
        let nights = try await s.sleepNights(in: range).filter(\.isPrimary)
        let cal = s.calendar
        let trainedDays = Set(workouts.map { LocalDay($0.start, calendar: cal) })
        let longDays = Set(workouts.filter { $0.duration > 3_000 && $0.kind == .run }.map { LocalDay($0.start, calendar: cal) })

        func after(_ days: Set<LocalDay>, hard: Bool) -> [DailyVitals] {
            vitals.filter { v in
                let yesterday = v.day.adding(days: -1, calendar: cal)
                return hard ? days.contains(yesterday) : !trainedDays.contains(yesterday)
            }
        }
        let hrvAfterHard = mean(after(longDays, hard: true).compactMap(\.heartRateVariability))
        let hrvAfterRest = mean(after([], hard: false).compactMap(\.heartRateVariability))
        #expect(hrvAfterHard < hrvAfterRest - 1.5)
        let rhrAfterHard = mean(after(longDays, hard: true).compactMap(\.restingHeartRate))
        let rhrAfterRest = mean(after([], hard: false).compactMap(\.restingHeartRate))
        #expect(rhrAfterHard > rhrAfterRest + 0.5)

        let asleepByDay = Dictionary(uniqueKeysWithValues: nights.map { ($0.day, $0.asleepDuration / 3_600) })
        let short = vitals.filter { (asleepByDay[$0.day] ?? 7.5) < 6.2 }.compactMap(\.heartRateVariability)
        let long = vitals.filter { (asleepByDay[$0.day] ?? 0) > 7.2 }.compactMap(\.heartRateVariability)
        #expect(short.count >= 5)
        #expect(mean(short) < mean(long) - 3)
    }

    @Test func fitnessImprovesOverMonths() async throws {
        let s = source()
        let vo2 = try await s.samples(of: .vo2Max, in: interval(days: 400, of: s))
        let early = mean(vo2.prefix(15).map(\.value)), late = mean(vo2.suffix(15).map(\.value))
        #expect(early > 47 && early < 49.5)
        #expect(late > 51 && late < 53)
        #expect(vo2.allSatisfy { (46...54).contains($0.value) })

        let runs = try await s.workouts(in: interval(days: 400, of: s), kinds: [.run])
        let easy = runs.filter { $0.title == "Easy Run" && !$0.isIndoor }.compactMap(\.averagePaceSecondsPerKilometer)
        #expect(mean(easy.suffix(20)) < mean(easy.prefix(20)) - 12)

        let mass = try await s.samples(of: .bodyMass, in: interval(days: 400, of: s))
        #expect(mass.allSatisfy { (72...77).contains($0.value) })
        #expect(mean(mass.suffix(8).map(\.value)) > mean(mass.prefix(8).map(\.value)))
    }

    @Test func activityIsPlausible() async throws {
        let s = source()
        let activity = try await s.dailyActivity(in: interval(days: 200, of: s))
        for a in activity.dropLast() {
            #expect((6_000...16_000).contains(a.steps))
            #expect((300...2_000).contains(a.activeEnergyKilocalories))
            #expect((8...14).contains(a.standHours))
            #expect(a.exerciseMinutes >= 0 && a.exerciseMinutes < 180)
            #expect(a.goals?.moveKilocalories == 600)
        }
        #expect(activity.dropLast().contains { ($0.exerciseProgress ?? 0) >= 1 })
        #expect(activity.dropLast().contains { ($0.moveProgress ?? 0) < 1 })
        // Today is only partially complete at noon.
        let today = try #require(activity.last)
        #expect(today.steps < 8_000)
    }

    @Test func todayLooksLikeTheDesign() async throws {
        let s = source()
        let vitals = try #require(try await s.dailyVitals(in: interval(days: 1, of: s)).last)
        #expect(vitals.heartRateVariability == 59 && vitals.restingHeartRate == 53)
        let night = try #require(try await s.sleepNights(in: interval(days: 1, of: s)).last)
        #expect(Int(night.asleepDuration / 60) == 462) // 7h42m
    }
}

@Suite("Mock data: workouts")
struct MockWorkoutTests {
    @Test func scheduleLooksLikePushPullLegsPlusThreeRuns() async throws {
        let s = source()
        let end = LocalDay(s.referenceDate, calendar: s.calendar)
        var fullWeeks = 0
        for week in 1...30 {
            let weekEnd = end.adding(days: -7 * week, calendar: s.calendar)
            let range = LocalDay.interval(from: weekEnd.adding(days: -6, calendar: s.calendar), through: weekEnd, calendar: s.calendar)
            let workouts = try await s.workouts(in: range, kinds: nil)
            let runs = workouts.filter { $0.kind == .run }.count
            let lifts = workouts.filter { $0.kind == .strength }.count
            #expect((0...4).contains(runs))
            #expect((1...5).contains(lifts))
            if runs == 3 && (3...4).contains(lifts) { fullWeeks += 1 }
        }
        #expect(fullWeeks >= 14)
    }

    @Test func workoutsAreWellFormedAndDoNotOverlap() async throws {
        let s = source()
        let workouts = try await s.workouts(in: interval(days: 400, of: s), kinds: nil)
        let nights = try await s.sleepNights(in: interval(days: 400, of: s))
        #expect(Set(workouts.map(\.id)).count == workouts.count)
        for (a, b) in zip(workouts, workouts.dropFirst()) { #expect(a.end <= b.start) }
        for w in workouts {
            #expect(w.end == w.start.addingTimeInterval(w.duration))
            for n in nights { #expect(w.end <= n.inBedStart || w.start >= n.inBedEnd) }
            switch w.kind {
            case .strength:
                #expect(w.source.name == "Hevy")
                #expect(w.heartRateSource?.name == "Apple Watch")
                #expect((50 * 60...75 * 60).contains(w.duration))
                #expect((110...135).contains(w.averageHeartRate!))
                #expect(w.maxHeartRate! > w.averageHeartRate! + 20 && w.maxHeartRate! < 175)
                #expect(["Push Day", "Pull Day", "Leg Day"].contains(w.title))
                #expect(w.distanceMeters == nil)
            case .run:
                #expect(w.source.isApple)
                #expect((4_900...18_100).contains(w.distanceMeters!))
                #expect((165...400).contains(w.averagePaceSecondsPerKilometer!) )
                #expect(w.maxHeartRate! > w.averageHeartRate!)
                #expect(w.maxHeartRate! < 196)
            case .other:
                Issue.record("unexpected workout kind")
            }
        }
        let runs = workouts.filter { $0.kind == .run }
        #expect(runs.contains { $0.distanceMeters! >= 12_000 })           // long runs
        #expect(runs.contains { $0.title == "Tempo Run" } && runs.contains { $0.title == "Intervals" })
        #expect(runs.contains { $0.title == "5K Race" } && runs.contains { $0.title == "10K Race" })
        #expect(runs.contains { $0.isIndoor && !$0.hasRoute })
    }

    @Test func racesProducePersonalBests() async throws {
        let s = source()
        let races = try await s.workouts(in: interval(days: 400, of: s), kinds: [.run]).filter { $0.title == "5K Race" }
        #expect(races.count >= 2)
        let times = races.map(\.duration)
        var best = Double.infinity
        var pbs = 0
        for t in times where t < best { best = t; pbs += 1 }
        #expect(pbs >= 2)
        #expect(times.last! < times.first!)
        #expect((1_150...1_400).contains(times.last!)) // 19:10–23:20
    }

    @Test func liftHeartRateMatchesWorkout() async throws {
        let s = source()
        let lift = try #require(try await s.workouts(in: interval(days: 30, of: s), kinds: [.strength]).first)
        let samples = try await s.heartRateSamples(in: lift.interval)
        #expect(samples.count > 300)
        #expect(abs(mean(samples.map(\.value)) - lift.averageHeartRate!) < 3)
        #expect(samples.map(\.value).max()! <= lift.maxHeartRate! + 1)
    }
}

@Suite("Mock data: runs")
struct MockRunDetailTests {
    @Test func routesAreContinuousAndMatchDistance() async throws {
        let s = source()
        let runs = try await s.workouts(in: interval(days: 400, of: s), kinds: [.run]).filter(\.hasRoute)
        #expect(runs.count > 100)
        for run in runs.prefix(40) + runs.suffix(10) {
            let d = try await s.runDetails(for: run.id)
            let route = d.route
            #expect(route.count == Int(run.duration) + 1)
            #expect(route.first?.timestamp == run.start)
            var length = 0.0
            for (a, b) in zip(route, route.dropFirst()) {
                #expect(b.timestamp.timeIntervalSince(a.timestamp) == 1)         // ~1 point per second
                let step = haversine(a, b)
                length += step
                #expect(step < 9)                                                // no GPS jumps (4.5 m/s max)
                #expect(abs(b.altitude! - a.altitude!) < 2)
            }
            #expect(abs(length - run.distanceMeters!) / run.distanceMeters! < 0.02)
            #expect(abs(d.cumulativeDistance.last!.value - run.distanceMeters!) < 1)
            // City-sized: stays within a few km of the centre, Istanbul latitude / longitude.
            #expect(route.allSatisfy { (40.9...41.1).contains($0.latitude) && (28.9...29.2).contains($0.longitude) })
            #expect(route.allSatisfy { $0.horizontalAccuracy! < 10 })
        }
    }

    @Test func seriesAreConsistentWithTheWorkout() async throws {
        let s = source()
        let run = try #require(try await s.workouts(in: interval(days: 60, of: s), kinds: [.run]).first { $0.title == "Tempo Run" })
        let d = try await s.runDetails(for: run.id)
        #expect(d.workoutID == run.id)
        #expect(d.heartRate.count == d.route.count && d.pace.count == d.route.count && d.elevation.count == d.route.count)
        #expect(d.cumulativeDistance.count == d.route.count)
        #expect(abs(mean(d.heartRate.map(\.value)) - run.averageHeartRate!) < 1.5)
        #expect(d.heartRate.map(\.value).max()! <= run.maxHeartRate! + 1)
        #expect(d.heartRate.allSatisfy { (80...196).contains($0.value) })
        // Distance is monotonic.
        #expect(zip(d.cumulativeDistance, d.cumulativeDistance.dropFirst()).allSatisfy { $0.value <= $1.value })
        // Tempo: the middle is faster than the warm-up and the heart rate rises with it.
        let n = d.pace.count
        let warmup = mean(d.pace[(n / 20)..<(n / 6)].map(\.value))
        let middle = mean(d.pace[(n * 2 / 5)..<(n * 3 / 5)].map(\.value))
        #expect(middle < warmup - 25)
        #expect(mean(d.heartRate[(n * 2 / 5)..<(n * 3 / 5)].map(\.value)) > mean(d.heartRate[(n / 20)..<(n / 6)].map(\.value)) + 8)
        // Elevation gain/loss of the workout is consistent with the series.
        var gain = 0.0
        for (a, b) in zip(d.elevation, d.elevation.dropFirst()) where b.value > a.value { gain += b.value - a.value }
        #expect(abs(gain - run.elevationGainMeters!) < max(15, run.elevationGainMeters! * 0.2))
    }

    @Test func runningFormIsInRange() async throws {
        let s = source()
        for run in try await s.workouts(in: interval(days: 45, of: s), kinds: [.run]).filter(\.hasRoute).prefix(8) {
            let d = try await s.runDetails(for: run.id)
            #expect(d.cadence.allSatisfy { (165...182).contains($0.value) })
            #expect(d.groundContactTime.allSatisfy { (220...260).contains($0.value) })
            #expect(d.verticalOscillation.allSatisfy { (7...9).contains($0.value) })
            #expect(d.power.allSatisfy { (230...300).contains($0.value) })
            #expect(d.strideLength.allSatisfy { (0.8...1.6).contains($0.value) })
            let form = d.form
            #expect((165...182).contains(form.cadence!) && (220...260).contains(form.groundContactTime!))
            #expect((7...9).contains(form.verticalOscillation!) && (230...300).contains(form.power!))
            #expect(!d.power.isEmpty)
        }
    }

    @Test func indoorRunsHaveNoRoute() async throws {
        let s = source()
        let treadmill = try #require(try await s.workouts(in: interval(days: 400, of: s), kinds: [.run]).first(where: \.isIndoor))
        let d = try await s.runDetails(for: treadmill.id)
        #expect(d.route.isEmpty && d.elevation.isEmpty)
        #expect(!d.heartRate.isEmpty && !d.cumulativeDistance.isEmpty)
        #expect(treadmill.elevationGainMeters == nil)
    }

    @Test func intervalsAlternateFastAndSlow() async throws {
        let s = source()
        let run = try #require(try await s.workouts(in: interval(days: 120, of: s), kinds: [.run]).first { $0.title == "Intervals" })
        let d = try await s.runDetails(for: run.id)
        let n = d.pace.count
        let middle = d.pace[(n * 3 / 10)..<(n * 7 / 10)].map(\.value)
        #expect(middle.max()! - middle.min()! > 60)
    }
}

@Suite("Mock data: performance")
struct MockPerformanceTests {
    @Test func ninetyDaySummariesAreFast() async throws {
        let s = source()
        let range = interval(days: 90, of: s)
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await s.sleepNights(in: range)
            _ = try await s.dailyVitals(in: range)
            _ = try await s.dailyActivity(in: range)
            _ = try await s.workouts(in: range, kinds: nil)
            _ = try await s.samples(of: .vo2Max, in: range)
            _ = try await s.samples(of: .bodyMass, in: range)
        }
        #expect(elapsed < .milliseconds(200), "took \(elapsed)")
    }

    @Test func yearOfSummariesAndLongRunDetailsAreReasonable() async throws {
        let s = source()
        let clock = ContinuousClock()
        let year = interval(days: 400, of: s)
        let summaries = try await clock.measure {
            _ = try await s.sleepNights(in: year)
            _ = try await s.dailyVitals(in: year)
            _ = try await s.dailyActivity(in: year)
            _ = try await s.workouts(in: year, kinds: nil)
        }
        #expect(summaries < .milliseconds(800), "took \(summaries)")
        let long = try #require(try await s.workouts(in: year, kinds: [.run]).max { $0.duration < $1.duration })
        let details = try await clock.measure { _ = try await s.runDetails(for: long.id) }
        #expect(details < .milliseconds(300), "took \(details)")
    }
}
