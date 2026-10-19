import Foundation

extension MockHealthDataSource {
    // MARK: Workout list

    func workouts(on day: LocalDay) -> [Workout] {
        let dn = day.mockDayNumber
        guard hasData, dn <= todayDN, dn >= firstDN else { return [] }
        let plan = plan(dn: dn)
        let midnight = day.startDate(in: calendar)
        var result: [Workout] = []
        if let run = plan.run {
            let start = midnight.addingTimeInterval(run.startSeconds)
            let km = run.distance / 1_000
            var gain: Double?
            var loss: Double?
            if !run.indoor {
                let change = course(dn: dn).elevationChange(over: run.distance)
                gain = change.gain.rounded()
                loss = change.loss.rounded()
            }
            result.append(Workout(
                id: Self.workoutID(day: day, slot: 1), kind: .run,
                activityName: run.indoor ? "Indoor Run" : "Outdoor Run", title: run.title,
                start: start, end: start.addingTimeInterval(run.duration), duration: run.duration,
                activeEnergyKilocalories: (km * 62 + noise.value(dn, 150, -8, 8)).rounded(),
                totalEnergyKilocalories: (km * 62 + run.duration / 60 * 1.2).rounded(),
                averageHeartRate: run.averageHeartRate, maxHeartRate: run.maxHeartRate,
                distanceMeters: run.distance, elevationGainMeters: gain, elevationLossMeters: loss,
                source: Self.workoutApp, heartRateSource: Self.watch, isIndoor: run.indoor, hasRoute: !run.indoor))
        }
        if let lift = plan.lift {
            let start = midnight.addingTimeInterval(lift.startSeconds.rounded())
            let minutes = lift.duration / 60
            result.append(Workout(
                id: Self.workoutID(day: day, slot: 2), kind: .strength,
                activityName: "Traditional Strength Training", title: lift.title,
                start: start, end: start.addingTimeInterval(lift.duration), duration: lift.duration,
                activeEnergyKilocalories: (minutes * 5.6).rounded(), totalEnergyKilocalories: (minutes * 6.8).rounded(),
                averageHeartRate: lift.averageHeartRate, maxHeartRate: lift.maxHeartRate,
                distanceMeters: nil, elevationGainMeters: nil, elevationLossMeters: nil,
                source: Self.hevy, heartRateSource: Self.watch, isIndoor: true, hasRoute: false))
        }
        return result.filter { $0.end <= referenceDate }
    }

    /// Stable UUIDs encoding the day so `workout(id:)` can regenerate without a lookup table.
    static func workoutID(day: LocalDay, slot: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", day.key * 10 + slot))!
    }

