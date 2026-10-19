import SwiftUI

/// Sleep calendar for the month containing `month`.
struct SleepCalendarView: View {
    let month: LocalDay

    var body: some View {
        ScreenPlaceholder(title: "Sleep calendar", subtitle: "\(month.year)-\(month.month)", night: true) {}
    }
}

#Preview {
    SleepCalendarView(month: .today()).vigilPreview()
}
