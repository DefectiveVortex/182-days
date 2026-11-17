import SwiftUI
import DaysCore

/// App entry. Owner: Days 1. Screens hang off `RootView` (Days 2).
@main
struct DaysApp: App {
    @State private var store: LogStore

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demo") {
            let scenario = i + 1 < args.count ? args[i + 1] : "normal"
            let store = try! LogStore.inMemory()
            DemoData.seed(store, scenario: scenario)
            _store = State(initialValue: store)
        } else {
            _store = State(initialValue: try! LogStore.onDisk())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
