import SwiftUI

/// Train · Lift: weekly sessions and the list of strength workouts.
struct TrainLiftView: View {
    @Environment(AppContainer.self) private var container
    @State private var lifts: [WorkoutSummary] = []

    var body: some View {
        ScreenPlaceholder(title: "Lift", subtitle: "Workout-level data from Health") {
            ForEach(lifts) { lift in
                PlaceholderLink(lift.workout.displayName, detail: "via \(lift.workout.source.name)", route: .liftDetail(lift.id))
            }
        }
        .task {
            let interval = DateInterval(start: Date.now.addingTimeInterval(-30 * 86_400), end: .now)
            lifts = (try? await container.repository.workouts(.strength, in: interval)) ?? []
        }
    }
}

#Preview {
    TrainLiftView().vigilPreview()
}
