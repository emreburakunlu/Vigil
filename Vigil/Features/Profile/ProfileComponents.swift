import SwiftUI

/// Card that stacks its rows with hairline separators.
struct ProfileCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id { Divider().overlay(Color.vSeparator) }
                }
            }
        }
        .padding(.horizontal, VSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.vCard, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
    }
}

/// Section label above a card.
struct ProfileSectionLabel: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        OverlineLabel(title)
            .padding(.horizontal, VSpacing.l)
            .padding(.top, VSpacing.huge - VSpacing.cardGap + VSpacing.s)
    }
}

/// Tappable row: title (+ subtitle) left, value and chevron right.
struct ProfileRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var value: String?
    var showsChevron = true
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VSpacing.l) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).vTextStyle(.body).foregroundStyle(isDestructive ? Color.vDangerInk : Color.vInk)
                    if let subtitle { Text(subtitle).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary) }
                }
                Spacer(minLength: VSpacing.s)
                if let value {
                    Text(value).vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel).multilineTextAlignment(.trailing)
                }
                if showsChevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.vInkTertiary).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Non-interactive row (label + value).
struct ProfileInfoRow<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: VSpacing.l) {
            Text(title).vTextStyle(.body).foregroundStyle(Color.vInk)
            Spacer(minLength: VSpacing.s)
            value
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Segmented control row filling a card slot.
struct ProfileSegmentRow<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> LocalizedStringKey

    var body: some View {
        VSegmentedControl(selection: $selection, options: options, title: title)
            .padding(.vertical, VSpacing.m)
    }
}

/// Wrapper for the small editing sheets.
struct ProfileSheetScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var detents: Set<PresentationDetent> = [.medium]
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.xxl) { content }
                    .padding(VSpacing.screenGutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.vBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(detents)
    }
}
