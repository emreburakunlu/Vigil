import SwiftUI

// MARK: - Buttons
//
// Design: Design/Onb*.dc.html (56 pt pill buttons), Main.dc.html (44 pt round header buttons).

/// 44 pt round header button (previous day, calendar, close…).
///
/// ```swift
/// CircleIconButton(systemImage: "chevron.left", label: "Previous day") { model.step(-1) }
/// ```
struct CircleIconButton: View {
    let systemImage: String
    /// VoiceOver label (required: the button has no text).
    let label: LocalizedStringKey
    var isDisabled = false
    /// Opt-in accent icon colour; the default is the neutral ink glyph on a white (card) circle.
    var usesAccent = false
    let action: () -> Void

    @Environment(\.vSurface) private var surface

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(usesAccent ? surface.accent : surface.ink)
                .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                .background(surface == .night ? Color.vNightCardRaised : Color.vCard, in: .circle)
                .overlay(Circle().strokeBorder(surface == .night ? Color.vNightSeparator : Color.vHairline, lineWidth: VSize.hairline))
                .contentShape(.circle)
        }
        .buttonStyle(.vPress)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}

/// Visual variants of the full-width pill button.
enum VButtonKind: Sendable {
    /// Brand-violet fill, white label (onboarding CTA).
    case primary
    /// Ink fill (inverts in dark), for "Continue" on neutral screens.
    case inverse
    /// Card fill with hairline and ink label.
    case secondary
    /// Red label on danger tint (delete data).
    case destructive
}

/// `ButtonStyle` behind `PrimaryButton` / `SecondaryButton`; use directly for custom labels.
struct VPillButtonStyle: ButtonStyle {
    var kind: VButtonKind = .primary
    var height: CGFloat = VSize.primaryButtonHeight
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.vStatValueSmall.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background, in: .rect(cornerRadius: height / 2, style: .continuous))
            .overlay {
                if kind == .secondary && isEnabled {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline)
                }
            }
            .contentShape(.rect(cornerRadius: height / 2, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? VMotion.pressScale : 1)
            .animation(reduceMotion ? nil : VMotion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return .vButtonDisabledInk }
        return switch kind {
        case .primary: .vInkOnAccent
        case .inverse: .vInkOnInverse
        case .secondary: .vInk
        case .destructive: .vDangerInk
        }
    }

    private var background: Color {
        guard isEnabled else { return .vButtonDisabled }
        return switch kind {
        case .primary: .vPrimaryButton
        case .inverse: .vInverseFill
        case .secondary: .vCard
        case .destructive: .vDangerTint
        }
    }
}

extension ButtonStyle where Self == VPillButtonStyle {
    /// Full-width pill button style.
    static func vPill(_ kind: VButtonKind = .primary) -> VPillButtonStyle { VPillButtonStyle(kind: kind) }
}

/// Full-width 56 pt primary call-to-action.
///
/// ```swift
/// PrimaryButton("Allow Health access", systemImage: "heart.fill") { … }
/// PrimaryButton("Continue", kind: .inverse) { … }.disabled(!isValid)
/// ```
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var kind: VButtonKind = .primary
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, kind: VButtonKind = .primary, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VSpacing.m) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title)
            }
        }
        .buttonStyle(.vPill(kind))
    }
}

/// Full-width secondary button (card fill, hairline).
struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isDestructive = false
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VSpacing.m) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title)
            }
        }
        .buttonStyle(.vPill(isDestructive ? .destructive : .secondary))
    }
}

/// Plain accent text button ("Not now", "See all").
struct VTextButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    @Environment(\.vSurface) private var surface

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .vTextStyle(.bodyStrong)
                .foregroundStyle(surface.accent)
                .frame(minHeight: VSize.minTapTarget)
        }
        .buttonStyle(.vPress)
    }
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        HStack { CircleIconButton(systemImage: "chevron.left", label: "Previous day") {}; CircleIconButton(systemImage: "calendar", label: "Choose a date") {}; CircleIconButton(systemImage: "chevron.right", label: "Next day", isDisabled: true) {} }
        PrimaryButton("Allow Health access", systemImage: "heart.fill") {}
        PrimaryButton("Continue", kind: .inverse) {}
        PrimaryButton("Continue") {}.disabled(true)
        SecondaryButton("Edit goals") {}
        SecondaryButton("Delete all data", isDestructive: true) {}
        VTextButton("Not now") {}
    }
    .padding()
    .background(Color.vBackground)
}
