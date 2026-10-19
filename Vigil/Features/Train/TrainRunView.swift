import SwiftUI

/// Train · Run: weekly distance and the list of runs (shows `NoRunsStateView` when empty).
struct TrainRunView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var runs: [WorkoutSummary] = []

    var body: some View {
        ScreenPlaceholder(title: "Run", subtitle: "From Apple Health") {
            ForEach(runs) { run in
                PlaceholderLink(run.workout.displayName,
                                detail: run.workout.distanceMeters.map { settingsStore.formatter.distance(meters: $0).text },
                                route: .runDetail(run.id))
            }
        }
        .task {
            let interval = DateInterval(start: Date.now.addingTimeInterval(-30 * 86_400), end: .now)
            runs = (try? await container.repository.workouts(.run, in: interval)) ?? []
        }
    }
}

#Preview {
    TrainRunView().vigilPreview()
}
