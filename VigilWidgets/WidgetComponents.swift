import SwiftUI
import WidgetKit

// MARK: - Shared widget building blocks

/// The Vigil eye mark (Design/Widgets.dc.html header icon): dark rounded square, white eye, coloured pupil.
struct VigilMark: View {
    var size: CGFloat = 16
    var pupil: Color = .vRecovery

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.vInverseFill)
            EyeShape()
                .stroke(Color.vInkOnInverse, lineWidth: size * 0.075)
                .frame(width: size * 0.66, height: size * 0.66)
            Circle().fill(pupil).frame(width: size * 0.106 * 2, height: size * 0.106 * 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct EyeShape: Shape {
        func path(in rect: CGRect) -> Path {
            // "M5.5 16c4.5-6.5 16.5-6.5 21 0-4.5 6.5-16.5 6.5-21 0z" in a 32 pt box.
            let sx = rect.width / 21, sy = rect.height / 21
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.midY + y * sy) }
            var path = Path()
            path.move(to: p(0, 0))
            path.addCurve(to: p(21, 0), control1: p(4.5, -6.5), control2: p(16.5, -6.5))
            path.addCurve(to: p(0, 0), control1: p(16.5, 6.5), control2: p(4.5, 6.5))
            path.closeSubpath()
            return path
        }
    }
}

/// Container background: card surface for Home Screen families, transparent for Lock Screen accessories.
struct WidgetContainerModifier: ViewModifier {
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline: Color.clear
            default: Color.vCard
            }
        }
    }
}

extension View {
    func vigilWidgetContainer() -> some View { modifier(WidgetContainerModifier()) }
}

/// Band-aware recovery colours.
extension RecoveryBand {
    var ringColor: Color {
        switch self {
        case .green: .vRecovery
        case .yellow: .vWarning
        case .red: .vDanger
        }
    }

    var trackColor: Color {
        switch self {
        case .green: .vRecoveryTint
        case .yellow: .vWarningTint
        case .red: .vDangerTint
        }
    }

    var inkColor: Color {
        switch self {
        case .green: .vRecoveryInk
        case .yellow: .vWarningInk
        case .red: .vDangerInk
        }
    }
}

/// A `ScoreRing` that adapts to the widget rendering mode: full colour, or accent-tinted in
/// accented / vibrant (Lock Screen) modes.
struct WidgetRing<Center: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let progress: Double
    let color: Color
    let track: Color
    let diameter: CGFloat
    let center: Center

    init(progress: Double, color: Color, track: Color, diameter: CGFloat, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.color = color
        self.track = track
        self.diameter = diameter
        self.center = center()
    }

    var body: some View {
        if renderingMode == .fullColor {
            ScoreRing(progress: progress, color: color, track: track, diameter: diameter, animated: false) { center }
        } else {
            ScoreRing(progress: progress, color: .primary, track: .primary.opacity(0.22), diameter: diameter, animated: false) { center }
                .widgetAccentable()
        }
    }
}

/// "Open Vigil to update" placeholder shown when there is no fresh snapshot.
struct WidgetNeedsUpdateView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "arrow.clockwise")
                Text("Open").font(.system(size: 11, weight: .semibold))
            }
            .accessibilityLabel("Open Vigil to update")
        case .accessoryRectangular, .accessoryInline:
            VStack(alignment: .leading, spacing: 2) {
                Text("Vigil").font(.headline).widgetAccentable()
                Text("Open Vigil to update").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: VSpacing.s) {
                VigilMark(size: 30, pupil: .vInkTertiary)
                Text("Open Vigil to update")
                    .vTextStyle(.callout)
                    .foregroundStyle(Color.vInkSecondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Header row used by the medium widgets: bold title left, secondary text right.
struct WidgetHeader: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack {
            Text(title).vTextStyle(.footnote).fontWeight(.bold).foregroundStyle(Color.vInk)
            Spacer(minLength: VSpacing.s)
            if let trailing {
                Text(trailing).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary).lineLimit(1)
            }
        }
    }
}

/// Fixed sample for previews: fresh, plus a stale entry.
enum WidgetPreviewData {
    static var fresh: SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder()) }
    static var stale: SnapshotEntry { SnapshotEntry(date: .now, snapshot: nil) }
    static var imperial: SnapshotEntry {
        var snapshot = WidgetSnapshot.placeholder()
        snapshot.units = .imperial
        return SnapshotEntry(date: .now, snapshot: snapshot)
    }
}
