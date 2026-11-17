import Foundation

/// `-demo <scenario>` (CI screenshots, .github/screenshots.txt). Owner: Days 2.
///
/// Scenarios:
///   normal  the normal day from the design (18 push-ups against a ghost of 31)
///   must    yesterday was a slip, nothing logged yet
///   ahead   past the ghost on both counts
///
/// Until Core's rules engine lands, Today shows these as fixed screen models (no rules run, nothing
/// written). Once it does, `seed` writes the matching entries into the in-memory store instead and
/// the screens read them through Core like the real app.
@MainActor
enum DemoData {
    static func seed(_ store: LogStore, scenario: String) {}

    /// The scenario named after `-demo`, or nil when not in demo mode.
    static var scenario: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo") else { return nil }
        return i + 1 < args.count ? args[i + 1] : "normal"
    }

    static func todayModel(for scenario: String) -> TodayModel {
        switch scenario {
        case "must": .previewMust
        case "ahead": .previewAhead
        default: .preview
        }
    }
}
