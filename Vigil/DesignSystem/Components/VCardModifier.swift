import SwiftUI

/// Standard card surface: `vCard` fill, continuous corners, hairline outline and soft shadow
/// (design: `box-shadow: 0 1px 2px rgba(18,20,26,.04), 0 0 0 1px rgba(18,20,26,.05)`).
/// `surface` lets the Sleep tab use the night card without a second modifier.
struct VCardModifier: ViewModifier {
    var padding: CGFloat = VSpacing.cardPadding
    var radius: CGFloat = VRadius.card
    var surface: Color = .vCard
    var outline: Color = .vHairline

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(surface, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(outline, lineWidth: VSize.hairline))
            .shadow(color: .vShadow, radius: 1, y: 1)
    }
}

extension View {
    /// Wraps content in the standard Vigil card.
    ///
    /// ```swift
    /// VStack { … }.vCard()                      // 18 pt padding, 24 pt radius
    /// row.vCard(padding: 14, radius: 22)        // compact list-row card
    /// ```
    func vCard(padding: CGFloat = VSpacing.cardPadding, radius: CGFloat = VRadius.card) -> some View {
        modifier(VCardModifier(padding: padding, radius: radius))
    }

    /// Card on the night palette (Sleep tab).
    func vNightCard(padding: CGFloat = VSpacing.cardPadding, radius: CGFloat = VRadius.card) -> some View {
        modifier(VCardModifier(padding: padding, radius: radius, surface: .vNightCard, outline: .vNightSeparator))
    }
}

/// Container form of the card: `VCard { … }`.
struct VCard<Content: View>: View {
    var padding: CGFloat = VSpacing.cardPadding
    var radius: CGFloat = VRadius.card
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.l) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard(padding: padding, radius: radius)
    }
}

#Preview("Card") {
    VCard {
        Text("Vitals").vTextStyle(.headline).foregroundStyle(Color.vInk)
        Text("vs. 30-day baseline").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
    }
    .padding(16)
    .background(Color.vBackground)
}
