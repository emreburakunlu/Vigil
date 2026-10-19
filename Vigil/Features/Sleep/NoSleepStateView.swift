import SwiftUI

/// State · No sleep recorded (embedded by `SleepView` when last night is missing).
struct NoSleepStateView: View {
    var body: some View {
        ScreenPlaceholder(title: "No sleep recorded", subtitle: "Apple Health has no sleep data for last night.", night: true) {}
    }
}

#Preview {
    NoSleepStateView().vigilPreview(.noSleepLastNight)
}
