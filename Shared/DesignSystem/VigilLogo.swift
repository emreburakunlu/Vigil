import SwiftUI

// MARK: - Brand colors (Design/Logo/vigil-logo-kit/README.md)

extension Color {
    /// Logo outer ring (Recovery).
    static let vLogoRecovery = Color.vDynamic(light: (0x1DB872, 1), dark: (0x3FE3A0, 1))
    /// Logo middle ring (Sleep).
    static let vLogoSleep = Color.vDynamic(light: (0x7B61FF, 1), dark: (0x9D8CFF, 1))
    /// Logo inner ring (Strain).
    static let vLogoStrain = Color.vDynamic(light: (0xFF6A3D, 1), dark: (0xFF6A3D, 1))
    /// App-icon tile background.
    static let vLogoTile = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0x17161F, 1))
}

// MARK: - Mark

/// The Vigil mark: three open rings (Recovery, Sleep, Strain) with a 60° gap at the top.
/// Vector, so it is sharp at any size. Pass `tint` for a single-color version.
///
/// Geometry on a 100 × 100 canvas: centre (50, 52), radii 33 / 22 / 11, stroke 8, round caps.
struct VigilLogoMark: View {
    var size: CGFloat = 32
    var tint: Color? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height) / 100
            let center = CGPoint(x: 50 * unit, y: 52 * unit)
            let style = StrokeStyle(lineWidth: 8 * unit, lineCap: .round)
            for (radius, color) in [(33.0, Color.vLogoRecovery), (22.0, .vLogoSleep), (11.0, .vLogoStrain)] {
                var arc = Path()
                // 300° clockwise from 30° right of 12 o'clock to 30° left of it.
                arc.addArc(center: center, radius: radius * unit,
                           startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
                context.stroke(arc, with: .color(tint ?? color), style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark on its app-icon tile (white in light mode, near-black in dark), with continuous corners.
/// Use where the brand appears as an icon: onboarding header, Profile, widgets.
struct VigilLogoTile: View {
    var size: CGFloat = 32

    var body: some View {
        VigilLogoMark(size: size * 0.86)
            .frame(width: size, height: size)
            .background(Color.vLogoTile, in: .rect(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
            .accessibilityHidden(true)
    }
}

#Preview("Logo") {
    HStack(spacing: 24) {
        VigilLogoMark(size: 96)
        VigilLogoTile(size: 64)
        VigilLogoTile(size: 32)
        VigilLogoMark(size: 48, tint: .vInk)
    }
    .padding()
}
