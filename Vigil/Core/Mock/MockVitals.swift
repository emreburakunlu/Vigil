import Foundation

extension MockHealthDataSource {
    /// Overnight vitals for the wake day. Correlations: hard training yesterday and short sleep lower HRV
    /// and raise RHR; fitness improves both over the year; illness dips push temperature, RHR and
    /// respiratory rate up and HRV down.
    func vitals(for day: LocalDay) -> DailyVitals? {
        let dn = day.mockDayNumber
        guard hasData, dn <= todayDN, dn >= firstDN else { return nil }
        if scenario == .noSleepLastNight && dn == todayDN {
            return DailyVitals(day: day, heartRateVariability: 58, restingHeartRate: 54)
        }
        let sleep = sleepPlan(day: day, dn: dn)
        guard sleep.sleepEnd <= referenceDate else { return nil }
        return DailyVitals(day: day, dn: dn, sleep: sleep, source: self)
    }

    /// Timestamp of the overnight value (inside the sleep window, on the wake day).
    func vitalsDate(_ day: LocalDay) -> Date {
        sleepPlan(day: day, dn: day.mockDayNumber).sleepEnd.addingTimeInterval(-1_800)
    }

    func dailyActivityValue(for day: LocalDay) -> DailyActivity {
        let dn = day.mockDayNumber
        let n = noise
        let weekday = mockWeekday(dn)
        let weekend = weekday == 6 || weekday == 0
        let sev = illness(dn)
        let plan = plan(dn: dn)

        var steps = n.value(dn, 401, 5_600, 8_800) + (weekend ? 1_300 : 0)
        var active = 190.0
        var exercise = n.value(dn, 402, 6, 22)
        var stand = n.value(dn, 403, 9, 12.9).rounded(.down)
        var workoutKcal = 0.0
        if let run = plan.run {
            steps += run.distance / 1_000 * 1_250
            workoutKcal += run.distance / 1_000 * 62
            exercise += run.duration / 60
            stand += 1
        }
        if let lift = plan.lift {
            steps += 1_800
            workoutKcal += lift.duration / 60 * 5.6
            exercise += lift.duration / 60 * 0.8
            stand += 1
        }
        steps *= 1 - 0.25 * sev
        if steps > 13_000 { steps = 13_000 + (steps - 13_000) * 0.3 }
        steps = mockClamp(steps, 6_000, 16_000)
        active += steps * 0.03 + workoutKcal
        stand = mockClamp(stand, 8, 14)

        var fraction = 1.0
        if dn == todayDN {
            let seconds = referenceDate.timeIntervalSince(day.startDate(in: calendar))
            fraction = mockClamp((seconds / 3_600 - 6.5) / 15, 0.03, 1)
        }
        return DailyActivity(day: day,
                             steps: Int(steps * fraction),
                             activeEnergyKilocalories: active * fraction,
                             basalEnergyKilocalories: 1_800 * fraction,
                             exerciseMinutes: (exercise * fraction).rounded(),
                             standHours: Int(stand * fraction),
                             goals: ActivityGoals(moveKilocalories: 600, exerciseMinutes: 30, standHours: 12))
    }

    // MARK: Body & fitness samples

    /// Weekly Monday-morning weigh-ins with a slight bulking trend (≈ 73.9 → 75.3 kg over 400 days).
    func bodyMassSamples(dn range: ClosedRange<Int>, in interval: DateInterval) -> [MetricSample] {
        range.compactMap { dn in
            guard mockWeekday(dn) == 1 else { return nil }
            let day = LocalDay(mockDayNumber: dn)
            let date = day.startDate(in: calendar).addingTimeInterval(8 * 3_600 + 300)
            guard interval.contains(date), date <= referenceDate else { return nil }
            let value = 73.9 + 1.4 * fitness(dn) + 0.35 * noise.gauss(dn, 410)
            return MetricSample(date: date, value: (value * 10).rounded() / 10, sourceName: "Health")
        }
    }

    /// One estimate after each outdoor run of at least 20 minutes (≈ every 2–3 days), 48 → 52 mL/kg/min.
    func vo2MaxSamples(dn range: ClosedRange<Int>, in interval: DateInterval) -> [MetricSample] {
        range.compactMap { dn in
            guard let run = plan(dn: dn).run, !run.indoor, run.duration >= 1_200 else { return nil }
            let day = LocalDay(mockDayNumber: dn)
            let date = day.startDate(in: calendar).addingTimeInterval(run.startSeconds + run.duration + 300)
            guard interval.contains(date), date <= referenceDate else { return nil }
            let value = 48 + 4 * fitness(dn) + 0.3 * noise.gauss(dn, 411)
            return MetricSample(date: date, value: (value * 10).rounded() / 10, sourceName: Self.watch.deviceName)
        }
    }
}

extension DailyVitals {
    fileprivate init(day: LocalDay, dn: Int, sleep: MockSleepPlan, source: MockHealthDataSource) {
        let n = source.noise
        let x = source.fitness(dn)
        let sev = source.illness(dn)
        let prevLoad = source.plan(dn: dn - 1).load
        let hours = sleep.asleepHours
        let slow = n.smooth(Double(dn) / 9, key: 0, salt: 11)
        let weekly = sin(2 * .pi * Double(mockWeekday(dn)) / 7)
        let seasonal = sin(2 * .pi * Double(dn) / 365.25)
        let shortSleep = max(0, 7.2 - hours)

        var hrv = 56.5 + 5 * x + 1.2 * weekly + 2 * seasonal + 3 * slow + 3.8 * n.gauss(dn, 12)
        hrv += -8 * prevLoad - 3.5 * shortSleep + 1.5 * max(0, hours - 8) - 22 * sev
        var rhr = 57.5 - 5.2 * x + 2 * prevLoad + 1.1 * shortSleep + 0.9 * n.gauss(dn, 13) + 0.7 * slow + 9 * sev
        var resp = 14.6 + 0.35 * n.gauss(dn, 14) + 0.3 * slow + 0.25 * prevLoad + 1.8 * sev
        var temp = 36.45 + 0.05 * weekly + 0.10 * n.gauss(dn, 15) + 0.08 * slow + 0.04 * prevLoad + 0.9 * sev
        var spo2 = 97 + 0.8 * n.gauss(dn, 16) - 1.2 * sev

        if sev == 0 {
            hrv = mockClamp(hrv, 46, 79)
            rhr = mockClamp(rhr, 47, 59)
            resp = mockClamp(resp, 13.2, 16)
            temp = mockClamp(temp, 36.1, 36.9)
        } else {
            hrv = max(30, hrv)
        }
        spo2 = mockClamp(spo2, 95, 99)

        if source.isHero(dn) {
            hrv = 59; rhr = 53; resp = 14.6; temp = 36.52; spo2 = 97
        }
        self.init(day: day,
                  heartRateVariability: hrv.rounded(),
                  restingHeartRate: rhr.rounded(),
                  respiratoryRate: (resp * 10).rounded() / 10,
                  wristTemperature: source.scenario == .partialData ? nil : (temp * 100).rounded() / 100,
                  oxygenSaturation: source.scenario == .partialData ? nil : spo2.rounded())
    }
}