    static func day(fromWorkoutID id: UUID) -> LocalDay? {
        guard let raw = Int(id.uuidString.suffix(12)) else { return nil }
        let key = raw / 10
        return LocalDay(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
    }

    // MARK: Run details

    /// Per-second effort (speed ÷ average speed) of a run; mean is exactly 1.
    func runEffort(_ run: MockRunPlan, dn: Int) -> [Double] {
        let count = Int(run.duration) + 1
        let n = noise
        func shape(_ tau: Double) -> Double {
            switch run.type {
            case .easy:
                return (1 - 0.07 * exp(-tau / 0.04)) * (1 - 0.02 * tau) * (1 + 0.03 * sin(2 * .pi * 3 * tau + 1))
            case .long:
                return (1 - 0.08 * exp(-tau / 0.03)) * (1 - 0.05 * tau) * (1 + 0.04 * sin(2 * .pi * 5 * tau + 2))
            case .tempo:
                return 0.88 + 0.26 * mockSmoothstep(0.17, 0.20, tau) - 0.30 * mockSmoothstep(0.78, 0.81, tau)
            case .intervals:
                if tau < 0.22 { return 0.86 }
                if tau >= 0.80 { return 0.84 }
                let phase = ((tau - 0.22) / 0.58 * 6).truncatingRemainder(dividingBy: 1)
                let hard = mockSmoothstep(0.0, 0.06, phase) - mockSmoothstep(0.52, 0.58, phase)
                return 0.78 + 0.50 * hard
            case .race5k, .race10k:
                return (1 + 0.04 * exp(-tau / 0.03)) * (1 + 0.03 * mockSmoothstep(0.93, 0.99, tau))
            }
        }
        var effort = (0..<count).map { i -> Double in
            let tau = Double(i) / Double(max(count - 1, 1))
            return shape(tau) * (1 + 0.012 * n.smooth(Double(i) / 12, key: dn, salt: 160))
        }
        let mean = effort.reduce(0, +) / Double(count)
        for i in effort.indices { effort[i] /= mean }
        return effort
    }

    /// Heart-rate series (1 Hz) of a run: lags effort, drifts upwards, mean and max match the workout.
    func runHeartRate(_ run: MockRunPlan, effort: [Double], dn: Int) -> [Double] {
        let n = noise
        var hr = 100.0
        var raw: [Double] = []
        raw.reserveCapacity(effort.count)
        for (i, e) in effort.enumerated() {
            let tau = Double(i) / Double(max(effort.count - 1, 1))
            let target = run.averageHeartRate + 90 * (e - 1) + 7 * tau
            hr += (target - hr) / 25
            raw.append(hr + 1.3 * n.smooth(Double(i) / 6, key: dn, salt: 161))
        }
        return Self.fit(raw, mean: run.averageHeartRate, maximum: run.maxHeartRate)
    }

    /// Heart-rate series (every 5 s) of a lifting session: warm-up, then set / rest oscillation.
    func liftHeartRate(_ lift: MockLiftPlan, dn: Int) -> [Double] {
        let n = noise
        let count = Int(lift.duration / 5) + 1
        let raw = (0..<count).map { i -> Double in
            let t = Double(i) * 5
            let warm = 1 - exp(-t / 240)
            let set = pow(sin(.pi * t / 150), 2)   // ~2.5-minute set + rest cycles
            return lift.averageHeartRate - 12 + 9 * warm + 16 * set * warm + 2.5 * n.smooth(t / 20, key: dn, salt: 162)
        }
        return Self.fit(raw, mean: lift.averageHeartRate, maximum: lift.maxHeartRate)
    }

    /// Shifts/scales a series so its mean and maximum equal the targets.
    static func fit(_ series: [Double], mean: Double, maximum: Double) -> [Double] {
        guard !series.isEmpty else { return series }
        let current = series.reduce(0, +) / Double(series.count)
        let peak = (series.max() ?? current) - current
        let scale = peak > 0.5 ? mockClamp((maximum - mean) / peak, 0.6, 1.3) : 1
        return series.map { max(70, mean + ($0 - current) * scale) }
    }

    func buildRunDetails(for run: Workout, day: LocalDay) -> RunDetails {
        let dn = day.mockDayNumber
        let n = noise
        let plan = plan(dn: dn).run
        guard let plan else { return RunDetails(workoutID: run.id) }
        let effort = runEffort(plan, dn: dn)
        let count = effort.count
        let averageSpeed = plan.distance / plan.duration
        let hr = runHeartRate(plan, effort: effort, dn: dn)

        // Speed → cumulative distance, scaled so the run covers exactly the workout distance.
        var speed = effort.map { $0 * averageSpeed }
        var cumulative = [Double](repeating: 0, count: count)
        for i in 1..<count { cumulative[i] = cumulative[i - 1] + (speed[i - 1] + speed[i]) / 2 }
        let scale = plan.distance / max(cumulative[count - 1], 1)
        for i in 0..<count { speed[i] *= scale; cumulative[i] *= scale }

        let watch = Self.watch.deviceName
        let start = run.start
        var pace: [MetricSample] = [], hrSamples: [MetricSample] = [], distanceSamples: [MetricSample] = []
        pace.reserveCapacity(count); hrSamples.reserveCapacity(count); distanceSamples.reserveCapacity(count)
        for i in 0..<count {
            let t = start.addingTimeInterval(Double(i))
            let window = speed[max(0, i - 4)...i]
            let smoothed = window.reduce(0, +) / Double(window.count)
            pace.append(MetricSample(date: t, value: mockClamp(1_000 / max(smoothed, 0.5), 150, 900), sourceName: watch))
            hrSamples.append(MetricSample(date: t, value: hr[i].rounded(), sourceName: watch))
            distanceSamples.append(MetricSample(date: t, value: cumulative[i], sourceName: watch))
        }

        // Route + elevation (outdoor only).
        var route: [RouteLocation] = []
        var elevation: [MetricSample] = []
        if !plan.indoor {
            let course = course(dn: dn)
            let table = MockCoursePath(course)
            route.reserveCapacity(count)
            elevation.reserveCapacity(count)
            let cosLat = cos(course.centerLatitude * .pi / 180)
            for i in 0..<count {
                let t = start.addingTimeInterval(Double(i))
                let p = table.position(atDistance: cumulative[i])
                let altitude = course.altitude(at: cumulative[i])
                route.append(RouteLocation(
                    timestamp: t,
                    latitude: course.centerLatitude + p.y / 111_320,
                    longitude: course.centerLongitude + p.x / (111_320 * cosLat),
                    altitude: altitude,
                    horizontalAccuracy: 3.5 + 2 * (n.smooth(Double(i) / 40, key: dn, salt: 163) + 1) / 2,
                    speed: speed[i]))
                elevation.append(MetricSample(date: t, value: altitude, sourceName: watch))
            }
        }

        // Running form (every 5 s): faster → higher cadence, shorter ground contact, less bounce, more power.
        var cadence: [MetricSample] = [], strideSamples: [MetricSample] = [], contact: [MetricSample] = []
        var oscillation: [MetricSample] = [], power: [MetricSample] = []
        let withPower = scenario != .partialData
        var sums = (cadence: 0.0, stride: 0.0, contact: 0.0, oscillation: 0.0, power: 0.0)
        var samples = 0
        for i in stride(from: 0, to: count, by: 5) {
            let t = start.addingTimeInterval(Double(i))
            let v = speed[i]
            let fatigue = Double(i) / Double(count)
            let c = mockClamp(156 + 6.4 * v + 1.2 * n.smooth(Double(i) / 25, key: dn, salt: 164) - 1.5 * fatigue, 165, 182)
            let s = v * 60 / c
            let g = mockClamp(292 - 15 * v + 2.5 * n.smooth(Double(i) / 30, key: dn, salt: 165) + 4 * fatigue, 220, 260)
            let o = mockClamp(9.6 - 0.55 * v + 0.2 * n.smooth(Double(i) / 30, key: dn, salt: 166), 7, 9)
            let w = mockClamp(245 + 50 * (v - 3.2) + 4 * n.smooth(Double(i) / 20, key: dn, salt: 167) - 5 * fatigue, 230, 300)
            cadence.append(MetricSample(date: t, value: c.rounded(), sourceName: watch))
            strideSamples.append(MetricSample(date: t, value: (s * 100).rounded() / 100, sourceName: watch))
            contact.append(MetricSample(date: t, value: g.rounded(), sourceName: watch))
            oscillation.append(MetricSample(date: t, value: (o * 10).rounded() / 10, sourceName: watch))
            if withPower { power.append(MetricSample(date: t, value: w.rounded(), sourceName: watch)) }
            sums.cadence += c; sums.stride += s; sums.contact += g; sums.oscillation += o; sums.power += w
            samples += 1
        }
        let k = Double(max(samples, 1))
        let form = RunningFormSummary(cadence: (sums.cadence / k).rounded(), strideLength: ((sums.stride / k) * 100).rounded() / 100,
                                      groundContactTime: (sums.contact / k).rounded(),
                                      verticalOscillation: ((sums.oscillation / k) * 10).rounded() / 10,
                                      power: withPower ? (sums.power / k).rounded() : nil)
        return RunDetails(workoutID: run.id, route: route, heartRate: hrSamples, pace: pace, elevation: elevation,
                          cumulativeDistance: distanceSamples, cadence: cadence, strideLength: strideSamples,
                          groundContactTime: contact, verticalOscillation: oscillation, power: power, form: form)
    }
}

/// One lap of a course as an arc-length-uniform polyline (metres east/north of the course centre).
struct MockCoursePath {
    private let xs: [Double]
    private let ys: [Double]
    private let lapLength: Double
    private let startFraction: Double
    private let reversed: Bool

