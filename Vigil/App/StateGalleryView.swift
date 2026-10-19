#if DEBUG
import SwiftUI

/// Developer-only list of state screens (reachable from Profile in DEBUG builds).
struct StateGalleryView: View {
    var body: some View {
        ScreenPlaceholder(title: "States", subtitle: "Developer gallery of empty and error states.") {
            NavigationLink { HealthAccessDeniedView(onRetry: {}) } label: { PlaceholderRow(title: "Health access denied", showsChevron: true) }
                .buttonStyle(.plain)
            NavigationLink { NoSleepStateView() } label: { PlaceholderRow(title: "No sleep recorded", showsChevron: true) }
                .buttonStyle(.plain)
            NavigationLink { NoRunsStateView() } label: { PlaceholderRow(title: "No runs this week", showsChevron: true) }
                .buttonStyle(.plain)
            PlaceholderRow(title: "Partial data", detail: "Launch with -VigilMockScenario partialData and open Today.")
        }
    }
}

#Preview {
    StateGalleryView().vigilPreview()
}
#endif
