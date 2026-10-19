import MapKit
import SwiftUI

/// Colour ramp for the route. Pace runs slow → fast (warm yellow to blue), heart rate follows the zone colours.
enum TrainRoutePalette {
    static func color(bucket: Int, mode: TrainRouteColorMode) -> Color {
        switch mode {
        case .pace:
            [Color.vWarning, Color.vStrain, Color.vMove, Color.vSleep, Color.vRun][min(max(bucket, 0), 4)]
        case .heartRate:
            Color.vZone(bucket + 1)
        }
    }
}

/// MapKit route coloured by pace or heart rate: one polyline per run of same-coloured segments,
/// simplified off the main actor, camera fitted to the route.
struct RunRouteMap: View {
    let presentation: RunDetailPresentation
    let mode: TrainRouteColorMode
    let summary: String

    var body: some View {
        Map(initialPosition: presentation.mapRect.map { .rect($0) } ?? .automatic, interactionModes: []) {
            ForEach(mode == .pace ? presentation.paceSegments : presentation.heartRateSegments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(TrainRoutePalette.color(bucket: segment.bucket, mode: mode),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let start = presentation.start {
                Annotation("Start", coordinate: start, anchor: .center) { TrainRouteDot(color: .vRecovery) }
            }
            if let end = presentation.end {
                Annotation("Finish", coordinate: end, anchor: .center) { TrainRouteDot(color: .vInk) }
            }
        }
        .mapControlVisibility(.hidden)
        .mapStyle(.standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}

private struct TrainRouteDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.vInkOnAccent, lineWidth: 3))
    }
}

/// "Slower ▮▮▮▮▮ Faster" legend that sits on the map.
struct RunRouteLegend: View {
    let mode: TrainRouteColorMode

    var body: some View {
        HStack(spacing: VSpacing.m) {
            Text(mode == .pace ? "Slower" : "Zone 1")
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { bucket in
                    Rectangle().fill(TrainRoutePalette.color(bucket: bucket, mode: mode)).frame(height: 8)
                        .clipShape(.rect(cornerRadius: 2))
                }
            }
            Text(mode == .pace ? "Faster" : "Zone 5")
        }
        .font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
        .foregroundStyle(Color.vInkLabel)
        .padding(.horizontal, VSpacing.l)
        .padding(.vertical, VSpacing.s)
        .background(Color.vCard.opacity(0.92), in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .pace ? "Route colour scale, slower to faster pace" : "Route colour scale, heart rate zone 1 to zone 5")
    }
}

/// Pace / Heart rate switch (sits in the navigation bar over the map).
struct RunRouteModePicker: View {
    @Binding var mode: TrainRouteColorMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrainRouteColorMode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    Text(option == .pace ? "Pace" : "Heart rate")
                        .font(.vCustom(.body, size: 13.5, weight: .bold, relativeTo: .footnote))
                        .foregroundStyle(mode == option ? Color.vInkOnInverse : Color.vInk)
                        .padding(.horizontal, VSpacing.xl)
                        .frame(minHeight: 36)
                        .background(mode == option ? Color.vInverseFill : Color.clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color route by")
    }
}
