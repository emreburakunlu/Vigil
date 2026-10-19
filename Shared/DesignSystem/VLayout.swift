import SwiftUI

// MARK: - Spacing, radii, sizes
//
// Owner: design-system agent. Values measured from Design/*.dc.html (390 pt wide boards).
// Feature code must use these instead of magic numbers for padding, spacing and corner radii.

/// Spacing scale (points).
enum VSpacing {
    /// 2
    static let xxxs: CGFloat = 2
    /// 4
    static let xxs: CGFloat = 4
    /// 6
    static let xs: CGFloat = 6
    /// 8
    static let s: CGFloat = 8
    /// 10
    static let m: CGFloat = 10
    /// 12
    static let l: CGFloat = 12
    /// 14
    static let xl: CGFloat = 14
    /// 16
    static let xxl: CGFloat = 16
    /// 20
    static let xxxl: CGFloat = 20
    /// 24
    static let huge: CGFloat = 24

    /// Horizontal margin between screen edge and cards (16).
    static let screenGutter: CGFloat = 16
    /// Horizontal margin for screen headers/titles (20).
    static let headerGutter: CGFloat = 20
    /// Inner padding of a standard card (18).
    static let cardPadding: CGFloat = 18
    /// Inner padding of a compact card / tile (14).
    static let cardPaddingCompact: CGFloat = 14
    /// Vertical gap between stacked cards (16).
    static let cardGap: CGFloat = 16
}

/// Corner radii (points). Use with `.rect(cornerRadius:)` / `RoundedRectangle(cornerRadius:style: .continuous)`.
enum VRadius {
    /// Small bars & legend swatches (4).
    static let bar: CGFloat = 4
    /// Chips, small tiles (12).
    static let chip: CGFloat = 12
    /// Inset tiles, segmented control (16).
    static let tile: CGFloat = 16
    /// Day chips (18).
    static let dayChip: CGFloat = 18
    /// Round 44 pt icon buttons (22).
    static let iconButton: CGFloat = 22
    /// Standard card (24).
    static let card: CGFloat = 24
    /// Hero card (26).
    static let cardLarge: CGFloat = 26
    /// Full-width primary button, 56 pt tall (28).
    static let button: CGFloat = 28
}

/// Fixed component sizes (points).
enum VSize {
    /// Minimum hit target (44).
    static let minTapTarget: CGFloat = 44
    /// Primary button height (56).
    static let primaryButtonHeight: CGFloat = 56
    /// Score ring diameter on Today (98).
    static let scoreRing: CGFloat = 98
    /// Score ring stroke width (≈ 9/100 of the ring).
    static let scoreRingStroke: CGFloat = 9
    /// Card hairline width.
    static let hairline: CGFloat = 1
}
