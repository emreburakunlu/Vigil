import SwiftUI
import UIKit

// MARK: - Semantic colour tokens
//
// GENERATED STRUCTURE, HAND-OWNED VALUES. Owner: design-system agent.
// Light values are taken from Design/*.dc.html. Dark values are TEMPORARY placeholders
// to be replaced by the design-system agent.
//
// Rules for feature code:
//  - Use only these tokens (`.foregroundStyle(.vInk)`, `.background(Color.vCard)`); never `Color(red:...)`,
//    hex literals, or system colours like `.blue` / `.gray`.
//  - Tokens are dynamic `UIColor`s, so they follow the window's `overrideUserInterfaceStyle`
//    (set from Settings → Appearance by `AppearanceController`) as well as SwiftUI's `colorScheme`.

/// Token storage (one `UIColor` provider per token). Access tokens via `Color.vX` / `.vX`.
enum VColorStorage {

    // MARK: Surfaces

    /// Screen background.
    static let vBackground = Color.vDynamic(light: (0xF4F2FA, 1), dark: (0x0E1022, 1))
    /// Card / grouped section background.
    static let vCard = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0x171A33, 1))
    /// Inset tile inside a card (stat tiles, info boxes).
    static let vCardRaised = Color.vDynamic(light: (0xF5F6F8, 1), dark: (0x1F2342, 1))
    /// Progress-bar tracks, empty heat-map cells, neutral chips.
    static let vFill = Color.vDynamic(light: (0xECE9F5, 1), dark: (0x262A4D, 1))
    /// Segmented control track.
    static let vControlTrack = Color.vDynamic(light: (0xE4E6EA, 1), dark: (0x262A4D, 1))
    /// Selected segment thumb.
    static let vControlThumb = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0x3A3F6B, 1))
    /// List row separators.
    static let vSeparator = Color.vDynamic(light: (0xEEEFF2, 1), dark: (0x2A2E52, 1))
    /// 1 pt outline drawn around cards.
    static let vHairline = Color.vDynamic(light: (0x12141A, 0.05), dark: (0xFFFFFF, 0.06))
    /// Soft card shadow colour.
    static let vShadow = Color.vDynamic(light: (0x12141A, 0.04), dark: (0x000000, 0.30))

    // MARK: Ink (text & icons)

    /// Primary text and icons.
    static let vInk = Color.vDynamic(light: (0x12141A, 1), dark: (0xF4F2FA, 1))
    /// Strong secondary text: legends, axis labels, secondary buttons.
    static let vInkLabel = Color.vDynamic(light: (0x4A505C, 1), dark: (0xC9CDE3, 1))
    /// Secondary text: dates, captions, units.
    static let vInkSecondary = Color.vDynamic(light: (0x646A78, 1), dark: (0xA3A8C3, 1))
    /// Tertiary text, neutral sparklines, chevrons.
    static let vInkTertiary = Color.vDynamic(light: (0x9AA0AC, 1), dark: (0x6E7396, 1))
    /// Disabled controls, inactive dots.
    static let vInkDisabled = Color.vDynamic(light: (0xC9CCD3, 1), dark: (0x4A4F72, 1))
    /// Inverted fill: selected day chip, primary button.
    static let vInverseFill = Color.vDynamic(light: (0x12141A, 1), dark: (0xF4F2FA, 1))
    /// Text/icons drawn on `vInverseFill`.
    static let vInkOnInverse = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0x12141A, 1))
    /// Text/icons drawn on saturated brand colours.
    static let vInkOnAccent = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0xFFFFFF, 1))

    // MARK: Brand & navigation

    /// App accent: selected tab, links, focus.
    static let vAccent = Color.vDynamic(light: (0x4B32D6, 1), dark: (0x9D8CFF, 1))
    /// Selected tab pill background.
    static let vAccentTint = Color.vDynamic(light: (0x7B61FF, 0.16), dark: (0x9D8CFF, 0.22))

    // MARK: Scores

    /// Recovery ring / green band.
    static let vRecovery = Color.vDynamic(light: (0x1DB872, 1), dark: (0x2FD38A, 1))
    /// Recovery ring track, positive chip background.
    static let vRecoveryTint = Color.vDynamic(light: (0xDCF6E8, 1), dark: (0x17382A, 1))
    /// Text on recovery tint; positive deltas.
    static let vRecoveryInk = Color.vDynamic(light: (0x157A40, 1), dark: (0x7EE2A8, 1))
    /// Sleep ring.
    static let vSleep = Color.vDynamic(light: (0x7B61FF, 1), dark: (0x9D8CFF, 1))
    /// Sleep ring track, sleep chip background.
    static let vSleepTint = Color.vDynamic(light: (0xEEEAFF, 1), dark: (0x262A4D, 1))
    /// Text on sleep tint.
    static let vSleepInk = Color.vDynamic(light: (0x4B42D6, 1), dark: (0xB7B1FF, 1))
    /// Strain ring.
    static let vStrain = Color.vDynamic(light: (0xFF6A3D, 1), dark: (0xFF7F57, 1))
    /// Strain ring track, strain chip background.
    static let vStrainTint = Color.vDynamic(light: (0xFFE9E1, 1), dark: (0x3D2219, 1))
    /// Text on strain tint.
    static let vStrainInk = Color.vDynamic(light: (0xB5480F, 1), dark: (0xFFB48F, 1))

    // MARK: Training

    /// Running: highlighted bars, routes, run chips.
    static let vRun = Color.vDynamic(light: (0x2E7CF6, 1), dark: (0x5B9BFF, 1))
    /// Running: non-highlighted bars.
    static let vRunSoft = Color.vDynamic(light: (0x9EC2FF, 1), dark: (0x3C5F99, 1))
    /// Running chip background.
    static let vRunTint = Color.vDynamic(light: (0xE7F0FF, 1), dark: (0x1A2A4A, 1))
    /// Lifting: highlighted bars and chips.
    static let vLift = Color.vDynamic(light: (0xFF6A3D, 1), dark: (0xFF7F57, 1))
    /// Lifting: non-highlighted bars.
    static let vLiftSoft = Color.vDynamic(light: (0xF8C4A3, 1), dark: (0x6B3A26, 1))
    /// Lifting chip background.
    static let vLiftTint = Color.vDynamic(light: (0xFFE9E1, 1), dark: (0x3D2219, 1))

    // MARK: Status

    /// Better-than-baseline delta text.
    static let vPositive = Color.vDynamic(light: (0x157A40, 1), dark: (0x7EE2A8, 1))
    /// Positive chip background.
    static let vPositiveTint = Color.vDynamic(light: (0xDCF6E8, 1), dark: (0x17382A, 1))
    /// Yellow recovery band, caution.
    static let vWarning = Color.vDynamic(light: (0xFFB21E, 1), dark: (0xFFC24D, 1))
    /// Text for caution deltas.
    static let vWarningInk = Color.vDynamic(light: (0x8A5E00, 1), dark: (0xFFD27A, 1))
    /// Caution chip / banner background.
    static let vWarningTint = Color.vDynamic(light: (0xFBF1D9, 1), dark: (0x3A2E12, 1))
    /// Red recovery band, errors, destructive.
    static let vDanger = Color.vDynamic(light: (0xE5484D, 1), dark: (0xFF6B6B, 1))
    /// Danger chip / banner background.
    static let vDangerTint = Color.vDynamic(light: (0xFCECEC, 1), dark: (0x3D1A1C, 1))

    // MARK: Sleep stages

    /// Hypnogram: awake.
    static let vStageAwake = Color.vDynamic(light: (0xFF9F6E, 1), dark: (0xFF9F6E, 1))
    /// Hypnogram: REM.
    static let vStageREM = Color.vDynamic(light: (0x7FD1F5, 1), dark: (0x7FD1F5, 1))
    /// Hypnogram: core.
    static let vStageCore = Color.vDynamic(light: (0x6E93FF, 1), dark: (0x6E93FF, 1))
    /// Hypnogram: deep.
    static let vStageDeep = Color.vDynamic(light: (0xB19BFF, 1), dark: (0xB19BFF, 1))

    // MARK: Sleep score bands (calendar)

    /// Sleep score 85+.
    static let vSleepGreat = Color.vDynamic(light: (0xB7B1FF, 1), dark: (0xB7B1FF, 1))
    /// Sleep score 70–84.
    static let vSleepGood = Color.vDynamic(light: (0x7C73F0, 1), dark: (0x7C73F0, 1))
    /// Sleep score 50–69.
    static let vSleepFair = Color.vDynamic(light: (0xFFB48F, 1), dark: (0xFFB48F, 1))
    /// Sleep score < 50.
    static let vSleepPoor = Color.vDynamic(light: (0xFF6B6B, 1), dark: (0xFF6B6B, 1))

    // MARK: Heart-rate zones

    /// Zone 1 · Warm-up.
    static let vZone1 = Color.vDynamic(light: (0x7DA7E8, 1), dark: (0x7DA7E8, 1))
    /// Zone 2 · Easy.
    static let vZone2 = Color.vDynamic(light: (0x2F9E8F, 1), dark: (0x3DBBAA, 1))
    /// Zone 3 · Aerobic.
    static let vZone3 = Color.vDynamic(light: (0xFFB21E, 1), dark: (0xFFC24D, 1))
    /// Zone 4 · Threshold.
    static let vZone4 = Color.vDynamic(light: (0xFF6A3D, 1), dark: (0xFF7F57, 1))
    /// Zone 5 · Maximum.
    static let vZone5 = Color.vDynamic(light: (0xE5484D, 1), dark: (0xFF6B6B, 1))

    // MARK: Night palette (Sleep tab is dark in both appearances)

    /// Sleep tab background.
    static let vNightBackground = Color.vDynamic(light: (0x0E1022, 1), dark: (0x0A0B18, 1))
    /// Sleep tab cards.
    static let vNightCard = Color.vDynamic(light: (0x171A33, 1), dark: (0x14162B, 1))
    /// Tiles inside sleep cards; header buttons.
    static let vNightCardRaised = Color.vDynamic(light: (0x1F2342, 1), dark: (0x1B1E3A, 1))
    /// Tracks and icon wells on the night palette.
    static let vNightFill = Color.vDynamic(light: (0x262A4D, 1), dark: (0x232644, 1))
    /// Card outline on the night palette.
    static let vNightSeparator = Color.vDynamic(light: (0xFFFFFF, 0.06), dark: (0xFFFFFF, 0.06))
    /// Primary text on the night palette.
    static let vNightInk = Color.vDynamic(light: (0xFFFFFF, 1), dark: (0xF4F2FA, 1))
    /// Secondary text on the night palette.
    static let vNightInkSecondary = Color.vDynamic(light: (0xA3A8C3, 1), dark: (0xA3A8C3, 1))
    /// Tertiary text on the night palette.
    static let vNightInkTertiary = Color.vDynamic(light: (0x5C6286, 1), dark: (0x5C6286, 1))
    /// Accent on the night palette.
    static let vNightAccent = Color.vDynamic(light: (0xB7B1FF, 1), dark: (0xB7B1FF, 1))
    /// Better-than-baseline on the night palette.
    static let vNightPositive = Color.vDynamic(light: (0x7EE2A8, 1), dark: (0x7EE2A8, 1))
    /// Worse-than-baseline on the night palette.
    static let vNightNegative = Color.vDynamic(light: (0xFFB48F, 1), dark: (0xFFB48F, 1))
}

