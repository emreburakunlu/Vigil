import SwiftUI

/// Heart-rate zones: Automatic or Custom with per-zone upper bounds, validated to be ascending.
struct ProfileZonesSection: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var draft: [Int] = []
    @FocusState private var focusedZone: Int?

    var body: some View {
        let settings = settingsStore.settings
        let zones = container.repository.heartRateZones()
        let isCustom = settings.heartRateZones.usesCustomZones
        let error = isCustom ? ProfileLogic.validateZoneBounds(draft, maxHeartRate: zones.maxHeartRate) : nil

        ProfileSectionLabel("Heart rate zones")
        ProfileCard {
            ProfileSegmentRow(selection: Binding(
                get: { settingsStore.settings.heartRateZones.usesCustomZones },
                set: { setCustom($0, current: zones) }),
                              options: [false, true]) { $0 ? "Custom" : "Automatic" }
            ForEach(zones.zones) { zone in
                HStack(spacing: VSpacing.l) {
                    Text("Z\(zone.number)").font(.vCustom(.body, size: 13, weight: .heavy, relativeTo: .caption))
                        .foregroundStyle(Color.vInk)
                        .frame(width: 34, height: 26)
                        .background(Color.vZone(zone.number), in: .rect(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(zone.name)).vTextStyle(.body).foregroundStyle(Color.vInk)
                    Spacer(minLength: VSpacing.s)
                    if isCustom, zone.number < 5 {
                        Text("\(zone.lowerBound)–").vTextStyle(.bodyStrong).foregroundStyle(Color.vInkSecondary)
                        TextField("bpm", value: boundBinding(zone.number - 1), format: .number)
                            .keyboardType(.numberPad)
                            .focused($focusedZone, equals: zone.number)
                            .multilineTextAlignment(.center)
                            .vTextStyle(.bodyStrong)
                            .frame(width: 56, height: 34)
                            .background(Color.vFill, in: .rect(cornerRadius: 10, style: .continuous))
                            .accessibilityLabel("Zone \(zone.number) upper bound")
                    } else {
                        Text("\(zone.lowerBound)–\(zone.upperBound)").vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
                    }
                    Text("bpm").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                }
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
            }
            if let error {
                Label(message(for: error), systemImage: "exclamationmark.circle.fill")
                    .vTextStyle(.footnote).foregroundStyle(Color.vDangerInk)
                    .padding(.vertical, VSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !isCustom {
                Text("Based on your max heart rate of \(zones.maxHeartRate) bpm.")
                    .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                    .padding(.vertical, VSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { syncDraft(zones) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedZone = nil } }
        }
    }

    private func syncDraft(_ zones: HeartRateZones) {
        let stored = settingsStore.settings.heartRateZones.customUpperBounds
        draft = stored.count == 4 ? stored : zones.zones.prefix(4).map(\.upperBound)
    }

    private func setCustom(_ custom: Bool, current zones: HeartRateZones) {
        if custom {
            let stored = settingsStore.settings.heartRateZones.customUpperBounds
            let start = stored.count == 4 ? stored : zones.zones.prefix(4).map(\.upperBound)
            draft = start
            settingsStore.update { $0.heartRateZones.usesCustomZones = true; $0.heartRateZones.customUpperBounds = start }
        } else {
            settingsStore.update { $0.heartRateZones.usesCustomZones = false }
        }
    }

    /// Edits the draft immediately; only valid sets are persisted.
    private func boundBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { index < draft.count ? draft[index] : 0 },
            set: { value in
                guard index < draft.count else { return }
                draft[index] = value
                let maxHR = container.repository.heartRateZones().maxHeartRate
                if ProfileLogic.validateZoneBounds(draft, maxHeartRate: maxHR) == nil {
                    settingsStore.update { $0.heartRateZones.customUpperBounds = draft }
                }
            })
    }

    private func message(for error: ProfileZoneBoundsError) -> LocalizedStringKey {
        switch error {
        case .wrongCount: "Enter an upper bound for zones 1 to 4."
        case .tooLow: "Zone 1 must end at 30 bpm or more."
        case .notAscending: "Each zone must end higher than the one before. Your last valid zones stay in use."
        case .aboveMax: "Zone 4 must end below your max heart rate."
        }
    }
}
