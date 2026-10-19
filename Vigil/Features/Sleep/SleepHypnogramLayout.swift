import Foundation

/// Geometry of the stage timeline, in unit coordinates (x: 0...1 of the night, lane: 0 = Awake ... 3 = Deep).
/// Pure so the segment-to-pixel mapping can be tested; `SleepHypnogramView` only scales it.
struct SleepHypnogramLayout: Equatable, Sendable {
    struct Bar: Equatable, Sendable {
        var lane: Int
        /// Start and end as fractions of the night.
        var start: Double
        var end: Double
        var stage: SleepStage
    }

    /// Vertical connector between two consecutive bars in different lanes.
    struct Link: Equatable, Sendable {
        var x: Double
        var fromLane: Int
        var toLane: Int
    }

    struct Tick: Equatable, Sendable {
        var fraction: Double
        var date: Date
    }

    var start: Date
    var end: Date
    var bars: [Bar]
    var links: [Link]

    static let laneCount = SleepStage.hypnogramStages.count

    /// Lane for a stage; unspecified asleep is drawn in the Core lane. `.inBed` has no lane.
    static func lane(for stage: SleepStage) -> Int? {
        switch stage {
        case .awake: 0
        case .rem: 1
        case .core, .asleepUnspecified: 2
        case .deep: 3
        case .inBed: nil
        }
    }

    /// Builds the layout from a night's segments; nil when there is nothing to draw.
    init?(segments: [SleepSegment]) {
        let drawable = segments
            .filter { Self.lane(for: $0.stage) != nil && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard let first = drawable.first, let last = drawable.max(by: { $0.end < $1.end }) else { return nil }
        let span = last.end.timeIntervalSince(first.start)
        guard span > 0 else { return nil }
        start = first.start
        end = last.end
        var bars: [Bar] = []
        var links: [Link] = []
        for segment in drawable {
            guard let lane = Self.lane(for: segment.stage) else { continue }
            let x0 = segment.start.timeIntervalSince(first.start) / span
            let x1 = segment.end.timeIntervalSince(first.start) / span
            if let previous = bars.last, previous.lane != lane {
                links.append(Link(x: x0, fromLane: previous.lane, toLane: lane))
            }
            bars.append(Bar(lane: lane, start: x0, end: x1, stage: segment.stage))
        }
        self.bars = bars
        self.links = links
    }

    /// Whole-hour ticks (every 1, 2 or 3 hours so at most about five labels) inside the night.
    func ticks(calendar: Calendar) -> [Tick] {
        let hours = end.timeIntervalSince(start) / 3600
        let step = hours <= 5 ? 1 : (hours <= 10 ? 2 : 3)
        let span = end.timeIntervalSince(start)
        var result: [Tick] = []
        var cursor = start.addingTimeInterval(-1)
        while let next = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime),
              next <= end {
            cursor = next
            if calendar.component(.hour, from: next) % step == 0 {
                result.append(Tick(fraction: next.timeIntervalSince(start) / span, date: next))
            }
        }
        return result
    }
}
