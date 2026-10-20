import SwiftUI
import WidgetKit

// MARK: - Shared widget building blocks

/// The Vigil logo tile in widget headers and placeholders.
struct VigilMark: View {
    var size: CGFloat = 16

    var body: some View {
        VigilLogoTile(size: size)
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
                VigilMark(size: 30)
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
