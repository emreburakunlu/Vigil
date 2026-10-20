import SwiftUI

/// Loading placeholder: one card-shaped block per entry in `heights`, with two title bars. No spinner.
/// The palette comes from `\.vSurface`, so it works on standard and night screens.
///
/// ```swift
/// VSkeletonStack(heights: [210, 300, 240], label: "Loading sleep")
/// ```
struct VSkeletonStack: View {
    let heights: [CGFloat]
    var label: LocalizedStringKey = "Loading"

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(spacing: VSpacing.xl) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: VRadius.cardLarge, style: .continuous)
                    .fill(surface.card)
                    .frame(height: height)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: VSpacing.l) {
                            Capsule().fill(surface.fill).frame(width: 140, height: 20)
                            Capsule().fill(surface.fill).frame(width: 220, height: 14)
                        }
                        .padding(VSpacing.xxxl)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// "Couldn't load" card with a retry button.
///
/// ```swift
/// VErrorCard(title: "Couldn't load sleep", message: "Something went wrong.") { model.reload() }
/// ```
struct VErrorCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let retry: () -> Void

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(spacing: VSpacing.l) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(surface.inkTertiary)
                .accessibilityHidden(true)
            Text(title)
                .vTextStyle(.title2).fontWeight(.bold)
                .foregroundStyle(surface.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .vTextStyle(.body)
                .foregroundStyle(surface.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Try again")
                    .vTextStyle(.body).fontWeight(.bold)
                    .foregroundStyle(surface.accent)
                    .frame(minHeight: VSize.minTapTarget)
                    .padding(.horizontal, VSpacing.xl)
            }
            .buttonStyle(.vPress)
        }
        .frame(maxWidth: .infinity)
        .padding(VSpacing.xxxl)
        .background(surface.card, in: .rect(cornerRadius: VRadius.cardLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VRadius.cardLarge, style: .continuous).strokeBorder(surface.outline, lineWidth: VSize.hairline))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Placeholders") {
    VStack(spacing: 16) {
        VSkeletonStack(heights: [90, 90])
        VErrorCard(title: "Couldn't load sleep", message: "Something went wrong reading your sleep data.") {}
    }
    .padding()
    .background(Color.vBackground)
}
