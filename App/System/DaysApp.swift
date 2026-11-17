import SwiftUI
@preconcurrency import UserNotifications
import DaysCore

/// App entry. Owner: Days 1. Screens hang off `RootView` (Days 2), which reads
/// `@Environment(LogStore.self)`.
///
/// Launch arguments (CI screenshots): `-demo <scenario>` seeds an in-memory store through
/// `DemoData.seed` (Days 2) and never touches notifications or widgets; `-screen <name>` is
/// for RootView to open a given screen.
@main
struct DaysApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: LogStore

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demo") {
            let scenario = i + 1 < args.count ? args[i + 1] : "normal"
            let store = try! LogStore.inMemory()
            DemoData.seed(store, scenario: scenario)
            LogStore.install(store)
            _store = State(initialValue: store)
        } else {
            _store = State(initialValue: LogStore.current)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

/// Notification actions arrive here, also when iOS launches the app in the background to handle one.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let category = response.notification.request.content.categoryIdentifier
        if action == UNNotificationDefaultActionIdentifier, category == NotificationCategory.photo.rawValue {
            await MainActor.run { AppRoute.shared.pending = "camera" }
        }
        let store = await MainActor.run {
            let store = LogStore.current
            store.refresh()
            NotificationScheduler.handle(action: action, text: text, store: store)
            return store
        }
        await store.settle()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
