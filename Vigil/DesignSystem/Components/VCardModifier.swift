import SwiftUI

/// Standard card surface: `vCard` fill, 24 pt continuous corners, hairline outline and soft shadow
/// (design: `box-shadow: 0 1px 2px rgba(18,20,26,.04), 0 0 0 1px rgba(18,20,26,.05)`).
/// Owner: design-system agent — extend with more shared components here (rings, chips, segmented control…).
struct VCardModifier: ViewModifier {
    var padding: CGFloat = VSpacing.cardPadding
    var radius: CGFloat = VRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.vCard, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
            .shadow(color: .vShadow, radius: 1, y: 1)
    }
}

extension View {
    /// Wraps content in the standard Vigil card.
    func vCard(padding: CGFloat = VSpacing.cardPadding, radius: CGFloat = VRadius.card) -> some View {
        modifier(VCardModifier(padding: padding, radius: radius))
    }
}