// Declared on `ShapeStyle where Self == Color` so both `Color.vInk` and leading-dot `.vInk`
// (in `foregroundStyle`, `fill`, `stroke`, `background`) resolve to the same token.
extension ShapeStyle where Self == Color {

    // MARK: Surfaces

    /// Screen background.
    static var vBackground: Color { VColorStorage.vBackground }
    /// Card / grouped section background.
    static var vCard: Color { VColorStorage.vCard }
    /// Inset tile inside a card (stat tiles, info boxes).
    static var vCardRaised: Color { VColorStorage.vCardRaised }
    /// Progress-bar tracks, empty heat-map cells, neutral chips.
    static var vFill: Color { VColorStorage.vFill }
    /// Segmented control track.
    static var vControlTrack: Color { VColorStorage.vControlTrack }
    /// Selected segment thumb.
    static var vControlThumb: Color { VColorStorage.vControlThumb }
    /// List row separators.
    static var vSeparator: Color { VColorStorage.vSeparator }
    /// 1 pt outline drawn around cards.
    static var vHairline: Color { VColorStorage.vHairline }
    /// Soft card shadow colour.
    static var vShadow: Color { VColorStorage.vShadow }

    // MARK: Ink (text & icons)

    /// Primary text and icons.
    static var vInk: Color { VColorStorage.vInk }
    /// Strong secondary text: legends, axis labels, secondary buttons.
    static var vInkLabel: Color { VColorStorage.vInkLabel }
    /// Secondary text: dates, captions, units.
    static var vInkSecondary: Color { VColorStorage.vInkSecondary }
    /// Tertiary text, neutral sparklines, chevrons.
    static var vInkTertiary: Color { VColorStorage.vInkTertiary }
    /// Disabled controls, inactive dots.
    static var vInkDisabled: Color { VColorStorage.vInkDisabled }
    /// Inverted fill: selected day chip, primary button.
    static var vInverseFill: Color { VColorStorage.vInverseFill }
    /// Text/icons drawn on `vInverseFill`.
    static var vInkOnInverse: Color { VColorStorage.vInkOnInverse }
    /// Text/icons drawn on saturated brand colours.
    static var vInkOnAccent: Color { VColorStorage.vInkOnAccent }

