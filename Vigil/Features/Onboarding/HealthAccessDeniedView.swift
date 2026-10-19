import SwiftUI

/// State · Health access off. Explains how to re-enable access in Settings.
///
/// Used by `RootView` after onboarding (`onRetry` re-checks access) and inside the onboarding flow,
/// where `onExplain` takes the user back to "Why Vigil needs this" (the Health access step).
struct HealthAccessDeniedView: View {
    let onRetry: () -> Void
    /// When set, the secondary action reads "Why Vigil needs this" and calls this; otherwise it is "Try again".
    var onExplain: (() -> Void)?

    @Environment(\.openURL) private var openURL

    private let steps: [Text] = [
        Text("Open **Settings** › **Health**"),
        Text("Tap **Data Access & Devices** › **Vigil**"),
        Text("Turn on **Turn On All**"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.huge) {
                icon
                    .padding(.top, VSpacing.huge * 2)
                VStack(spacing: VSpacing.m) {
                    Text("Vigil can't read Apple Health")
                        .font(.vCustom(.heading, size: 28, weight: .bold, relativeTo: .title))
                        .tracking(-0.56)
                        .foregroundStyle(.vInk)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Access is turned off, so there's nothing to score. Your data stays where it is.")
                        .vTextStyle(.body)
                        .foregroundStyle(.vInkLabel)
                        .multilineTextAlignment(.center)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, VSpacing.huge + VSpacing.xxs)

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: VSpacing.l) {
                            Text("\(index + 1)")
                                .font(.vCustom(.body, size: 13, weight: .heavy, relativeTo: .footnote))
                                .foregroundStyle(.vInkOnInverse)
                                .frame(width: 26, height: 26)
                                .background(Color.vInverseFill, in: .circle)
                                .accessibilityHidden(true)
                            step.vTextStyle(.bodyStrong).foregroundStyle(.vInk)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 50)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1)")
                        if index < steps.count - 1 { Divider().overlay(Color.vSeparator) }
                    }
                }
                .padding(.horizontal, VSpacing.xxl)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .vCard(padding: 0, radius: VRadius.card - 2)
                .padding(.horizontal, VSpacing.screenGutter)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("How to turn access on")
            }
            .padding(.bottom, VSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                PrimaryButton("Open Settings", systemImage: "arrow.up.right") {
                    if let url = URL(string: "app-settings:") ?? URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button(onExplain == nil ? "Try again" : "Why Vigil needs this") { (onExplain ?? onRetry)() }
                    .vTextStyle(.bodyStrong)
                    .foregroundStyle(.vInkLabel)
                    .frame(minHeight: VSize.minTapTarget)
            }
            .padding(.horizontal, VSpacing.huge)
            .padding(.top, VSpacing.s)
            .padding(.bottom, VSpacing.xs)
            .background(Color.vBackground)
        }
        .vScreenBackground()
    }

    private var icon: some View {
        Image(systemName: "heart.text.square.fill")
            .font(.system(size: 56, weight: .regular))
            .foregroundStyle(.vDanger)
            .frame(width: 132, height: 132)
            .background(Color.vCard, in: .rect(cornerRadius: 40, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
            .shadow(color: .vShadow, radius: 20, y: 16)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.vDanger, in: .circle)
                    .overlay(Circle().strokeBorder(Color.vBackground, lineWidth: 4))
                    .offset(x: 8, y: 8)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HealthAccessDeniedView(onRetry: {}).vigilPreview(.healthAccessDenied, navigation: false)
}

#Preview("In onboarding · dark") {
    HealthAccessDeniedView(onRetry: {}, onExplain: {}).vigilPreview(.healthAccessDenied, navigation: false)
        .preferredColorScheme(.dark)
}
