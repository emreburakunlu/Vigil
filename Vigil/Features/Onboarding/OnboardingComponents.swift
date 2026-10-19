import SwiftUI

// Private building blocks shared by the onboarding screens. Layout from Design/Onb*.dc.html.

extension View {
    /// Hides the navigation bar (the screens draw their own back button) while keeping swipe-back.
    func onboardingChrome() -> some View {
        self
            .toolbarVisibility(.hidden, for: .navigationBar)
            .vScreenBackground()
    }
}

/// 44 pt back button plus the four-segment progress bar of steps 1–4.
struct OnboardingStepHeader: View {
    /// 1…4.
    let step: Int
    var showsBack = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: VSpacing.xl) {
            if showsBack {
                CircleIconButton(systemImage: "chevron.left", label: "Back") { dismiss() }
            }
            HStack(spacing: VSpacing.xs) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.vInk : Color.vControlTrack)
                        .frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step) of 4")
        }
        .frame(minHeight: VSize.minTapTarget)
        .padding(.leading, VSpacing.screenGutter)
        .padding(.trailing, VSpacing.huge)
    }
}

/// "STEP 2 OF 4", large title and a supporting sentence.
struct OnboardingTitleBlock: View {
    var step: Int?
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            if let step {
                Text("Step \(step) of 4")
                    .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
                    .tracking(0.78)
                    .textCase(.uppercase)
                    .foregroundStyle(.vInkSecondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.vCustom(.heading, size: 30, weight: .bold, relativeTo: .title))
                .tracking(-0.6)
                .foregroundStyle(.vInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .vTextStyle(.body)
                .foregroundStyle(.vInkLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VSpacing.huge)
    }
}

/// Square tinted icon tile (40 pt) used on the Health, Goals and checklist rows.
struct OnboardingIconTile: View {
    let systemImage: String
    let tint: Color
    let ink: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: 40, height: 40)
            .background(tint, in: .rect(cornerRadius: VRadius.chip, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Bottom call-to-action area: the primary button and an optional caption / extra control.
struct OnboardingFooter<Extra: View>: View {
    let button: PrimaryButton
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: VSpacing.l) {
            button
            extra
        }
        .padding(.horizontal, VSpacing.huge)
        .padding(.top, VSpacing.s)
        .padding(.bottom, VSpacing.xs)
        .background(Color.vBackground)
    }
}

extension OnboardingFooter where Extra == EmptyView {
    init(button: PrimaryButton) {
        self.init(button: button) { EmptyView() }
    }
}

/// Footnote caption under a footer button.
struct OnboardingCaption: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .vTextStyle(.footnote)
            .foregroundStyle(.vInkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Card container with zero inner padding, so rows can draw their own dividers.
struct OnboardingFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard(padding: 0, radius: VRadius.card - 2)
    }
}

/// Number input pill (Age, Body weight, Max HR).
struct OnboardingNumberField: View {
    let text: Binding<String>
    var width: CGFloat = 66
    var keyboard: UIKeyboardType = .numberPad
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        TextField("", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.vStatValueSmall.weight(.bold))
            .foregroundStyle(.vInk)
            .frame(width: width, height: 36)
            .background(Color.vBackground, in: .rect(cornerRadius: VRadius.chip - 2, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
    }
}
