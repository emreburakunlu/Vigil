import SwiftUI

/// Onb5 · About you (age, sex, body weight, units, max HR). Prefilled from Health where possible.
struct AboutYouView: View {
    let onContinue: () -> Void

    @Environment(AppContainer.self) private var container
    @State private var model: AboutYouModel?

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepHeader(step: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.xxxl) {
                    OnboardingTitleBlock(step: 2, title: "About you",
                                         message: "We filled in what Health already knows. Check it looks right.")
                    if let model {
                        AboutYouForm(model: model)
                    } else {
                        placeholder
                    }
                }
                .padding(.top, VSpacing.xxxl)
                .padding(.bottom, VSpacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingFooter(button: PrimaryButton("Continue", action: onContinue))
        }
        .task {
            guard model == nil else { return }
            let loaded = AboutYouModel(repository: container.repository)
            model = loaded
            await loaded.prefillFromHealth()
        }
    }

    private var placeholder: some View {
        VStack(spacing: VSpacing.l) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: VRadius.card, style: .continuous)
                    .fill(Color.vFill)
                    .frame(height: 96)
            }
        }
        .padding(.horizontal, VSpacing.screenGutter)
        .accessibilityHidden(true)
    }
}

private struct AboutYouForm: View {
    @Bindable var model: AboutYouModel

    private var formatter: VigilFormatter { model.formatter }

    var body: some View {
        VStack(spacing: VSpacing.l) {
            OnboardingFormCard {
                HStack {
                    Text("Age").vTextStyle(.body).fontWeight(.bold).foregroundStyle(.vInk)
                    Spacer()
                    OnboardingNumberField(text: Binding(get: { model.ageText }, set: model.setAgeText),
                                          width: 56, accessibilityLabel: "Age in years")
                    Text("years").vTextStyle(.callout).foregroundStyle(.vInkSecondary)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, VSpacing.xxl)
                Divider().overlay(Color.vSeparator)

                VStack(alignment: .leading, spacing: VSpacing.m) {
                    Text("Sex").vTextStyle(.body).fontWeight(.bold).foregroundStyle(.vInk)
                    VSegmentedControl(selection: Binding(get: { model.sex }, set: model.setSex),
                                      options: [BiologicalSex?.some(.female), .some(.male), .some(.other)]) { option in
                        switch option {
                        case .female: "Female"
                        case .male: "Male"
                        default: "Other"
                        }
                    }
                }
                .padding(.horizontal, VSpacing.xxl)
                .padding(.vertical, VSpacing.xl)
                Divider().overlay(Color.vSeparator)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Body weight").vTextStyle(.body).fontWeight(.bold).foregroundStyle(.vInk)
                        if model.isFromHealth, let date = model.bodyMassDate {
                            Text("From Health · \(date, format: .dateTime.month(.abbreviated).day())")
                                .vTextStyle(.caption).foregroundStyle(.vInkSecondary)
                        } else if model.isFromHealth {
                            Text("From Health").vTextStyle(.caption).foregroundStyle(.vInkSecondary)
                        }
                    }
                    Spacer()
                    OnboardingNumberField(text: Binding(get: { model.weightText }, set: model.setWeightText),
                                          width: 72, keyboard: .decimalPad, accessibilityLabel: "Body weight")
                    Text(formatter.weightUnit).vTextStyle(.callout).foregroundStyle(.vInkSecondary)
                        .frame(minWidth: 22, alignment: .leading)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, VSpacing.xxl)
            }

            VCard(padding: VSpacing.xxl, radius: VRadius.card - 2) {
                Text("Units").vTextStyle(.body).fontWeight(.bold).foregroundStyle(.vInk)
                VSegmentedControl(selection: Binding(get: { model.units }, set: model.setUnits),
                                  options: UnitSystem.allCases) { unit in
                    let f = VigilFormatter(units: unit)
                    return LocalizedStringKey("\(f.weightUnit) · \(f.distanceUnit)")
                }
            }

            VCard(padding: VSpacing.xxl, radius: VRadius.card - 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Max heart rate").vTextStyle(.body).fontWeight(.bold).foregroundStyle(.vInk)
                    Spacer()
                    if model.estimatesMaxHeartRate {
                        Text(formatter.heartRate(bpm: Double(model.maxHeartRate)).text)
                            .font(.vCustom(.heading, size: 22, weight: .bold, relativeTo: .title2))
                            .foregroundStyle(.vInk)
                    } else {
                        OnboardingNumberField(text: Binding(get: { model.manualHeartRateText }, set: model.setManualHeartRateText),
                                              width: 72, accessibilityLabel: "Max heart rate in beats per minute")
                        Text(formatter.heartRate(bpm: 0).unit).vTextStyle(.callout).foregroundStyle(.vInkSecondary)
                    }
                }
                VSegmentedControl(selection: Binding(get: { model.estimatesMaxHeartRate }, set: model.setEstimatesMaxHeartRate),
                                  options: [true, false]) { $0 ? "Estimate for me" : "Enter my own" }
                Text(model.estimatesMaxHeartRate
                     ? "Estimated from your age. Vigil refines it when a workout shows a higher peak."
                     : "Use a value from a lab test or a recent all-out effort.")
                    .vTextStyle(.footnote)
                    .foregroundStyle(.vInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, VSpacing.screenGutter)
    }
}

#Preview {
    AboutYouView(onContinue: {}).vigilPreview(onboarded: false, navigation: false)
}

#Preview("Dark · imperial") {
    AboutYouView(onContinue: {}).vigilPreview(onboarded: false, navigation: false)
        .preferredColorScheme(.dark)
}
