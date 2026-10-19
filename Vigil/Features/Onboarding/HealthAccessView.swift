import SwiftUI

/// Onb4 · Connect Apple Health. Explains each data type, then shows the system permission sheet.
/// `OnboardingModel` decides where to go next (About you, or the denied state).
struct HealthAccessView: View {
    @Environment(AppContainer.self) private var container
    @Environment(OnboardingModel.self) private var model

    private struct DataGroup: Identifiable {
        let id: String
        let systemImage: String
        let tint: Color
        let ink: Color
        let title: LocalizedStringKey
        let reads: LocalizedStringKey
        let why: LocalizedStringKey
    }

    private let groups = [
        DataGroup(id: "sleep", systemImage: "bed.double.fill", tint: .vSleepTint, ink: .vSleepInk, title: "Sleep & recovery",
                  reads: "Sleep, HRV, resting HR, respiratory rate, wrist temp, blood oxygen",
                  why: "For your Sleep and Recovery scores and baselines."),
        DataGroup(id: "workouts", systemImage: "heart.fill", tint: .vStrainTint, ink: .vStrainInk, title: "Workouts & heart rate",
                  reads: "Workouts, heart rate, running routes, pace, cadence, power",
                  why: "For Strain, heart rate zones and run maps."),
        DataGroup(id: "activity", systemImage: "flame.fill", tint: .vRecoveryTint, ink: .vRecoveryInk, title: "Daily activity",
                  reads: "Steps, active energy, exercise and stand minutes",
                  why: "For your activity summary and everyday strain."),
        DataGroup(id: "body", systemImage: "scalemass.fill", tint: .vRunTint, ink: .vRunInk, title: "Body",
                  reads: "Body weight",
                  why: "For accurate calorie and load estimates."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepHeader(step: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.xxxl) {
                    OnboardingTitleBlock(step: 1, title: "Connect Apple Health",
                                         message: "Here's what Vigil reads and why. It never writes anything back.")
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            row(group)
                            if index < groups.count - 1 { Divider().overlay(Color.vSeparator) }
                        }
                    }
                    .padding(.horizontal, VSpacing.xxl)
                    .padding(.vertical, VSpacing.xxs)
                    .frame(maxWidth: .infinity)
                    .vCard(padding: 0)
                    .padding(.horizontal, VSpacing.screenGutter)
                }
                .padding(.top, VSpacing.xxxl)
                .padding(.bottom, VSpacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingFooter(button: PrimaryButton("Allow Health access", systemImage: "heart.fill") {
                Task { await model.requestHealthAccess(in: container) }
            }) {
                footerCaption
            }
            .disabled(model.isRequestingAccess)
        }
    }

    @ViewBuilder
    private var footerCaption: some View {
        switch model.accessProblem {
        case .unavailable:
            Text("Apple Health isn't available on this device.")
                .vTextStyle(.footnote).foregroundStyle(.vDangerInk).multilineTextAlignment(.center)
        case .failed:
            Text("Couldn't open the Health permission sheet. Try again.")
                .vTextStyle(.footnote).foregroundStyle(.vDangerInk).multilineTextAlignment(.center)
        case nil:
            OnboardingCaption("Apple's permission sheet opens next. You can change this any time in Settings.")
        }
    }

    private func row(_ group: DataGroup) -> some View {
        HStack(alignment: .top, spacing: VSpacing.l) {
            OnboardingIconTile(systemImage: group.systemImage, tint: group.tint, ink: group.ink)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.vCustom(.body, size: 15.5, weight: .bold, relativeTo: .body)).foregroundStyle(.vInk)
                Text(group.reads).vTextStyle(.footnote).foregroundStyle(.vInkLabel)
                Text(group.why).vTextStyle(.footnote).fontWeight(.medium).foregroundStyle(.vInkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, VSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HealthAccessView().environment(OnboardingModel()).vigilPreview(.newUser, onboarded: false)
}

#Preview("Dark") {
    HealthAccessView().environment(OnboardingModel()).vigilPreview(.newUser, onboarded: false)
        .preferredColorScheme(.dark)
}
