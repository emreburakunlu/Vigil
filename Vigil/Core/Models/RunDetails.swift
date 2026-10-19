import Foundation

/// A GPS point of a workout route (`CLLocation` flattened to a Sendable value).
struct RouteLocation: Hashable, Codable, Sendable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Altitude above sea level, metres.
    var altitude: Double?
    /// Horizontal accuracy, metres (filter points > ~50 m).
    var horizontalAccuracy: Double?
    /// Instantaneous speed, m/s, if reported.
    var speed: Double?
}

/// One split (per km or per mile, following the user's unit system).
struct RunSplit: Hashable, Codable, Sendable, Identifiable {
    /// 1-based split number.
    var index: Int
    /// Distance covered by this split, metres (1000 / 1609.344, or less for the final partial split).
    var distanceMeters: Double
    /// Time for this split, seconds.
    var duration: TimeInterval
    /// Average heart rate during the split, bpm.
    var averageHeartRate: Double?
    /// Net elevation change across the split, metres (+ climb, − descent).
    var elevationChangeMeters: Double?
    /// True for the final split shorter than a full unit.
    var isPartial: Bool

    var id: Int { index }

    /// Pace normalized to seconds per kilometre (format with `VigilFormatter.pace`).
    var paceSecondsPerKilometer: Double {
        distanceMeters > 0 ? duration / (distanceMeters / 1_000) : 0
    }
}

/// Averages of the running-form metrics shown on Run detail. Any can be missing.
struct RunningFormSummary: Hashable, Codable, Sendable {
    /// Steps per minute.
    var cadence: Double?
    /// Metres.
    var strideLength: Double?
    /// Milliseconds.
    var groundContactTime: Double?
    /// Centimetres.
    var verticalOscillation: Double?
    /// Watts.
    var power: Double?

    static let empty = RunningFormSummary()
}

/// Everything needed by Run detail besides the `Workout` itself.
/// Series are ordered by date and expressed in the units documented per property.
struct RunDetails: Hashable, Codable, Sendable {
    var workoutID: UUID
    /// GPS route; empty for indoor runs or when location access was not granted.
    var route: [RouteLocation]
    /// Heart rate, bpm.
    var heartRate: [MetricSample]
    /// Pace, seconds per kilometre (from running speed samples or the route).
    var pace: [MetricSample]
    /// Altitude, metres.
    var elevation: [MetricSample]
    /// Cumulative distance since start, metres (used for splits & best efforts when no route).
    var cumulativeDistance: [MetricSample]
    /// Cadence, steps/min.
    var cadence: [MetricSample]
    /// Stride length, metres.
    var strideLength: [MetricSample]
    /// Ground contact time, ms.
    var groundContactTime: [MetricSample]
    /// Vertical oscillation, cm.
    var verticalOscillation: [MetricSample]
    /// Running power, W.
    var power: [MetricSample]
    /// Averages of the form series.
    var form: RunningFormSummary

    init(workoutID: UUID, route: [RouteLocation] = [], heartRate: [MetricSample] = [], pace: [MetricSample] = [],
         elevation: [MetricSample] = [], cumulativeDistance: [MetricSample] = [], cadence: [MetricSample] = [],
         strideLength: [MetricSample] = [], groundContactTime: [MetricSample] = [],
         verticalOscillation: [MetricSample] = [], power: [MetricSample] = [], form: RunningFormSummary = .empty) {
        self.workoutID = workoutID
        self.route = route
        self.heartRate = heartRate
        self.pace = pace
        self.elevation = elevation
        self.cumulativeDistance = cumulativeDistance
        self.cadence = cadence
        self.strideLength = strideLength
        self.groundContactTime = groundContactTime
        self.verticalOscillation = verticalOscillation
        self.power = power
        self.form = form
    }
}
