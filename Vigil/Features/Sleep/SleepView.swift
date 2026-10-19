import SwiftUI

/// Tab 2 · Sleep (night palette). Shows `NoSleepStateView` content when last night is missing.
/// Owner: Sleep agent.
struct SleepView: View {
    @Environment(AppContainer.self) private var container

    private var day: LocalDay { container.repository.today }

    var body: some View {
        ScreenPlaceholder(title: "Sleep", subtitle: "Last night", night: true) {
            PlaceholderLink("Last night", route: .sleepNight(day))
            PlaceholderLink("Sleep calendar", route: .sleepCalendar(day))
        }
    }
}

#Preview {
    SleepView().vigilPreview()
}
