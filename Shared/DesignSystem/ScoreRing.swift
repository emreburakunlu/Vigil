import SwiftUI

// MARK: - Score rings
//
// Owner: design-system agent. Geometry from Design/Main.dc.html (98 pt ring, r = 43/100, stroke 9/100,
// round caps, starts at 12 o'clock) and Onb1-Welcome.dc.html (three concentric rings).
// Shared so the widget extension can draw the same rings.

/// The three headline scores and their colours.
enum VScoreKind: String, CaseIterable, Sendable {
    case recovery, sleep, strain

    var color: Color {
        switch self {
        case .recovery: .vRecovery
        case .sleep: .vSleep
        case .strain: .vStrain
        }
    }

    var track: Color {
        switch self {
        case .recovery: .vRecoveryTint
        case .sleep: .vSleepTint
        case .strain: .vStrainTint
        }
    }

    /// Text colour for the caption under the ring ("Green", "7h 42m", "Moderate").
    var ink: Color {
        switch self {
        case .recovery: .vRecoveryInk
        case .sleep: .vSleepInk
        case .strain: .vStrainInk
        }
    }

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .strain: "Strain"
        }
    }
}

/// One circular progress ring with a track, a round-capped arc that draws in, and optional centre content.
///
/// ```swift
/// ScoreRing(progress: 0.78, color: .vRecovery, track: .vRecoveryTint) { Text("78").vTextStyle(.score) }
/// ScoreRing(kind: .sleep, progress: 0.84)   // convenience
/// ```
/// `progress` is clamped to 0...1. Pass `animated: false` for static contexts (widgets, snapshots).
struct ScoreRing<Center: View>: View {
    let progress: Double
    let color: Color
    let track: Color
    let diameter: CGFloat
    let animated: Bool
    let center: Center

    init(progress: Double, color: Color, track: Color, diameter: CGFloat = VSize.scoreRing, animated: Bool = true, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.color = color
        self.track = track
        self.diameter = diameter
        self.animated = animated
        self.center = center()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        let stroke = diameter * 0.09
        let shownProgress = (drawn || !animated || reduceMotion) ? min(max(progress, 0), 1) : 0
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: shownProgress)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(stroke / 2)
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard animated, !reduceMotion, !drawn else { return }
            withAnimation(VMotion.ringDraw) { drawn = true }
        }
        .animation(reduceMotion ? nil : VMotion.ease(duration: 0.8), value: progress)
    }
}

extension ScoreRing where Center == EmptyView {
    init(progress: Double, color: Color, track: Color, diameter: CGFloat = VSize.scoreRing, animated: Bool = true) {
        self.init(progress: progress, color: color, track: track, diameter: diameter, animated: animated) { EmptyView() }
    }
}

extension ScoreRing {
    /// Ring coloured for a headline score.
    init(kind: VScoreKind, progress: Double, diameter: CGFloat = VSize.scoreRing, animated: Bool = true, @ViewBuilder center: () -> Center) {
        self.init(progress: progress, color: kind.color, track: kind.track, diameter: diameter, animated: animated, center: center)
    }
}

/// Three concentric rings (Recovery outermost, Sleep, Strain) — the onboarding hero. Values are 0...1.
/// Echoes the Vigil logo (see `VigilLogoMark`).
struct ConcentricRings: View {
    var recovery: Double
    var sleep: Double
    var strain: Double
    var diameter: CGFloat = 320
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        let unit = diameter / 320
        let stroke = 22 * unit
        let animate = animated && !reduceMotion
        ZStack {
            ring(.recovery, value: recovery, radius: 140 * unit, stroke: stroke, delay: 0)
            ring(.sleep, value: sleep, radius: 106 * unit, stroke: stroke, delay: 0.12)
            ring(.strain, value: strain, radius: 72 * unit, stroke: stroke, delay: 0.24)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard animate, !drawn else { return }
            drawn = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery \(Int((recovery * 100).rounded())) percent, Sleep \(Int((sleep * 100).rounded())) percent, Strain \(Int((strain * 100).rounded())) percent")
    }

    private func ring(_ kind: VScoreKind, value: Double, radius: CGFloat, stroke: CGFloat, delay: Double) -> some View {
        let show = (drawn || !animated || reduceMotion) ? min(max(value, 0), 1) : 0
        return ZStack {
            Circle().stroke(kind.track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: show)
                .stroke(kind.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : VMotion.ringDraw.delay(delay), value: drawn)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

#Preview("Rings") {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            ScoreRing(kind: .recovery, progress: 0.78) { Text("78").vTextStyle(.score) }
            ScoreRing(kind: .sleep, progress: 0.84) { Text("84").vTextStyle(.score) }
            ScoreRing(kind: .strain, progress: 0.62) { Text("62").vTextStyle(.score) }
        }
        ConcentricRings(recovery: 0.78, sleep: 0.84, strain: 0.62, diameter: 240)
    }
    .padding()
    .background(Color.vBackground)
}
