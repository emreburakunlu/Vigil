import SwiftUI

/// Sleep night detail for the night ending on `day`. Previous/next step through nights in place.
struct SleepNightView: View {
    let day: LocalDay

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = SleepNightScreenModel()
    @State private var shownDay: LocalDay?

    private var repository: VigilRepository { container.repository }
    private var current: LocalDay { shownDay ?? day }
    private var today: LocalDay { container.currentDay }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.xl) {
                stepper
                content
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vNightScreen()
        .navigationTitle(SleepFormat.nightRange(for: current, calendar: repository.calendar))
        .navigationSubtitle("Primary sleep")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: [AnyHashable(current), AnyHashable(container.dataVersion)]) {
            await model.load(repository: repository, formatter: settingsStore.formatter, day: current)
        }
        .onChange(of: container.currentDay) { old, new in
            if current == old { shownDay = new }
        }
    }

    private var stepper: some View {
        HStack(spacing: VSpacing.s) {
            Button { shownDay = current.adding(days: -1, calendar: repository.calendar) } label: {
                Label("Previous night", systemImage: "chevron.left")
            }
            .buttonStyle(NightPillStyle())
            Button { shownDay = current.adding(days: 1, calendar: repository.calendar) } label: {
                Label("Next night", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(NightPillStyle())
            .disabled(current >= today)
            .opacity(current >= today ? 0.35 : 1)
        }
        .padding(.top, VSpacing.xs)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VSkeletonStack(heights: [210, 300, 240], label: "Loading sleep")
        case .failed:
            VErrorCard(title: "Couldn't load sleep", message: "Something went wrong reading your sleep data.") {
                Task { await model.load(repository: repository, formatter: settingsStore.formatter, day: current) }
            }
        case .empty:
            SleepNoSleepCard(isLastNight: current == today)
        case .loaded(let night):
            SleepScoreCard(night: night)
            SleepStagesCard(night: night, showsEdgeTicks: true)
            if night.hasVitals { SleepVitalsCard(night: night) }
        }
    }
}

/// 44 pt pill used for previous/next night.
private struct NightPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vTextStyle(.subheadline).fontWeight(.bold)
            .foregroundStyle(Color.vNightInk)
            .frame(maxWidth: .infinity, minHeight: VSize.minTapTarget)
            .background(Color.vNightCardRaised, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: VSpacing.xs) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    SleepNightView(day: .today().adding(days: -5)).vigilPreview()
}

#Preview("Dark") {
    SleepNightView(day: .today()).vigilPreview().preferredColorScheme(.dark)
}
