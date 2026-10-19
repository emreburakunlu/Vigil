import SwiftUI

// TEMPORARY scaffolding used by Phase 0 placeholder screens. Screen agents replace their
// placeholder bodies; delete this file once no screen uses it.

/// A titled placeholder screen built only from design tokens.
struct ScreenPlaceholder<Content: View>: View {
    let title: String
    let subtitle: String
    var night: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                VStack(alignment: .leading, spacing: VSpacing.xxs) {
                    Text(title)
                        .vTextStyle(.largeTitle)
                        .foregroundStyle(night ? Color.vNightInk : Color.vInk)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .vTextStyle(.callout)
                        .foregroundStyle(night ? Color.vNightInkSecondary : Color.vInkSecondary)
                }
                .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                content
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.vertical, VSpacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(night ? Color.vNightBackground : Color.vBackground)
        .toolbarTitleDisplayMode(.inline)
    }
}

/// A card-style navigation row pushing an `AppRoute`.
struct PlaceholderLink: View {
    let title: String
    var detail: String?
    let route: AppRoute

    init(_ title: String, detail: String? = nil, route: AppRoute) {
        self.title = title
        self.detail = detail
        self.route = route
    }

    var body: some View {
        NavigationLink(value: route) {
            PlaceholderRow(title: title, detail: detail, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}

/// A card-style row.
struct PlaceholderRow: View {
    let title: String
    var detail: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: VSpacing.l) {
            VStack(alignment: .leading, spacing: VSpacing.xxxs) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(.vInk)
                if let detail {
                    Text(detail).vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.vFootnote)
                    .foregroundStyle(.vInkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(VSpacing.cardPaddingCompact)
        .frame(maxWidth: .infinity, minHeight: VSize.minTapTarget, alignment: .leading)
        .background(Color.vCard, in: .rect(cornerRadius: VRadius.card, style: .continuous))
        .contentShape(.rect)
    }
}

/// Full-width primary button used by placeholder onboarding steps.
struct PlaceholderPrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .vTextStyle(.bodyStrong)
                .foregroundStyle(.vInkOnInverse)
                .frame(maxWidth: .infinity, minHeight: VSize.primaryButtonHeight)
                .background(Color.vInverseFill, in: .rect(cornerRadius: VRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
