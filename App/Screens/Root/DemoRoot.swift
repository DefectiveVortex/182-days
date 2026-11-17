import SwiftUI

/// What the app shows when launched with `-demo`: seeded sample data, no store, nothing written.
/// CI screenshots launch it with one of these state arguments after `-demo`:
///   (none) or `-demoState normal`  the normal day from the design
///   `-demoState must`              a must day, nothing logged
///   `-demoState ahead`             past the ghost on both counts
struct DemoRoot: View {
    @State private var store: PreviewTodayStore

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        _store = State(initialValue: PreviewTodayStore(Self.model(for: arguments)))
    }

    var body: some View {
        RootView { TodayView(model: store.model, actions: store.actions) }
    }

    /// True when the process was launched with `-demo`.
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func model(for arguments: [String]) -> TodayModel {
        let state = arguments.firstIndex(of: "-demoState").flatMap { i in
            arguments.indices.contains(i + 1) ? arguments[i + 1] : nil
        }
        switch state {
        case "must": return .previewMust
        case "ahead": return .previewAhead
        default: return .preview
        }
    }
}
