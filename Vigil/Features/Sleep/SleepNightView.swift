import SwiftUI

/// Sleep night detail for the night ending on `day`.
struct SleepNightView: View {
    let day: LocalDay

    var body: some View {
        ScreenPlaceholder(title: "Night", subtitle: day.isoString, night: true) {}
    }
}

#Preview {
    SleepNightView(day: .today()).vigilPreview()
}
