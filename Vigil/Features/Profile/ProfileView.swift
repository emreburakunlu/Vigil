import SwiftUI

/// Tab 5 · Profile & settings. Owner: Profile agent. Every setting reads and writes through `SettingsStore`.
struct ProfileView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openURL) private var openURL
    @State private var model = ProfileModel()
    @State private var sheet: ProfileSheet?
    @State private var confirmsDelete = false
    @State private var deleteFailed = false

    var body: some View {
        let settings = settingsStore.settings
        let formatter = settingsStore.formatter
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.s) {
                Text("Profile").vTextStyle(.largeTitle).foregroundStyle(Color.vInk)
                    .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                    .accessibilityAddTraits(.isHeader)
                summary
                profileSection(settings, formatter)
                goalsSection(settings, formatter)
                unitsSection
                ProfileZonesSection()
                healthSection
                notificationsSection(settings)
                appearanceSection
                dataSection
                aboutSection
                #if DEBUG
                ProfileSectionLabel("Developer")
                ProfileCard {
                    NavigationLink(value: AppRoute.stateGallery) {
                        HStack {
                            Text("States gallery").vTextStyle(.body).foregroundStyle(Color.vInk)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.vInkTertiary).accessibilityHidden(true)
                        }
                        .frame(minHeight: 52).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            .padding(.bottom, VSpacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.vBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(container: container) }
        .sheet(item: $sheet, onDismiss: { model.resetImport(); Task { await model.load(container: container) } }) { sheet in
            switch sheet {
            case .age: ProfileAgeSheet()
            case .sex: ProfileSexSheet()
            case .weight: ProfileWeightSheet(healthBodyMass: model.healthBodyMass)
            case .maxHeartRate: ProfileMaxHeartRateSheet(estimated: estimatedMaxHeartRate)
            case .sleepGoal: ProfileSleepGoalSheet()
            case .runGoal: ProfileRunGoalSheet()
            case .liftGoal: ProfileLiftGoalSheet()
            case .privacy: ProfilePrivacySheet()
            case .export: ProfileExportSheet(model: model)
            case .reimport: ProfileReimportSheet(model: model)
            }
        }
        .confirmationDialog("Delete local data?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete local data", role: .destructive) {
                do { try container.deleteAllLocalData() } catch { deleteFailed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Vigil's scores, baselines and settings from this iPhone and returns to setup. Your Apple Health data is not touched.")
        }
        .alert("Couldn't delete data", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Sections

    private var summary: some View {
        HStack(spacing: VSpacing.xl) {
            Image(systemName: "eye")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.vInk)
                .frame(width: 52, height: 52)
                .background(Color.vInkOnAccent, in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your Vigil").vTextStyle(.statValueSmall)
                Text("\(model.cachedDays) days of history · stored on this iPhone").vTextStyle(.footnote).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.vInkOnAccent)
        .padding(VSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vAccent, in: .rect(cornerRadius: VRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func profileSection(_ settings: VigilSettings, _ formatter: VigilFormatter) -> some View {
        let profile = settings.profile
        let age = ProfileLogic.age(from: profile.dateOfBirth, now: container.repository.now(), calendar: container.repository.calendar)
        let weightKg = profile.bodyMassFromHealth ? (model.healthBodyMass ?? profile.bodyMassKilograms) : profile.bodyMassKilograms
        ProfileSectionLabel("Profile")
        ProfileCard {
            ProfileRow(title: "Age", value: age.map(String.init) ?? String(localized: "Not set")) { sheet = .age }
            ProfileRow(title: "Sex", value: profile.sex.map { Self.sexName($0) } ?? String(localized: "Not set")) { sheet = .sex }
            ProfileRow(title: "Body weight", subtitle: profile.bodyMassFromHealth ? "Synced from Health" : nil,
                       value: weightKg.map { formatter.weight(kilograms: $0).text } ?? String(localized: "Not set")) { sheet = .weight }
            ProfileRow(title: "Max heart rate", subtitle: profile.estimatesMaxHeartRate ? "Estimated" : "Manual",
                       value: "\(container.repository.heartRateZones().maxHeartRate) bpm") { sheet = .maxHeartRate }
        }
    }

    @ViewBuilder
    private func goalsSection(_ settings: VigilSettings, _ formatter: VigilFormatter) -> some View {
        ProfileSectionLabel("Goals")
        ProfileCard {
            ProfileRow(title: "Nightly sleep", value: VigilFormatter.duration(settings.goals.sleepTarget)) { sheet = .sleepGoal }
            ProfileRow(title: "Weekly running", value: formatter.distance(meters: settings.goals.weeklyRunDistanceMeters, fractionDigits: 0).text) { sheet = .runGoal }
            ProfileRow(title: "Weekly lifting", value: settings.goals.weeklyLiftSessions == 1 ? String(localized: "1 session") : String(localized: "\(settings.goals.weeklyLiftSessions) sessions")) { sheet = .liftGoal }
        }
    }

    @ViewBuilder
    private var unitsSection: some View {
        ProfileSectionLabel("Units")
        ProfileCard {
            ProfileSegmentRow(selection: settingsStore.binding(\.units), options: UnitSystem.allCases) {
                $0 == .metric ? "kg · km" : "lb · mi"
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        ProfileSectionLabel("Apple Health")
        ProfileCard {
            ProfileInfoRow(title: "Access") {
                HStack(spacing: VSpacing.xs) {
                    Circle().fill(healthColor).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(healthText).vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
                }
            }
            ProfileRow(title: "Manage permissions", showsChevron: true) {
                if let url = URL(string: "app-settings:") ?? URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            ProfileRow(title: "Open Health", showsChevron: true) {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
        }
    }

    private var healthText: LocalizedStringKey {
        switch model.healthState {
        case .connected: "Connected"
        case .likelyDenied: "Access off"
        case .notDetermined: "Not connected"
        case .unavailable: "Unavailable"
        case nil: "Checking…"
        }
    }

    private var healthColor: Color {
        switch model.healthState {
        case .connected: .vPositive
        case .likelyDenied: .vDanger
        default: .vInkTertiary
        }
    }

    @ViewBuilder
    private func notificationsSection(_ settings: VigilSettings) -> some View {
        let prefs = settings.notifications
        ProfileSectionLabel("Notifications")
        ProfileCard {
            toggleRow("Morning recovery summary", subtitle: "After you wake, or at the time below", isOn: Binding(
                get: { settingsStore.settings.notifications.morningSummaryEnabled },
                set: { setNotification { $0.morningSummaryEnabled = $1 }($0) }))
            timeRow("Time", minutes: prefs.morningSummaryMinutes, enabled: prefs.morningSummaryEnabled) { minutes in
                updateNotifications { $0.morningSummaryMinutes = minutes }
            }
            toggleRow("Bedtime reminder", subtitle: "Based on your \(VigilFormatter.duration(settings.goals.sleepTarget)) sleep target", isOn: Binding(
                get: { settingsStore.settings.notifications.bedtimeReminderEnabled },
                set: { setNotification { $0.bedtimeReminderEnabled = $1 }($0) }))
            timeRow("Remind me at", minutes: prefs.bedtimeReminderMinutes, enabled: prefs.bedtimeReminderEnabled) { minutes in
                updateNotifications { $0.bedtimeReminderMinutes = minutes }
            }
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).vTextStyle(.body).foregroundStyle(Color.vInk)
                Text(subtitle).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
            }
        }
        .tint(.vPositive)
        .frame(minHeight: 56)
    }

    private func timeRow(_ title: LocalizedStringKey, minutes: Int, enabled: Bool, set: @escaping (Int) -> Void) -> some View {
        DatePicker(title, selection: Binding(
            get: { ProfileLogic.date(fromMinutes: minutes) },
            set: { set(ProfileLogic.minutes(from: $0)) }), displayedComponents: .hourAndMinute)
            .vTextStyle(.body)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .frame(minHeight: 52)
    }

    /// Returns a setter that persists a toggle and asks for permission when switching on.
    private func setNotification(_ change: @escaping (inout NotificationPreferences, Bool) -> Void) -> (Bool) -> Void {
        { value in
            updateNotifications { change(&$0, value) }
            if value { Task { _ = await container.notifications.requestAuthorizationIfNeeded(); await reschedule() } }
        }
    }

    private func updateNotifications(_ change: (inout NotificationPreferences) -> Void) {
        settingsStore.update { change(&$0.notifications) }
        Task { await reschedule() }
    }

    private func reschedule() async {
        await container.notifications.sync(settings: settingsStore.settings, snapshot: WidgetSnapshotStore().load())
    }

    @ViewBuilder
    private var appearanceSection: some View {
        ProfileSectionLabel("Appearance")
        ProfileCard {
            ProfileSegmentRow(selection: settingsStore.binding(\.appearance), options: [.light, .dark, .system]) {
                switch $0 {
                case .light: "Light"
                case .dark: "Dark"
                case .system: "System"
                }
            }
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        ProfileSectionLabel("Data")
        ProfileCard {
            ProfileRow(title: "Export all data", value: "CSV · JSON") { sheet = .export }
            ProfileRow(title: "Re-import history from Health") { sheet = .reimport }
            ProfileRow(title: "Delete local data", showsChevron: false, isDestructive: true) { confirmsDelete = true }
        }
        Text("Deleting removes Vigil's scores and baselines. Your Apple Health data is not touched.")
            .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
            .padding(.horizontal, VSpacing.l)
    }

    @ViewBuilder
    private var aboutSection: some View {
        ProfileSectionLabel("About")
        ProfileCard {
            VStack(alignment: .leading, spacing: VSpacing.xs) {
                Label("Your data stays on this iPhone", systemImage: "lock.shield")
                    .vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                Text("Vigil has no account, no servers and no analytics. It reads Apple Health on device and never writes to it.")
                    .vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
            }
            .padding(.vertical, VSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            ProfileRow(title: "Version \(Self.versionText)", value: String(localized: "Privacy statement")) { sheet = .privacy }
        }
    }

    // MARK: Helpers

    private var estimatedMaxHeartRate: Int {
        var profile = settingsStore.settings.profile
        profile.estimatesMaxHeartRate = true
        return container.engine.heartRateZones(profile: profile, settings: .default, observedMaxHeartRate: nil,
                                               on: container.repository.now()).maxHeartRate
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    static func sexName(_ sex: BiologicalSex) -> String {
        switch sex {
        case .female: String(localized: "Female")
        case .male: String(localized: "Male")
        case .other: String(localized: "Other")
        }
    }
}

#Preview("Profile") { ProfileView().vigilPreview() }
#Preview("Profile dark") { ProfileView().vigilPreview().preferredColorScheme(.dark) }
