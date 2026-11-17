import SwiftUI

/// Colour tokens for direction A "Tally". Dark only; one accent.
/// Values come from design/AC-Today.dc.html. Nothing else in the app should name a colour.
enum Palette {
    /// Page background, #0D0D0C.
    static let background = Color(hex: 0x0D0D0C)
    /// Primary text and today's marks, #F2F0EA.
    static let text = Color(hex: 0xF2F0EA)
    /// Secondary text, labels, inactive tabs, #9A978E.
    static let muted = Color(hex: 0x9A978E)
    /// Hairline rules between sections, #2A2A27.
    static let rule = Color(hex: 0x2A2A27)
    /// Outline of secondary buttons, #3A3A36.
    static let outline = Color(hex: 0x3A3A36)
    /// Empty track behind a bar, #1A1A18.
    static let track = Color(hex: 0x1A1A18)
    /// Yesterday: dashed, dim, #4A4A45.
    static let ghost = Color(hex: 0x4A4A45)
    /// The one accent: past the ghost, must days, slouching, #FF5B1F.
    static let accent = Color(hex: 0xFF5B1F)
    /// Text on an accent or cream fill.
    static let onFill = background
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Spacing and size tokens (points). The design is drawn at 390 pt wide.
enum Metrics {
    /// Side gutter of every screen.
    static let gutter: CGFloat = 20
    /// Gap between the sections of a screen.
    static let sectionGap: CGFloat = 16
    /// Space under a section's hairline rule.
    static let ruleGap: CGFloat = 14
    /// Gap between rows inside a section.
    static let rowGap: CGFloat = 10
    /// Height of a primary/secondary button. Above the 44 pt minimum.
    static let buttonHeight: CGFloat = 48
    /// Minimum hit target.
    static let minTarget: CGFloat = 44
    /// Hairline width.
    static let hairline: CGFloat = 1
}
