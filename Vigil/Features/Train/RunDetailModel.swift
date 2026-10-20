import CoreLocation
import MapKit
import Observation
import SwiftUI

/// How the route is coloured.
enum TrainRouteColorMode: String, CaseIterable, Hashable, Sendable {
    case pace
    case heartRate
}

/// A run of consecutive route segments sharing one colour bucket (0...4).
struct TrainRouteSegment: Identifiable, Sendable {
    var id: Int
    var coordinates: [CLLocationCoordinate2D]
    var bucket: Int
}

/// Everything heavy that Run detail derives from a `RunDetail`, computed off the main actor.
struct RunDetailPresentation: Sendable {
    var paceSegments: [TrainRouteSegment] = []
    var heartRateSegments: [TrainRouteSegment] = []
    var mapRect: MKMapRect?
    var start: CLLocationCoordinate2D?
    var end: CLLocationCoordinate2D?
    /// Series (≤ 240 points). `x` is metres when `xIsDistance`, otherwise seconds from the start.
    var pace: [TrainChartPoint] = []
    var heartRate: [TrainChartPoint] = []
    var elevation: [TrainChartPoint] = []
    var xIsDistance = true
    var xMax: Double = 0
    /// Fastest sustained pace (s/km), used for the "best" label.
    var bestPace: Double?
    var hasRoute: Bool { paceSegments.count + heartRateSegments.count > 0 && mapRect != nil }

    static let paceRange: ClosedRange<Double> = 120...1_200
    static let maxRoutePoints = 450
    static let maxSeriesPoints = 240