    // MARK: Brand & navigation

    /// App accent: selected tab, links, focus.
    static var vAccent: Color { VColorStorage.vAccent }
    /// Selected tab pill background.
    static var vAccentTint: Color { VColorStorage.vAccentTint }

    // MARK: Scores

    /// Recovery ring / green band.
    static var vRecovery: Color { VColorStorage.vRecovery }
    /// Recovery ring track, positive chip background.
    static var vRecoveryTint: Color { VColorStorage.vRecoveryTint }
    /// Text on recovery tint; positive deltas.
    static var vRecoveryInk: Color { VColorStorage.vRecoveryInk }
    /// Sleep ring.
    static var vSleep: Color { VColorStorage.vSleep }
    /// Sleep ring track, sleep chip background.
    static var vSleepTint: Color { VColorStorage.vSleepTint }
    /// Text on sleep tint.
    static var vSleepInk: Color { VColorStorage.vSleepInk }
    /// Strain ring.
    static var vStrain: Color { VColorStorage.vStrain }
    /// Strain ring track, strain chip background.
    static var vStrainTint: Color { VColorStorage.vStrainTint }
    /// Text on strain tint.
    static var vStrainInk: Color { VColorStorage.vStrainInk }

    // MARK: Training

    /// Running: highlighted bars, routes, run chips.
    static var vRun: Color { VColorStorage.vRun }
    /// Running: non-highlighted bars.
    static var vRunSoft: Color { VColorStorage.vRunSoft }
    /// Running chip background.
    static var vRunTint: Color { VColorStorage.vRunTint }
    /// Lifting: highlighted bars and chips.
    static var vLift: Color { VColorStorage.vLift }
    /// Lifting: non-highlighted bars.
    static var vLiftSoft: Color { VColorStorage.vLiftSoft }
    /// Lifting chip background.
    static var vLiftTint: Color { VColorStorage.vLiftTint }

