import SwiftUI

// MARK: - Motion tokens
//
// Owner: design-system agent. Curves/durations taken from the `@keyframes` in Design/*.dc.html.
// Every animation below is skipped when `accessibilityReduceMotion` is on.

enum VMotion {
    /// `cubic-bezier(.22, 1, .36, 1)` (ease-out-expo-ish) — the design's signature curve.
    static func ease(duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// Card rise-in (0.6 s).
    static let rise = ease(duration: 0.6)
    /// Ring stroke draw (1.4 s, 0.25 s delay).
    static let ringDraw = ease(duration: 1.4).delay(0.25)
    /// Bar grow (0.9 s, 0.3 s delay).
    static let barGrow = ease(duration: 0.9).delay(0.3)
    /// Line draw (1.8 s, 0.3 s delay).
    static let lineDraw = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.8).delay(0.3)
    /// Tab bar / button state changes (0.2 s).
    static let quick = ease(duration: 0.2)
    /// Distance cards travel while rising (16 pt).
    static let riseOffset: CGFloat = 16
    /// Button press scale (0.96).
    static let pressScale: CGFloat = 0.96
}

/// Fade + 16 pt rise on first appearance. Stagger sections with `delay`.
private struct RiseInModifier: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : VMotion.riseOffset)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else {
                    withAnimation(VMotion.rise.delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// Card rise-in: fades in while moving up 16 pt. Use on top-level sections with a stagger
    /// (`.vRiseIn(delay: 0.07 * Double(index))`). No-op with Reduce Motion.
    func vRiseIn(delay: Double = 0) -> some View {
        modifier(RiseInModifier(delay: delay))
    }
}

/// Button style that scales to 0.96 while pressed (design: `a:active, button:active`).
struct VPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? VMotion.pressScale : 1)
            .animation(reduceMotion ? nil : VMotion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == VPressStyle {
    /// Press-scale button style: `Button { } label: { … }.buttonStyle(.vPress)`.
    static var vPress: VPressStyle { VPressStyle() }
}
