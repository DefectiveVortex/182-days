import Observation

/// Where a notification tap asks the app to go. Owner: Days 1 (set), Days 2 (consumes).
/// RootView switches tab on it; the screen that handles it sets `pending = nil`.
/// Values: "camera" (the Sunday posture-photo notification).
@MainActor @Observable
final class AppRoute {
    static let shared = AppRoute()
    var pending: String?
}
