import SwiftUI

/// State · No runs this week (embedded by `TrainRunView` under the weekly card).
struct NoRunsStateView: View {
    /// The most recent older run, offered as a shortcut.
    var lastRun: WorkoutSummary?
    @Environment(SettingsStore.self) private var settingsStore

    init(lastRun: WorkoutSummary? = nil) {
        self.lastRun = lastRun
    }

    var body: some View {
        VStack(spacing: VSpacing.m) {
            Image(systemName: "figure.run")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.vRun)
                .frame(width: 56, height: 56)
                .background(Color.vRunTint, in: .rect(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("No runs this week").vTextStyle(.title2).foregroundStyle(Color.vInk).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Runs from your Apple Watch, or any app that saves to Health, appear here on their own.")
                .vTextStyle(.callout).foregroundStyle(Color.vInkLabel).multilineTextAlignment(.center)
            if let lastRun {
                NavigationLink(value: AppRoute.runDetail(lastRun.id)) {
                    HStack(spacing: VSpacing.s) {
                        Text(lastRunTitle(lastRun)).vTextStyle(.bodyStrong).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.vInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: VSize.minTapTarget)
                    .background(Color.vCard, in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
                }
                .buttonStyle(.vPress)
                .padding(.top, VSpacing.xxs)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: VRadius.cardLarge, style: .continuous)
            .strokeBorder(Color.vInkDisabled, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
    }

    private func lastRunTitle(_ run: WorkoutSummary) -> String {
        let formatter = settingsStore.formatter
        let calendar = Calendar.current
        let day = run.workout.start.formatted(Date.FormatStyle(calendar: calendar).weekday(.abbreviated).month(.abbreviated).day())
        let distance = run.workout.distanceMeters.map { " · " + formatter.distance(meters: $0, fractionDigits: 1).text } ?? ""
        return String(localized: "Last run") + " · " + day + distance
    }
}

#Preview {
    TrainView().vigilPreview(.noRunsThisWeek)
}