    // MARK: Status

    /// Better-than-baseline delta text.
    static var vPositive: Color { VColorStorage.vPositive }
    /// Positive chip background.
    static var vPositiveTint: Color { VColorStorage.vPositiveTint }
    /// Yellow recovery band, caution.
    static var vWarning: Color { VColorStorage.vWarning }
    /// Text for caution deltas.
    static var vWarningInk: Color { VColorStorage.vWarningInk }
    /// Caution chip / banner background.
    static var vWarningTint: Color { VColorStorage.vWarningTint }
    /// Red recovery band, errors, destructive.
    static var vDanger: Color { VColorStorage.vDanger }
    /// Danger chip / banner background.
    static var vDangerTint: Color { VColorStorage.vDangerTint }

    // MARK: Sleep stages

    /// Hypnogram: awake.
    static var vStageAwake: Color { VColorStorage.vStageAwake }
    /// Hypnogram: REM.
    static var vStageREM: Color { VColorStorage.vStageREM }
    /// Hypnogram: core.
    static var vStageCore: Color { VColorStorage.vStageCore }
    /// Hypnogram: deep.
    static var vStageDeep: Color { VColorStorage.vStageDeep }

    // MARK: Sleep score bands (calendar)

    /// Sleep score 85+.
    static var vSleepGreat: Color { VColorStorage.vSleepGreat }
    /// Sleep score 70–84.
    static var vSleepGood: Color { VColorStorage.vSleepGood }
    /// Sleep score 50–69.
    static var vSleepFair: Color { VColorStorage.vSleepFair }
    /// Sleep score < 50.
    static var vSleepPoor: Color { VColorStorage.vSleepPoor }

