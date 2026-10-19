import SwiftUI

/// Onb7 · History import. Runs the 90-day import (owned by `OnboardingModel`, so it continues if the
/// user swipes back); "Open Vigil" completes onboarding.
struct HistoryImportView: View {
    @Environment(AppContainer.self) private var container
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        let progress = model.importProgress
        VStack(spacing: 0) {
            OnboardingStepHeader(step: 4, showsBack: false)
            ScrollView {
                VStack(spacing: VSpacing.huge) {
                    ring(progress)
                    VStack(spacing: VSpacing.s) {
                        Text(model.importFailed ? "Couldn't finish reading Health" : "Reading your last 90 days")
                            .font(.vCustom(.heading, size: 28, weight: .bold, relativeTo: .title))
                            .tracking(-0.56)
                            .foregroundStyle(.vInk)
                            .accessibilityAddTraits(.isHeader)
                        Text(model.importFailed
                             ? "Something interrupted the import. Try again, or open Vigil and it will catch up as data arrives."
                             : "Vigil is learning your normal so every score is measured against you.")
                            .vTextStyle(.body)
                            .foregroundStyle(.vInkLabel)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, VSpacing.huge + VSpacing.s)

                    checklist(progress)
                }
                .padding(.top, VSpacing.huge)
                .padding(.bottom, VSpacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .task { model.startImport(in: container) }
    }

    // MARK: Pieces

    private func ring(_ progress: ImportProgress?) -> some View {
        let fraction = progress?.fraction ?? 0
        let percent = Int((fraction * 100).rounded())
        return ScoreRing(progress: fraction, color: .vAccent, track: .vAccentTint, diameter: 176) {
            VStack(spacing: 2) {
                Text("\(percent)%")
                    .font(.vCustom(.heading, size: 44, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(.vInk)
                Text(caption(progress))
                    .vTextStyle(.footnote)
                    .foregroundStyle(.vInkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Import progress")
        .accessibilityValue("\(percent) percent")
    }

    private func caption(_ progress: ImportProgress?) -> LocalizedStringKey {
        guard let progress else { return "Starting…" }
        if progress.phase == .finished { return "All done" }
        if model.importFailed { return "Stopped" }
        let elapsed = model.importStartedAt.map { container.repository.now().timeIntervalSince($0) } ?? 0
        if let seconds = OnboardingImportPresentation.secondsRemaining(fraction: progress.fraction, elapsed: elapsed) {
            return "about \(seconds) s left"
        }
        return "Working…"
    }

    private func checklist(_ progress: ImportProgress?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(OnboardingImportPresentation.rows.enumerated()), id: \.element) { index, phase in
                let state = OnboardingImportPresentation.state(of: phase, progress: progress)
                HStack(spacing: VSpacing.l) {
                    indicator(state)
                    Text(title(phase))
                        .vTextStyle(.bodyStrong)
                        .fontWeight(state == .active ? .bold : .semibold)
                        .foregroundStyle(state == .pending ? Color.vInkSecondary : Color.vInk)
                    Spacer(minLength: 0)
                    if let detail = detail(phase, state: state, progress: progress) {
                        Text(detail).vTextStyle(.subheadline).foregroundStyle(.vInkSecondary)
                    }
                }
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
                if index < OnboardingImportPresentation.rows.count - 1 { Divider().overlay(Color.vSeparator) }
            }
        }
        .padding(.horizontal, VSpacing.xxl)
        .padding(.vertical, VSpacing.xxs)
        .frame(maxWidth: .infinity)
        .vCard(padding: 0)
        .padding(.horizontal, VSpacing.screenGutter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import steps")
    }

    @ViewBuilder
    private func indicator(_ state: ImportStepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.vPositive, in: .circle)
                .accessibilityLabel("Done")
        case .active:
            ProgressView()
                .controlSize(.small)
                .tint(.vInk)
                .frame(width: 24, height: 24)
                .accessibilityLabel("In progress")
        case .pending:
            Circle()
                .strokeBorder(Color.vInkDisabled, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 24, height: 24)
                .accessibilityLabel("Waiting")
        }
    }

    private func title(_ phase: ImportPhase) -> LocalizedStringKey {
        switch phase {
        case .sleep: "Sleep"
        case .vitals: "Heart rate, HRV & vitals"
        case .workouts: "Workouts & routes"
        case .baselines: "Building your baselines"
        default: "Calculating scores"
        }
    }

    private func detail(_ phase: ImportPhase, state: ImportStepState, progress: ImportProgress?) -> LocalizedStringKey? {
        guard let progress, state != .pending else { return nil }
        switch phase {
        case .sleep:
            return state == .done && progress.nightsImported > 0 ? "\(progress.nightsImported) nights" : (state == .done ? "Done" : nil)
        case .vitals:
            return state == .done ? "Done" : nil
        case .workouts:
            if progress.workoutsTotal > 0 { return "\(progress.workoutsImported) of \(progress.workoutsTotal)" }
            return state == .done ? "Done" : nil
        default:
            return state == .done ? "Done" : nil
        }
    }

    private var footer: some View {
        VStack(spacing: VSpacing.l) {
            if model.importFailed {
                PrimaryButton("Try again") { model.retryImport(in: container) }
                SecondaryButton("Open Vigil anyway") { model.complete(in: container) }
            } else {
                PrimaryButton("Open Vigil") { model.complete(in: container) }
                    .disabled(!model.isImportFinished)
                OnboardingCaption("Stays on this iPhone. Nothing is uploaded.")
            }
        }
        .padding(.horizontal, VSpacing.huge)
        .padding(.top, VSpacing.s)
        .padding(.bottom, VSpacing.xs)
        .background(Color.vBackground)
    }
}

#Preview {
    HistoryImportView().environment(OnboardingModel()).vigilPreview(.newUser, onboarded: false, navigation: false)
}

#Preview("Dark") {
    HistoryImportView().environment(OnboardingModel()).vigilPreview(.newUser, onboarded: false, navigation: false)
        .preferredColorScheme(.dark)
}
