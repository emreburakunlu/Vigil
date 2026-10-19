import Foundation
import Testing
@testable import Vigil

struct TrainTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func downsampleKeepsEndpointsAndPeaks() {
        let points = (0..<7_200).map { TrainChartPoint(id: $0, x: Double($0), y: $0 == 3_000 ? 500 : Double($0 % 7)) }
        let sampled = TrainSeries.downsample(points, to: 240)
        #expect(sampled.count == 240)
        #expect(sampled.first?.x == 0)
        #expect(sampled.last?.x == 7_199)
        #expect(sampled.contains { $0.y == 500 })
    }

    @Test func downsampleLeavesShortSeriesAlone() {
        let points = (0..<10).map { TrainChartPoint(id: $0, x: Double($0), y: 1) }
        #expect(TrainSeries.downsample(points, to: 240).count == 10)
    }

    @Test func simplifyDropsCollinearPoints() {
        let xs = (0..<100).map(Double.init)
        let ys = [Double](repeating: 0, count: 100)
        #expect(TrainSeries.simplify(x: xs, y: ys, epsilon: 0.01) == [0, 99])
    }

    @Test func simplifyHonoursMaxPoints() {
        let xs = (0..<7_200).map { cos(Double($0) / 200) * 100 + Double($0 % 3) * 0.01 }
        let ys = (0..<7_200).map { sin(Double($0) / 200) * 100 }
        let kept = TrainSeries.simplify(x: xs, y: ys, maxPoints: 450)
        #expect(kept.count <= 450)
        #expect(kept.first == 0 && kept.last == 7_199)
    }

    @Test func routePreviewIsNormalised() {
        let start = Date(timeIntervalSince1970: 0)
        let route = (0..<1_000).map { i in
            RouteLocation(timestamp: start.addingTimeInterval(Double(i)), latitude: 50 + sin(Double(i) / 100) * 0.01,
                          longitude: 8 + cos(Double(i) / 100) * 0.01, altitude: nil, horizontalAccuracy: 5, speed: nil)
        }
        let preview = TrainRoutePreview.make(from: route)
        #expect(!preview.isEmpty)
        #expect(preview.points.count <= 64)
        #expect(preview.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(TrainRoutePreview.make(from: []).isEmpty)
    }

    @Test func nearestAndInterpolatedLookups() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = [MetricSample(date: t0, value: 0), MetricSample(date: t0.addingTimeInterval(10), value: 100)]
        #expect(TrainSeries.nearestValue(in: samples, at: t0.addingTimeInterval(3)) == 0)
        #expect(TrainSeries.nearestValue(in: samples, at: t0.addingTimeInterval(8)) == 100)
        #expect(TrainSeries.interpolated(in: samples, at: t0.addingTimeInterval(5)) == 50)
    }

    @Test func distanceTicksFollowUnits() {
        let metric = TrainSeries.distanceTicks(maxMeters: 8_040, formatter: VigilFormatter(units: .metric))
        #expect(metric.first == 0 && metric.count <= 5)
        let imperial = TrainSeries.distanceTicks(maxMeters: 8_040, formatter: VigilFormatter(units: .imperial))
        #expect(abs(imperial[1] - 2 * 1_609.344) < 0.01)
    }

    @Test func barFractions() {
        #expect(TrainFormatting.barFractions([0, 5, 10]) == [0, 0.5, 1])
        #expect(TrainFormatting.barFractions([0, 0]) == [0, 0])
    }

    @Test func splitBarFractionFasterIsLonger() {
        let fast = TrainFormatting.splitBarFraction(pace: 300, fastest: 300, slowest: 340)
        let slow = TrainFormatting.splitBarFraction(pace: 340, fastest: 300, slowest: 340)
        #expect(fast == 1 && slow == 0.25)
        #expect(TrainFormatting.splitBarFraction(pace: 300, fastest: 300, slowest: 300) == 1)
    }

    @Test func monthGroupsPreserveOrder() {
        func summary(_ date: Date) -> WorkoutSummary {
            WorkoutSummary(workout: Workout(id: UUID(), kind: .run, activityName: "Run", title: nil, start: date, end: date, duration: 1,
                                            source: DataSourceInfo(name: "Test"), isIndoor: false, hasRoute: false), strain: nil)
        }
        let oct = Date(timeIntervalSince1970: 1_792_400_000)
        let items = [summary(oct), summary(oct.addingTimeInterval(-86_400)), summary(oct.addingTimeInterval(-40 * 86_400))]
        let groups = TrainFormatting.monthGroups(items, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].items.count == 2)
    }

    @Test func zoneFractionsHandleEmpty() {
        #expect(TrainFormatting.zoneFractions(ZoneDurations()) == [0, 0, 0, 0, 0])
        #expect(TrainFormatting.zoneFractions(ZoneDurations(seconds: [10, 10, 0, 0, 0]))[0] == 0.5)
    }

    @Test func quintileBucketsOrderFasterHigher() {
        let values: [Double?] = [300, 310, 320, 330, 340]
        let buckets = RunDetailPresentation.quintileBuckets(values, fasterIsHigher: true)
        #expect(buckets.first == 4 && buckets.last == 0)
    }
}
