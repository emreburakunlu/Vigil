import Foundation

extension MockHealthDataSource {
    /// Heart rate across `interval`: sleeping lows, daytime baseline with walking bursts, and dense
    /// (5 s) workout series that match the workout's average and maximum.
    func heartRateSamplesSync(in interval: DateInterval) -> [MetricSample] {
        guard hasData else { return [] }
        let end = min(interval.end, referenceDate)
        guard end > interval.start, let range = dayRange(overlapping: DateInterval(start: interval.start, end: end)) else { return [] }
        let span = DateInterval(start: interval.start, end: end)
        let step: TimeInterval = span.duration <= 6 * 3_600 ? 30 : 300
        let device = Self.watch.deviceName
        var samples: [MetricSample] = []

        for dn in range {
            let day = LocalDay(mockDayNumber: dn)
            let midnight = day.startDate(in: calendar)
            let dayEnd = min(day.interval(in: calendar).end, span.end)
            let dayStart = max(midnight, span.start)
            guard dayEnd > dayStart else { continue }

            // Workouts of the day.
            let plan = plan(dn: dn)
            var windows: [DateInterval] = []
            for workout in workouts(on: day) {
                windows.append(workout.interval)
                guard workout.interval.end > dayStart, workout.start < dayEnd else { continue }
                let series: [Double]
                let seriesStep: TimeInterval
                if workout.kind == .run, let run = plan.run {
                    series = runHeartRate(run, effort: runEffort(run, dn: dn), dn: dn)
                    seriesStep = 1
                } else if let lift = plan.lift {
                    series = liftHeartRate(lift, dn: dn)
                    seriesStep = 5
                } else {
                    continue
                }
                let stride = max(1, Int(5 / seriesStep))
                for i in Swift.stride(from: 0, to: series.count, by: stride) {
                    let t = workout.start.addingTimeInterval(Double(i) * seriesStep)
                    if t >= dayStart && t < dayEnd && t <= workout.end {
                        samples.append(MetricSample(date: t, value: series[i].rounded(), sourceName: device))
                    }
                }
            }

            // Background heart rate on a regular grid.
            let rhr = vitals(for: day)?.restingHeartRate ?? 54
            let sleepToday = sleepPlan(day: day, dn: dn)
            let sleepNext = sleepPlan(day: LocalDay(mockDayNumber: dn + 1), dn: dn + 1)
            var t = (dayStart.timeIntervalSinceReferenceDate / step).rounded(.up) * step
            while t < dayEnd.timeIntervalSinceReferenceDate {
                let date = Date(timeIntervalSinceReferenceDate: t)
                defer { t += step }
                if windows.contains(where: { $0.start <= date && date <= $0.end }) { continue }
                let seconds = date.timeIntervalSince(midnight)
                let asleep = (date >= sleepToday.sleepStart && date < sleepToday.sleepEnd)
                    || (date >= sleepNext.sleepStart && date < sleepNext.sleepEnd)
                let value: Double
                let n = noise
                if asleep {
                    let wave = sin(2 * .pi * date.timeIntervalSince(sleepToday.sleepStart) / 5_400)
                    value = rhr - 1 + 3 * wave + 1.5 * n.smooth(seconds / 300, key: dn, salt: 170)
                } else {
                    let hour = seconds / 3_600
                    let burst = n.smooth(seconds / 720, key: dn, salt: 171)
                    value = rhr + 9 + 5 * sin(2 * .pi * (hour - 11) / 24) + 22 * max(0, burst - 0.35) / 0.65
                        + 2 * n.smooth(seconds / 60, key: dn, salt: 172)
                }
                samples.append(MetricSample(date: date, value: value.rounded(), sourceName: device))
            }
        }
        samples.sort { $0.date < $1.date }
        return samples
    }
}
