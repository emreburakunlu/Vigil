import SwiftUI

/// Tab 5 · Profile & settings. Owner: Profile agent.
struct ProfileView: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ScreenPlaceholder(title: "Profile", subtitle: "Your data stays on this iPhone") {
            Picker("Units", selection: settingsStore.binding(\.units)) {
                Text("kg · km").tag(UnitSystem.metric)
                Text("lb · mi").tag(UnitSystem.imperial)
            }
            .pickerStyle(.segmented)
            Picker("Appearance", selection: settingsStore.binding(\.appearance)) {
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
                Text("System").tag(AppearanceMode.system)
            }
            .pickerStyle(.segmented)
            #if DEBUG
            PlaceholderLink("Developer · States", route: .stateGallery)
            #endif
        }
    }
}

#Preview {
    ProfileView().vigilPreview()
}
