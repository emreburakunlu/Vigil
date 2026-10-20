import SwiftUI

/// Welcome pages 1–3 (Onb1 Welcome, Onb2 Three scores, Onb3 Private by design).
struct WelcomeView: View {
    let page: OnboardingStep
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var pageNumber: Int {
        switch page {
        case .scores: 2
        case .privacy: 3
        default: 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: VSpacing.huge) {
                    hero
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 300)
                    copy
                }
                .padding(.top, VSpacing.xxxl)
                .padding(.bottom, VSpacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            if pageNumber == 1 {
                HStack(spacing: VSpacing.m) {
                    VigilLogoTile(size: 32)
                    Text("Vigil")
                        .font(.vCustom(.heading, size: 22, weight: .bold, relativeTo: .title2))
                        .tracking(-0.44)
                        .foregroundStyle(.vInk)
                }
                .padding(.leading, VSpacing.s)
                .accessibilityElement(children: .combine)
            } else {
                CircleIconButton(systemImage: "chevron.left", label: "Back") { dismiss() }
            }
            Spacer(minLength: 0)
            if pageNumber < 3 {
                Button("Skip", action: onSkip)
                    .vTextStyle(.bodyStrong)
                    .foregroundStyle(.vInkLabel)
                    .frame(minHeight: VSize.minTapTarget)
                    .padding(.horizontal, VSpacing.xxs)
            }
        }
        .padding(.leading, pageNumber == 1 ? VSpacing.huge - VSpacing.s : VSpacing.screenGutter)
        .padding(.trailing, VSpacing.huge)
        .frame(minHeight: VSize.minTapTarget)
    }

    @ViewBuilder
    private var hero: some View {
        switch page {
        case .scores:
            WelcomeScoreCards()
        case .privacy:
            WelcomePrivacyArt()
        default:
            ConcentricRings(recovery: OnboardingIllustration.recovery, sleep: OnboardingIllustration.sleep,
                            strain: OnboardingIllustration.strain, diameter: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Three rings for Recovery, Sleep and Strain")
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: VSpacing.l) {
            Text(title)
                .vTextStyle(.largeTitle)
                .foregroundStyle(.vInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.vCustom(.body, size: 17, weight: .medium, relativeTo: .body))
                .foregroundStyle(.vInkLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VSpacing.huge + VSpacing.xxs)
    }

    private var bottomBar: some View {
        VStack(spacing: 22) {
            HStack(spacing: VSpacing.xs) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(index == pageNumber ? Color.vInk : Color.vControlTrack)
                        .frame(width: index == pageNumber ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(pageNumber) of 3")
            PrimaryButton(page == .privacy ? "Get started" : "Continue", action: onContinue)
        }
        .padding(.horizontal, VSpacing.huge)
        .padding(.top, VSpacing.s)
        .padding(.bottom, VSpacing.xs)
        .background(Color.vBackground)
    }

    private var title: LocalizedStringKey {
        switch page {
        case .scores: "Three scores, every morning."
        case .privacy: "Everything stays on your iPhone."
        default: "Sleep, runs and lifts in one place."
        }
    }

    private var message: LocalizedStringKey {
        switch page {
        case .scores: "Each one is measured against your own baseline, so a good day for you means a good day for you."
        case .privacy: "No sign-in and no servers. Vigil only reads Apple Health, so data from Hevy and other apps shows up too."
        default: "Vigil reads what your Apple Watch already records. There's nothing to log, ever."
        }
    }
}

// MARK: - Illustration values

/// Illustrative scores for the welcome art. They are decoration (a new user has no data yet), so they
/// are hidden from VoiceOver and never presented as the user's data.
enum OnboardingIllustration {
    static let recovery = 0.78
    static let sleep = 0.84
    static let strain = 0.62
}

// MARK: - Logo


// MARK: - Onb2 · score cards

private struct WelcomeScoreCards: View {
    private struct Card: Identifiable {
        let kind: VScoreKind
        let value: Double
        let caption: LocalizedStringKey
        let rotation: Double
        let offset: CGFloat
        var id: VScoreKind { kind }
    }

    private let cards = [
        Card(kind: .recovery, value: OnboardingIllustration.recovery, caption: "How ready your body is today", rotation: -2, offset: 0),
        Card(kind: .sleep, value: OnboardingIllustration.sleep, caption: "How well you rested last night", rotation: 1.5, offset: 10),
        Card(kind: .strain, value: OnboardingIllustration.strain, caption: "How hard you worked, runs and lifts together", rotation: -1, offset: 0),
    ]

    var body: some View {
        VStack(spacing: VSpacing.l) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                HStack(spacing: VSpacing.xl) {
                    ScoreRing(kind: card.kind, progress: card.value, diameter: 64) {
                        Text("\(Int((card.value * 100).rounded()))")
                            .font(.vCustom(.heading, size: 19, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(.vInk)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(card.kind.title))
                            .vTextStyle(.statValueSmall)
                            .foregroundStyle(.vInk)
                        Text(card.caption)
                            .vTextStyle(.subheadline)
                            .foregroundStyle(.vInkLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .vCard(padding: VSpacing.xxl)
                .shadow(color: .vShadow, radius: 15, y: 12)
                .rotationEffect(.degrees(card.rotation))
                .offset(x: card.offset)
                .vRiseIn(delay: 0.07 * Double(index))
            }
        }
        .padding(.horizontal, VSpacing.huge + VSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery, Sleep and Strain scores")
    }
}

// MARK: - Onb3 · privacy art

private struct WelcomePrivacyArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.vCard)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.vInk, lineWidth: 2))
                .shadow(color: .vShadow, radius: 20, y: 18)
                .frame(width: 136, height: 280)
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.vInkOnInverse)
                .frame(width: 76, height: 76)
                .background(Color.vInverseFill, in: .rect(cornerRadius: 24, style: .continuous))
            pill("No account").offset(x: -92, y: -96)
            pill("No cloud").offset(x: 92, y: -12)
            pill("No feed").offset(x: -82, y: 82)
        }
        .frame(width: 300, height: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No account, no cloud, no feed")
    }

    private func pill(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .vTextStyle(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(.vInk)
            .padding(.horizontal, VSpacing.xl)
            .padding(.vertical, VSpacing.m)
            .background(Color.vCard, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
            .shadow(color: .vShadow, radius: 10, y: 8)
    }
}

#Preview("1 Welcome") {
    WelcomeView(page: .welcome, onContinue: {}, onSkip: {}).vigilPreview(onboarded: false)
}

#Preview("2 Scores") {
    WelcomeView(page: .scores, onContinue: {}, onSkip: {}).vigilPreview(onboarded: false)
}

#Preview("3 Privacy · dark") {
    WelcomeView(page: .privacy, onContinue: {}, onSkip: {}).vigilPreview(onboarded: false)
        .preferredColorScheme(.dark)
}
