import SwiftUI

/// A tiny normalised polyline (x, y in 0...1, y pointing down) for the run-list thumbnail.
struct TrainRoutePreview: Hashable, Sendable {
    var points: [CGPoint]
    var isEmpty: Bool { points.count < 2 }

    static let none = TrainRoutePreview(points: [])

    /// Projects the route, drops inaccurate fixes, simplifies (Douglas-Peucker) to at most `maxPoints`
    /// and fits it into the unit square with padding. Nonisolated: safe to call off the main actor.
    static func make(from route: [RouteLocation], maxPoints: Int = 64) -> TrainRoutePreview {
        let usable = route.filter { ($0.horizontalAccuracy ?? 0) <= 50 }
        let fixes = usable.count >= 2 ? usable : route
        guard fixes.count >= 2 else { return .none }
        let meanLatitude = fixes.reduce(0) { $0 + $1.latitude } / Double(fixes.count)
        let scale = cos(meanLatitude * .pi / 180)
        let xs = fixes.map { $0.longitude * scale }
        let ys = fixes.map { $0.latitude }
        let kept = TrainSeries.simplify(x: xs, y: ys, maxPoints: maxPoints)
        guard kept.count >= 2,
              let minX = kept.map({ xs[$0] }).min(), let maxX = kept.map({ xs[$0] }).max(),
              let minY = kept.map({ ys[$0] }).min(), let maxY = kept.map({ ys[$0] }).max() else { return .none }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return .none }
        let padding = 0.16
        let inner = 1 - padding * 2
        let offsetX = (1 - (maxX - minX) / span * inner) / 2
        let offsetY = (1 - (maxY - minY) / span * inner) / 2
        let points = kept.map { index in
            CGPoint(x: offsetX + (xs[index] - minX) / span * inner,
                    y: 1 - (offsetY + (ys[index] - minY) / span * inner))
        }
        return TrainRoutePreview(points: points)
    }

    /// Off-main entry point.
    @concurrent
    static func build(from route: [RouteLocation]) async -> TrainRoutePreview {
        make(from: route)
    }
}

/// Memoises route previews for the lifetime of the Train tab (runs never change once recorded).
@MainActor
final class TrainRouteCache {
    private var storage: [UUID: TrainRoutePreview] = [:]

    func cached(for id: UUID) -> TrainRoutePreview? { storage[id] }

    func preview(for id: UUID, repository: VigilRepository) async -> TrainRoutePreview {
        if let hit = storage[id] { return hit }
        let route = await repository.trainRoute(for: id)
        let preview = await TrainRoutePreview.build(from: route)
        storage[id] = preview
        return preview
    }
}

/// 76 pt route thumbnail: faint map-like grid with the simplified route, or a static placeholder.
/// The route loads in `.task`, which only runs once the (lazy) row is on screen.
struct TrainRouteThumbnail: View {
    let workout: Workout
    let cache: TrainRouteCache
    @Environment(AppContainer.self) private var container
    @State private var preview: TrainRoutePreview?

    var body: some View {
        ZStack {
            Color.vRunTint
            TrainThumbnailGrid().stroke(Color.vRunSoft.opacity(0.35), lineWidth: 1)
            if let preview, !preview.isEmpty {
                TrainRouteShape(points: preview.points)
                    .stroke(Color.vRun, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            } else {
                Image(systemName: workout.isIndoor ? "figure.run.treadmill" : "figure.run")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.vRun.opacity(0.7))
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(.rect(cornerRadius: VRadius.tile, style: .continuous))
        .accessibilityHidden(true)
        .task(id: workout.id) {
            guard workout.hasRoute else { return }
            if let hit = cache.cached(for: workout.id) {
                preview = hit
            } else {
                preview = await cache.preview(for: workout.id, repository: container.repository)
            }
        }
    }
}

private struct TrainThumbnailGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [1.0 / 3, 2.0 / 3] {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
            path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
        }
        return path
    }
}

private struct TrainRouteShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        return path
    }
}