    // MARK: Heart-rate zones

    /// Zone 1 · Warm-up.
    static var vZone1: Color { VColorStorage.vZone1 }
    /// Zone 2 · Easy.
    static var vZone2: Color { VColorStorage.vZone2 }
    /// Zone 3 · Aerobic.
    static var vZone3: Color { VColorStorage.vZone3 }
    /// Zone 4 · Threshold.
    static var vZone4: Color { VColorStorage.vZone4 }
    /// Zone 5 · Maximum.
    static var vZone5: Color { VColorStorage.vZone5 }

    // MARK: Night palette (Sleep tab is dark in both appearances)

    /// Sleep tab background.
    static var vNightBackground: Color { VColorStorage.vNightBackground }
    /// Sleep tab cards.
    static var vNightCard: Color { VColorStorage.vNightCard }
    /// Tiles inside sleep cards; header buttons.
    static var vNightCardRaised: Color { VColorStorage.vNightCardRaised }
    /// Tracks and icon wells on the night palette.
    static var vNightFill: Color { VColorStorage.vNightFill }
    /// Card outline on the night palette.
    static var vNightSeparator: Color { VColorStorage.vNightSeparator }
    /// Primary text on the night palette.
    static var vNightInk: Color { VColorStorage.vNightInk }
    /// Secondary text on the night palette.
    static var vNightInkSecondary: Color { VColorStorage.vNightInkSecondary }
    /// Tertiary text on the night palette.
    static var vNightInkTertiary: Color { VColorStorage.vNightInkTertiary }
    /// Accent on the night palette.
    static var vNightAccent: Color { VColorStorage.vNightAccent }
    /// Better-than-baseline on the night palette.
    static var vNightPositive: Color { VColorStorage.vNightPositive }
    /// Worse-than-baseline on the night palette.
    static var vNightNegative: Color { VColorStorage.vNightNegative }
}

extension Color {
    /// Builds a light/dark dynamic colour from `(hex, alpha)` pairs.
    static func vDynamic(light: (UInt32, Double), dark: (UInt32, Double)) -> Color {
        let lightColor = UIColor(vHex: light.0, alpha: light.1)
        let darkColor = UIColor(vHex: dark.0, alpha: dark.1)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }

    /// Colour for a recovery band (green / yellow / red).
    static func vRecoveryBand(_ band: RecoveryBand) -> Color {
        switch band {
        case .green: .vRecovery
        case .yellow: .vWarning
        case .red: .vDanger
        }
    }

    /// Colour for a sleep-score band (calendar legend).
    static func vSleepScoreBand(_ band: SleepScoreBand) -> Color {
        switch band {
        case .great: .vSleepGreat
        case .good: .vSleepGood
        case .fair: .vSleepFair
        case .poor: .vSleepPoor
        }
    }

    /// Colour for heart-rate zone 1...5 (out-of-range values clamp).
    static func vZone(_ zone: Int) -> Color {
        switch zone {
        case ...1: .vZone1
        case 2: .vZone2
        case 3: .vZone3
        case 4: .vZone4
        default: .vZone5
        }
    }
}

extension UIColor {
    /// `0xRRGGBB` initialiser used by the token table.
    convenience init(vHex hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
