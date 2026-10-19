import SwiftUI

/// Semantic chip colourways.
enum VChipTone: Sendable {
    case neutral, recovery, sleep, strain, run, lift, warning, danger, accent

    var foreground: Color {
        switch self {
        case .neutral: .vInkLabel
        case .recovery: .vRecoveryInk
        case .sleep: .vSleepInk
        case .strain, .lift: .vStrainInk
        case .run: .vRunInk
        case .warning: .vWarningInk
        case .danger: .vDangerInk
        case .accent: .vAccent
        }
    }

    var background: Color {
        switch self {
        case .neutral: .vFill
        case .recovery: .vRecoveryTint
        case .sleep: .vSleepTint
        case .strain: .vStrainTint
        case .lift: .vLiftTint
        case .run: .vRunTint
        case .warning: .vWarningTint
        case .danger: .vDangerTint
        case .accent: .vAccentTint
        }
    }
}

/// Small pill label: source app ("via Hevy"), status, tag.
///
/// ```swift
/// VChip("Hevy", systemImage: "app.badge")
/// VChip("Green", tone: .recovery)
/// ```
struct VChip: View {
    let text: LocalizedStringKey
    var systemImage: String?
    var tone: VChipTone = .neutral

    init(_ text: LocalizedStringKey, systemImage: String? = nil, tone: VChipTone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: VSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
            }
            Text(text).font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, VSpacing.m)
        .padding(.vertical, VSpacing.xxs + 1)
        .background(tone.background, in: .capsule)
    }
}

/// Personal-record badge ("PR" / "NEW PR").
///
/// ```swift
/// PRBadge()           // "PR"
/// PRBadge(isNew: true) // "NEW"
/// ```
struct PRBadge: View {
    var isNew = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            Text(isNew ? "NEW PR" : "PR").font(.vCustom(.body, size: 11, weight: .heavy, relativeTo: .caption2)).tracking(0.4)
        }
        .foregroundStyle(Color.vInkOnAccent)
        .padding(.horizontal, VSpacing.s)
        .padding(.vertical, 3)
        .background(Color.vStrain, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isNew ? "New personal record" : "Personal record")
    }
}

/// Insight card: tinted icon well + sentence (Sleep tab, Progress).
///
/// ```swift
/// InsightRow("You sleep 35 min more on rest days.", systemImage: "chart.line.uptrend.xyaxis")
/// ```
struct InsightRow: View {
    let text: String
    var systemImage: String

    @Environment(\.vSurface) private var surface

    init(_ text: String, systemImage: String = "sparkles") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: VSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(surface.accent)
                .frame(width: 36, height: 36)
                .background(surface.fill, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .vTextStyle(.callout)
                .lineSpacing(2)
                .foregroundStyle(surface.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(VSpacing.xxl)
        .background(surface.card, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(surface.outline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
        .accessibilityElement(children: .combine)
    }
}

/// Icon + title + message + optional action, for empty / error states.
///
/// ```swift
/// EmptyStateView(systemImage: "moon.zzz", title: "No sleep recorded", message: "Wear your Watch to bed.", actionTitle: "Open Health") { … }
/// ```
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(spacing: VSpacing.xxl) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(surface == .night ? Color.vNightInkTertiary : Color.vInkTertiary)
                .frame(width: 84, height: 84)
                .background(
                    Circle().strokeBorder(surface == .night ? Color.vNightDashed : Color.vInkDisabled, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                )
                .accessibilityHidden(true)
            VStack(spacing: VSpacing.xs) {
                Text(title).vTextStyle(.title).multilineTextAlignment(.center).foregroundStyle(surface.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message).vTextStyle(.body).multilineTextAlignment(.center).foregroundStyle(surface.inkSecondary)
            }
            if let actionTitle, let action {
                PrimaryButton(actionTitle, kind: .primary, action: action)
                    .padding(.top, VSpacing.xs)
            }
        }
        .padding(.horizontal, VSpacing.huge)
        .padding(.vertical, VSpacing.huge)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Chips & states") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VChip("via Hevy"); VChip("Green", tone: .recovery); VChip("Run", systemImage: "figure.run", tone: .run); VChip("Lift", tone: .lift); PRBadge(); PRBadge(isNew: true) }
            InsightRow("You sleep 35 min more on rest days than after lifting.", systemImage: "chart.line.uptrend.xyaxis")
            EmptyStateView(systemImage: "moon.zzz", title: "No sleep recorded", message: "Wear your Apple Watch to bed to see last night's sleep.", actionTitle: "Open Health") {}
                .vCard()
        }
        .padding(16)
    }
    .background(Color.vBackground)
}
