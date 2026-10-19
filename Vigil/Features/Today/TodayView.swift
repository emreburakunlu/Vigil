import SwiftUI

/// Tab 1 · Today. Also renders the partial-data state when `overview.completeness` is `.partial`.
/// Owner: Today agent.
struct TodayView: View {
    @Environment(AppContainer.self) private var container
    @State private var overview: DayOverview?

    private var day: LocalDay { container.repository.today }

    var body: some View {
        ScreenPlaceholder(title: "Today", subtitle: scoresLine) {
            PlaceholderLink("Recovery", detail: overview?.recovery?.message, route: .recovery(day))
            PlaceholderLink("Strain", route: .strain(day))
            ForEach(HealthMetric.vitals) { metric in
                PlaceholderLink(metric.displayName, route: .metric(metric, day))
            }
            ForEach(overview?.workouts ?? []) { item in
                PlaceholderLink(item.workout.displayName,
                                route: item.workout.kind == .run ? .runDetail(item.id) : .liftDetail(item.id))
            }
            if case .partial(let missing) = overview?.completeness {
                PlaceholderRow(title: "Partial data", detail: "Missing: " + missing.map(\.shortName).joined(separator: ", "))
            }
        }
        .task { overview = try? await container.repository.dayOverview(for: day) }
    }

    private var scoresLine: String {
        guard let overview else { return "Loading…" }
        let recovery = overview.recovery.map { "Recovery \($0.value)%" } ?? "Recovery –"
        let sleep = overview.sleepScore.map { "Sleep \($0.value)" } ?? "Sleep –"
        let strain = overview.strain.map { "Strain \($0.value)" } ?? "Strain –"
        return [recovery, sleep, strain].joined(separator: " · ")
    }
}

#Preview {
    TodayView().vigilPreview()
}

#Preview("Partial data") {
    TodayView().vigilPreview(.partialData)
}
