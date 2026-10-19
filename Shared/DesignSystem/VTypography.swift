import SwiftUI

// MARK: - Typography roles
//
// Owner: design-system agent. Sizes/weights measured from Design/*.dc.html.
// Headings use "Bricolage Grotesque", body uses "Figtree" (both SIL OFL, bundled from
// Shared/Resources/Fonts and registered via UIAppFonts). If the font files are missing,
// `Font.custom` silently falls back to the system font, so builds never fail.
//
// Feature code uses `Text(...).vTextStyle(.headline)` (font + tracking + case) or `.font(.vBody)`.
// Every role scales with Dynamic Type via `relativeTo:`.

/// Font family names as registered by the font files.
enum VFontFamily: Sendable {
    /// Display / headings ("Bricolage Grotesque").
    case heading
    /// Body / UI ("Figtree").
    case body

    /// PostScript name of the named variable-font instance for a weight.
    ///
    /// Variable fonts loaded with `Font.custom(family, …).weight(…)` frequently ignore the weight, so
    /// we address the font's *named instances* (500/600/700/800) directly. Both families register
    /// them from the `*-Variable.ttf` files (`UIAppFonts`).
    func postScriptName(for weight: Font.Weight) -> String {
        let suffix: String
        switch weight {
        case .black, .heavy: suffix = "ExtraBold"
        case .bold: suffix = "Bold"
        case .semibold: suffix = "SemiBold"
        case .medium: suffix = "Medium"
        case .regular, .light, .thin, .ultraLight: suffix = "Regular"
        default: suffix = "Bold"
        }
        switch self {
        case .heading: return "BricolageGrotesque-96ptExtraBold_\(suffix)"
        case .body: return "Figtree-\(suffix)"
        }
    }
}

/// Semantic text styles.
enum VTextStyle: CaseIterable, Sendable {
    /// 34 / Bricolage Bold, −0.02em — tab screen titles ("Today").
    case largeTitle
    /// 26 / Bricolage Bold — detail screen titles, hero numbers in cards.
    case title
    /// 21 / Bricolage Bold — secondary titles.
    case title2
    /// 19 / Bricolage Bold — section and card titles ("Vitals").
    case headline
    /// 48 / Bricolage Bold — hero score in detail screens (e.g. Recovery 78%).
    case display
    /// 30 / Bricolage Bold — score inside a ring.
    case score
    /// 20 / Figtree ExtraBold — stat values ("11,284").
    case statValue
    /// 17 / Figtree ExtraBold — small stat values, list primary numbers.
    case statValueSmall
    /// 16 / Figtree SemiBold — body copy.
    case body
    /// 15 / Figtree Bold — row titles, emphasized body.
    case bodyStrong
    /// 15 / Figtree SemiBold — secondary body, subtitles.
    case callout
    /// 14 / Figtree SemiBold — supporting text.
    case subheadline
    /// 13 / Figtree SemiBold — footnotes, card subtitles ("vs. 30-day baseline").
    case footnote
    /// 12 / Figtree SemiBold — captions, chart legends.
    case caption
    /// 11 / Figtree SemiBold — tab bar labels, axis ticks.
    case caption2
    /// 11 / Figtree Bold, uppercase, +0.04em — day-strip weekday labels, overlines.
    case overline

    var size: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 26
        case .title2: 21
        case .headline: 19
        case .display: 48
        case .score: 30
        case .statValue: 20
        case .statValueSmall: 17
        case .body: 16
        case .bodyStrong, .callout: 15
        case .subheadline: 14
        case .footnote: 13
        case .caption: 12
        case .caption2, .overline: 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .largeTitle, .title, .title2, .headline, .display, .score, .bodyStrong, .overline: .bold
        case .statValue, .statValueSmall: .heavy
        case .body, .callout, .subheadline, .footnote, .caption, .caption2: .semibold
        }
    }

    var family: VFontFamily {
        switch self {
        case .largeTitle, .title, .title2, .headline, .display, .score: VFontFamily.heading
        default: VFontFamily.body
        }
    }

    /// Dynamic Type anchor.
    var relativeTo: Font.TextStyle {
        switch self {
        case .largeTitle, .display: .largeTitle
        case .title, .score: .title
        case .title2: .title2
        case .headline, .statValue: .title3
        case .statValueSmall, .bodyStrong: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2, .overline: .caption2
        }
    }

    /// Letter spacing in points (design em × size).
    var tracking: CGFloat {
        switch self {
        case .largeTitle, .display: -0.02 * size
        case .title, .score: -0.01 * size
        case .overline: 0.04 * size
        default: 0
        }
    }

    var isUppercased: Bool { self == .overline }

    var font: Font {
        Font.vCustom(family, size: size, weight: weight, relativeTo: relativeTo)
    }
}

extension Font {
    /// Free-form brand font for sizes the roles don't cover (e.g. a 29 pt ring number).
    /// Scales with Dynamic Type relative to `textStyle`; digits are tabular.
    static func vCustom(_ family: VFontFamily, size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom(family.postScriptName(for: weight), size: size, relativeTo: textStyle).monospacedDigit()
    }

    static var vLargeTitle: Font { VTextStyle.largeTitle.font }
    static var vTitle: Font { VTextStyle.title.font }
    static var vTitle2: Font { VTextStyle.title2.font }
    static var vHeadline: Font { VTextStyle.headline.font }
    static var vDisplay: Font { VTextStyle.display.font }
    static var vScore: Font { VTextStyle.score.font }
    static var vStatValue: Font { VTextStyle.statValue.font }
    static var vStatValueSmall: Font { VTextStyle.statValueSmall.font }
    static var vBody: Font { VTextStyle.body.font }
    static var vBodyStrong: Font { VTextStyle.bodyStrong.font }
    static var vCallout: Font { VTextStyle.callout.font }
    static var vSubheadline: Font { VTextStyle.subheadline.font }
    static var vFootnote: Font { VTextStyle.footnote.font }
    static var vCaption: Font { VTextStyle.caption.font }
    static var vCaption2: Font { VTextStyle.caption2.font }
    static var vOverline: Font { VTextStyle.overline.font }
}

extension View {
    /// Applies a Vigil text style: font, tracking and text case.
    func vTextStyle(_ style: VTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}
