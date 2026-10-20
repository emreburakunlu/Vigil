import Foundation

/// Equirectangular projection of a route into planar coordinates (x = longitude scaled by cos(mean latitude),
/// y = latitude). Shared by the list thumbnail and the Run detail map. Points are assumed to be pre-filtered
/// for accuracy by the data source.
struct RouteProjection: Sendable {
    let xs: [Double]
    let ys: [Double]

    var count: Int { xs.count }

    init(_ route: [RouteLocation]) {
        let meanLatitude = route.isEmpty ? 0 : route.reduce(0) { $0 + $1.latitude } / Double(route.count)
        let scale = cos(meanLatitude * .pi / 180)
        xs = route.map { $0.longitude * scale }
        ys = route.map(\.latitude)
    }
}