    /// Nonisolated and pure: safe for `@concurrent` use.
    static func make(from detail: RunDetail) -> RunDetailPresentation {
        var result = RunDetailPresentation()
        let details = detail.details
        let startDate = detail.workout.start

        // Chart x axis: distance when a cumulative-distance timeline exists, otherwise elapsed time.
        let timeline = details.cumulativeDistance
        let isDistance = timeline.count >= 2
        result.xIsDistance = isDistance
        let toX: (Date) -> Double = { date in
            isDistance
                ? (TrainSeries.interpolated(in: timeline, at: date) ?? 0)
                : max(0, date.timeIntervalSince(startDate))
        }
        result.xMax = result.xIsDistance ? (timeline.last?.value ?? detail.workout.distanceMeters ?? 0) : detail.workout.duration
        result.pace = TrainSeries.series(from: details.pace, maxPoints: maxSeriesPoints, x: toX) { paceRange.contains($0) }
        result.heartRate = TrainSeries.series(from: details.heartRate, maxPoints: maxSeriesPoints, x: toX) { $0 > 20 && $0 < 260 }
        result.elevation = TrainSeries.series(from: details.elevation, maxPoints: maxSeriesPoints, x: toX)
        let paceValues = details.pace.map(\.value).filter { paceRange.contains($0) }
        result.bestPace = paceValues.isEmpty ? nil : TrainSeries.percentile(paceValues, 0.03)

        guard !detail.workout.isIndoor else { return result }
        let fixes = details.route
        guard fixes.count >= 2 else { return result }

        let projection = RouteProjection(fixes)
        let xs = projection.xs, ys = projection.ys
        let kept = TrainSeries.simplify(x: xs, y: ys, maxPoints: maxRoutePoints)
        guard kept.count >= 2 else { return result }

        // Per-fix values for colouring, forward-filled over gaps.
        let paceAtFix: [Double?] = fixes.enumerated().map { index, fix in
            if !details.pace.isEmpty {
                return TrainSeries.nearestValue(in: details.pace, at: fix.timestamp).flatMap { paceRange.contains($0) ? $0 : nil }
            }
            if let speed = fix.speed, speed > 0.3 { return 1_000 / speed }
            guard index > 0 else { return nil }
            let previous = fixes[index - 1]
            let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
            let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: fix.latitude, longitude: fix.longitude))
            return seconds > 0 && meters > 0.5 ? seconds / meters * 1_000 : nil
        }
        let hrAtFix: [Double?] = fixes.map { TrainSeries.nearestValue(in: details.heartRate, at: $0.timestamp) }
        let times = fixes.map(\.timestamp)
        let paceSegmentValues = segmentValues(smoothed(paceAtFix, times: times), kept: kept)
        let hrSegmentValues = segmentValues(smoothed(hrAtFix, times: times), kept: kept)

        let coordinates = fixes.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let paceBuckets = quintileBuckets(paceSegmentValues, fasterIsHigher: true)
        let hrBuckets = paceBucketsForHeartRate(hrSegmentValues, zones: detail.zones)
        result.paceSegments = merge(kept: kept, coordinates: coordinates, buckets: paceBuckets)
        result.heartRateSegments = merge(kept: kept, coordinates: coordinates, buckets: hrBuckets)
        result.start = coordinates.first
        result.end = coordinates.last
        result.mapRect = boundingRect(kept.map { coordinates[$0] })
        return result
    }

    @concurrent
    static func build(from detail: RunDetail) async -> RunDetailPresentation {
        make(from: detail)
    }

    // MARK: Helpers

    /// Rolling mean over a centred time window (default 30 s) after forward/back-filling gaps, so colours
    /// don't flicker with every GPS fix.
    static func smoothed(_ values: [Double?], times: [Date], window: TimeInterval = 30) -> [Double?] {
        guard values.count == times.count, values.contains(where: { $0 != nil }) else { return values }
        var filled: [Double] = []
        filled.reserveCapacity(values.count)
        var last: Double?
        for value in values {
            if let value { last = value }
            filled.append(value ?? last ?? .nan)
        }
        let firstValid = filled.first { !$0.isNaN } ?? 0
        for index in filled.indices where filled[index].isNaN { filled[index] = firstValid }
        var prefix: [Double] = [0]
        prefix.reserveCapacity(filled.count + 1)
        for value in filled { prefix.append(prefix[prefix.count - 1] + value) }
        var lower = 0, upper = 0
        let half = window / 2
        return filled.indices.map { index in
            while times[index].timeIntervalSince(times[lower]) > half { lower += 1 }
            if upper < index { upper = index }
            while upper + 1 < times.count, times[upper + 1].timeIntervalSince(times[index]) <= half { upper += 1 }
            return (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
        }
    }

    /// Average value across each simplified segment (nil when the stretch has no data).
    static func segmentValues(_ values: [Double?], kept: [Int]) -> [Double?] {
        var filled: [Double?] = []
        var last: Double?
        for value in values {
            if let value { last = value }
            filled.append(value ?? last)
        }
        // Back-fill the leading gap.
        if let firstValid = filled.first(where: { $0 != nil }) {
            for index in filled.indices where filled[index] == nil { filled[index] = firstValid }
        }
        var prefix: [Double] = [0]
        prefix.reserveCapacity(filled.count + 1)
        for value in filled { prefix.append(prefix[prefix.count - 1] + (value ?? 0)) }
        let hasData = filled.contains { $0 != nil }
        return (0..<(kept.count - 1)).map { segment in
            guard hasData else { return nil }
            let from = kept[segment], to = kept[segment + 1]
            return (prefix[to + 1] - prefix[from]) / Double(to - from + 1)
        }
    }

    /// Splits values into five equal-count buckets; 4 = fastest (lowest pace number).
    static func quintileBuckets(_ values: [Double?], fasterIsHigher: Bool) -> [Int] {
        let present = values.compactMap { $0 }
        guard present.count > 1 else { return values.map { _ in 2 } }
        let t20 = TrainSeries.percentile(present, 0.2), t40 = TrainSeries.percentile(present, 0.4)
        let t60 = TrainSeries.percentile(present, 0.6), t80 = TrainSeries.percentile(present, 0.8)
        return values.map { value in
            guard let value else { return 2 }
            let slowToFast = value > t80 ? 0 : value > t60 ? 1 : value > t40 ? 2 : value > t20 ? 3 : 4
            return fasterIsHigher ? slowToFast : 4 - slowToFast
        }
    }

    static func paceBucketsForHeartRate(_ values: [Double?], zones: HeartRateZones) -> [Int] {
        values.map { value in
            guard let value else { return 0 }
            return min(max((zones.zone(for: value) ?? 1) - 1, 0), 4)
        }
    }

    /// Joins neighbouring segments with the same bucket into single polylines.
    static func merge(kept: [Int], coordinates: [CLLocationCoordinate2D], buckets: [Int]) -> [TrainRouteSegment] {
        var segments: [TrainRouteSegment] = []
        for segment in 0..<(kept.count - 1) {
            let a = coordinates[kept[segment]], b = coordinates[kept[segment + 1]]
            let bucket = buckets[segment]
            if let last = segments.last, last.bucket == bucket {
                segments[segments.count - 1].coordinates.append(b)
            } else {
                segments.append(TrainRouteSegment(id: segments.count, coordinates: [a, b], bucket: bucket))
            }
        }
        return segments
    }

    static func boundingRect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // Pad so the route sits comfortably inside the camera, with a minimum visible span (~600 m).
        let minimum = MKMapPointsPerMeterAtLatitude(coordinates[0].latitude) * 600
        let width = max(rect.width, minimum), height = max(rect.height, minimum)
        let padded = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        return padded.insetBy(dx: -width * 0.25, dy: -height * 0.35)
    }
}

enum RunDetailLoadState {
    case loading
    case loaded(RunDetail)
    case failed
}

@MainActor
@Observable
final class RunDetailModel {
    private(set) var state: RunDetailLoadState = .loading
    private(set) var presentation = RunDetailPresentation()
    var colorMode: TrainRouteColorMode = .pace

    func load(id: UUID, repository: VigilRepository) async {
        // Keep the content on screen while reloading (e.g. after a units change).
        if case .loaded = state {} else { state = .loading }
        do {
            let detail = try await repository.runDetail(id: id)
            let built = await RunDetailPresentation.build(from: detail)
            presentation = built
            state = .loaded(detail)
        } catch {
            state = .failed
        }
    }

    var segments: [TrainRouteSegment] {
        colorMode == .pace ? presentation.paceSegments : presentation.heartRateSegments
    }
}
