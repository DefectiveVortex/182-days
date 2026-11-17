import CoreText
import SwiftUI

/// The two bundled families (both SIL OFL 1.1, licences in Resources/Fonts):
/// Barlow Condensed for numbers and headings, Inter for text.
///
/// Fonts are registered at runtime from the bundle the first time a style is used, so no
/// Info.plist `UIAppFonts` entry is needed and any target that bundles Resources/Fonts
/// (app or widget extension) gets them.
enum Typeface {
    enum Barlow: String, CaseIterable {
        case medium = "BarlowCondensed-Medium"
        case semibold = "BarlowCondensed-SemiBold"
        case bold = "BarlowCondensed-Bold"
    }

    enum Inter: String, CaseIterable {
        case regular = "Inter-Regular"
        case medium = "Inter-Medium"
        case semibold = "Inter-SemiBold"
    }

    /// Registers every bundled TTF once per process. Safe to call from any thread.
    static func registerIfNeeded() { _ = registration }

    private static let registration: Void = {
        let files = Barlow.allCases.map(\.rawValue) + Inter.allCases.map(\.rawValue)
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            // Already-registered (e.g. a second target in the same process) is not an error worth surfacing.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// The type scale. Every style scales with Dynamic Type relative to a text style, so the
/// layout grows with the user's setting; screens cap the very largest sizes where a
/// numeral would no longer fit.
enum TextStyle {
    case dayNumber      // "DAY 23"           Barlow 700 44
    case dayTotal       // "/ 182"            Barlow 500 20
    case hero           // push-up count      Barlow 700 104
    case ghostLabel     // "ghost 31"         Barlow 500 22
    case count          // sit-up count       Barlow 700 44
    case banner         // must-day headline  Barlow 700 20
    case blockTitle     // "Study block"      Barlow 600 26
    case button         // "+10"              Barlow 700 22
    case label          // "PUSH-UPS"         Inter 600 12, tracked 1.6
    case note           // "Past your ghost"  Inter 600 13
    case bannerBody     // must-day sub-line  Inter 500 13
    case caption        // date, status       Inter 400 13
    case body           // posture line       Inter 400 14
    case bodyMedium     // "Log a set"        Inter 500 14
    case tab            // tab bar            Inter 600 11
    case headline       // "23 IN. 159 TO GO." Barlow 700 40
    case stat           // "23 DAYS"          Barlow 700 34
    case small          // grid dates, legend Inter 400 11

    var font: Font {
        Typeface.registerIfNeeded()
        switch self {
        case .dayNumber: return .custom(Typeface.Barlow.bold.rawValue, size: 44, relativeTo: .largeTitle)
        case .dayTotal: return .custom(Typeface.Barlow.medium.rawValue, size: 20, relativeTo: .title3)
        case .hero: return .custom(Typeface.Barlow.bold.rawValue, size: 104, relativeTo: .largeTitle)
        case .ghostLabel: return .custom(Typeface.Barlow.medium.rawValue, size: 22, relativeTo: .title2)
        case .count: return .custom(Typeface.Barlow.bold.rawValue, size: 44, relativeTo: .largeTitle)
        case .banner: return .custom(Typeface.Barlow.bold.rawValue, size: 20, relativeTo: .title3)
        case .blockTitle: return .custom(Typeface.Barlow.semibold.rawValue, size: 26, relativeTo: .title)
        case .button: return .custom(Typeface.Barlow.bold.rawValue, size: 22, relativeTo: .title2)
        case .label: return .custom(Typeface.Inter.semibold.rawValue, size: 12, relativeTo: .caption)
        case .note: return .custom(Typeface.Inter.semibold.rawValue, size: 13, relativeTo: .footnote)
        case .bannerBody: return .custom(Typeface.Inter.medium.rawValue, size: 13, relativeTo: .footnote)
        case .caption: return .custom(Typeface.Inter.regular.rawValue, size: 13, relativeTo: .footnote)
        case .body: return .custom(Typeface.Inter.regular.rawValue, size: 14, relativeTo: .subheadline)
        case .bodyMedium: return .custom(Typeface.Inter.medium.rawValue, size: 14, relativeTo: .subheadline)
        case .tab: return .custom(Typeface.Inter.semibold.rawValue, size: 11, relativeTo: .caption2)
        case .headline: return .custom(Typeface.Barlow.bold.rawValue, size: 40, relativeTo: .largeTitle)
        case .stat: return .custom(Typeface.Barlow.bold.rawValue, size: 34, relativeTo: .title)
        case .small: return .custom(Typeface.Inter.regular.rawValue, size: 11, relativeTo: .caption2)
        }
    }

    /// Letter spacing in points (CSS letter-spacing).
    var tracking: CGFloat {
        switch self {
        case .label: return 1.6
        case .banner: return 0.4
        default: return 0
        }
    }
}

extension View {
    /// Applies a type-scale style: font, tracking, and monospaced digits for the numeral styles
    /// so counts don't jitter as they change.
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .monospacedDigit()
    }
}

extension Text {
    /// A section label: uppercase Inter 600 12, tracked, muted.
    @MainActor static func label(_ string: String) -> some View {
        Text(string.uppercased())
            .textStyle(.label)
            .foregroundStyle(Palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}