    init(_ course: MockCourse) {
        let samples = 3_600
        var px = [Double](), py = [Double](), arc = [Double]()
        px.reserveCapacity(samples + 1); py.reserveCapacity(samples + 1); arc.reserveCapacity(samples + 1)
        for k in 0...samples {
            let theta = 2 * Double.pi * Double(k) / Double(samples)
            let r = 1 + course.shapeA2 * cos(2 * theta + course.shapePhase2) + course.shapeA3 * cos(3 * theta + course.shapePhase3)
            px.append(r * cos(theta) * 1.3)
            py.append(r * sin(theta) * 0.75)
            if k == 0 {
                arc.append(0)
            } else {
                arc.append(arc[k - 1] + ((px[k] - px[k - 1]) * (px[k] - px[k - 1]) + (py[k] - py[k - 1]) * (py[k] - py[k - 1])).squareRoot())
            }
        }
        let perimeter = arc[samples]
        let scale = course.lapLength / perimeter
        let count = 1_200
        var rx = [Double](), ry = [Double]()
        rx.reserveCapacity(count + 1); ry.reserveCapacity(count + 1)
        var j = 0
        for i in 0...count {
            let target = perimeter * Double(i) / Double(count)
            while j < samples - 1 && arc[j + 1] < target { j += 1 }
            let span = arc[j + 1] - arc[j]
            let f = span > 0 ? (target - arc[j]) / span : 0
            rx.append((px[j] + (px[j + 1] - px[j]) * f) * scale)
            ry.append((py[j] + (py[j + 1] - py[j]) * f) * scale)
        }
        xs = rx
        ys = ry
        lapLength = course.lapLength
        startFraction = course.startFraction
        reversed = course.reversed
    }

    func position(atDistance distance: Double) -> (x: Double, y: Double) {
        var u = (distance / lapLength + startFraction).truncatingRemainder(dividingBy: 1)
        if reversed { u = 1 - u }
        let scaled = u * Double(xs.count - 1)
        let i = min(xs.count - 2, Int(scaled))
        let f = scaled - Double(i)
        return (xs[i] + (xs[i + 1] - xs[i]) * f, ys[i] + (ys[i + 1] - ys[i]) * f)
    }
}
