import SwiftUI

/// Pure stepping rules of the goal steppers (unit-tested).
enum OnboardingGoalSteps {
    static let sleepRange: ClosedRange<TimeInterval> = (5 * 3600)...(11 * 3600)
    static let sleepStep: TimeInterval = 15 * 60
    static let distanceRange = 0...200
    static let distanceStep = 5
    static let liftRange = 0...7

    static func steppedSleep(_ current: TimeInterval, by direction: Int) -> TimeInterval {
        min(max(current + Double(direction) * sleepStep, sleepRange.lowerBound), sleepRange.upperBound)
    }

    /// Moves to the next / previous multiple of 5 in display units (km or mi), so imperial values snap cleanly.
    static func steppedDistance(meters: Double, by direction: Int, formatter: VigilFormatter) -> Double {
        let shown = Int(formatter.displayDistance(meters: meters).rounded())
        let target: Int
        if direction > 0 {
            target = (shown / distanceStep + 1) * distanceStep
        } else {
            target = shown % distanceStep == 0 ? shown - distanceStep : (shown / distanceStep) * distanceStep
        }
        let clamped = min(max(target, distanceRange.lowerBound), distanceRange.upperBound)
        return formatter.meters(fromDisplayDistance: Double(clamped))
    }

    static func steppedLifts(_ current: Int, by direction: Int) -> Int {
        min(max(current + direction, liftRange.lowerBound), liftRange.upperBound)
    }
}

/// Onb6 · Set your goals (sleep, weekly running, weekly lifting). Saved to settings on every tap.
struct GoalsView: View {
    let onContinue: () -> Void

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let goals = settingsStore.settings.goals
        let formatter = settingsStore.formatter
        VStack(spacing: 0) {
            OnboardingStepHeader(step: 3)
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.xxxl) {
                    OnboardingTitleBlock(step: 3, title: "Set your goals",
                                         message: "Vigil measures your week against these. Change them any time in Profile.")
                    VStack(spacing: VSpacing.l) {
                        goalCard(systemImage: "moon.fill", tint: .vSleepTint, ink: .vSleepInk,
                                 title: "Nightly sleep", hint: "Time asleep, not time in bed",
                                 value: formatter.duration(goals.sleepTarget), unit: nil,
                                 decrement: ("Less sleep", { setSleep(OnboardingGoalSteps.steppedSleep(goals.sleepTarget, by: -1)) }),
                                 increment: ("More sleep", { setSleep(OnboardingGoalSteps.steppedSleep(goals.sleepTarget, by: 1)) }),
                                 canDecrement: goals.sleepTarget > OnboardingGoalSteps.sleepRange.lowerBound,
                                 canIncrement: goals.sleepTarget < OnboardingGoalSteps.sleepRange.upperBound)
                        let run = formatter.distance(meters: goals.weeklyRunDistanceMeters, fractionDigits: 0)
                        goalCard(systemImage: "figure.run", tint: .vRunTint, ink: .vRunInk,
                                 title: "Weekly running", hint: "Distance from all runs",
                                 value: run.value, unit: Text(run.unit),
                                 decrement: ("Less distance", { setRun(OnboardingGoalSteps.steppedDistance(meters: goals.weeklyRunDistanceMeters, by: -1, formatter: formatter)) }),
                                 increment: ("More distance", { setRun(OnboardingGoalSteps.steppedDistance(meters: goals.weeklyRunDistanceMeters, by: 1, formatter: formatter)) }),
                                 canDecrement: goals.weeklyRunDistanceMeters > 0,
                                 canIncrement: formatter.displayDistance(meters: goals.weeklyRunDistanceMeters).rounded() < Double(OnboardingGoalSteps.distanceRange.upperBound))
                        goalCard(systemImage: "dumbbell.fill", tint: .vStrainTint, ink: .vStrainInk,
                                 title: "Weekly lifting", hint: "Strength workouts from any app",
                                 value: "\(goals.weeklyLiftSessions)",
                                 unit: goals.weeklyLiftSessions == 1 ? Text("session") : Text("sessions"),
                                 decrement: ("Fewer sessions", { setLifts(OnboardingGoalSteps.steppedLifts(goals.weeklyLiftSessions, by: -1)) }),
                                 increment: ("More sessions", { setLifts(OnboardingGoalSteps.steppedLifts(goals.weeklyLiftSessions, by: 1)) }),
                                 canDecrement: goals.weeklyLiftSessions > OnboardingGoalSteps.liftRange.lowerBound,
                                 canIncrement: goals.weeklyLiftSessions < OnboardingGoalSteps.liftRange.upperBound)
                    }
                    .padding(.horizontal, VSpacing.screenGutter)
                }
                .padding(.top, VSpacing.xxxl)
                .padding(.bottom, VSpacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingFooter(button: PrimaryButton("Continue", action: onContinue))
        }
    }

    private func setSleep(_ value: TimeInterval) { settingsStore.update { $0.goals.sleepTarget = value } }
    private func setRun(_ meters: Double) { settingsStore.update { $0.goals.weeklyRunDistanceMeters = meters } }
    private func setLifts(_ value: Int) { settingsStore.update { $0.goals.weeklyLiftSessions = value } }

    private func goalCard(systemImage: String, tint: Color, ink: Color, title: LocalizedStringKey, hint: LocalizedStringKey,
                          value: String, unit: Text?,
                          decrement: (label: LocalizedStringKey, action: () -> Void),
                          increment: (label: LocalizedStringKey, action: () -> Void),
                          canDecrement: Bool, canIncrement: Bool) -> some View {
        VCard(padding: VSpacing.cardPadding) {
            HStack(spacing: VSpacing.l) {
                OnboardingIconTile(systemImage: systemImage, tint: tint, ink: ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).vTextStyle(.bodyStrong).foregroundStyle(.vInk)
                    Text(hint).vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: VSpacing.s) {
                stepButton("minus", label: decrement.label, enabled: canDecrement, action: decrement.action)
                HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                    Text(value)
                        .font(.vCustom(.heading, size: 32, weight: .bold, relativeTo: .title))
                        .tracking(-0.64)
                        .foregroundStyle(.vInk)
                        .minimumScaleFactor(0.7)
                    if let unit { unit.vTextStyle(.bodyStrong).foregroundStyle(.vInkSecondary) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                stepButton("plus", label: increment.label, enabled: canIncrement, action: increment.action)
            }
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.vInk)
                .frame(width: 48, height: 48)
                .background(Color.vBackground, in: .circle)
        }
        .buttonStyle(.vPress)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

#Preview {
    GoalsView(onContinue: {}).vigilPreview(onboarded: false, navigation: false)
}

#Preview("Dark") {
    GoalsView(onContinue: {}).vigilPreview(onboarded: false, navigation: false)
        .preferredColorScheme(.dark)
}
