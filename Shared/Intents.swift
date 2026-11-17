import AppIntents
import WidgetKit
import DaysCore

/// Log reps (or seconds) of a practice to today. Used by interactive widgets and Shortcuts.
public struct LogPracticeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log reps"
    public static let openAppWhenRun = false

    @Parameter(title: "Practice") public var practice: String
    @Parameter(title: "Amount", default: 10) public var amount: Int

    public init() {}

    public init(_ practice: PracticeID, _ amount: Int) {
        self.practice = practice.rawValue
        self.amount = amount
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        LogStore.current.refresh()
        LogStore.current.log(PracticeID(practice), amount)
        return .result()
    }
}

/// Answer a posture check.
public struct AnswerPostureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Posture check"
    public static let openAppWhenRun = false

    @Parameter(title: "Upright") public var upright: Bool

    public init() {}

    public init(upright: Bool) { self.upright = upright }

    @MainActor
    public func perform() async throws -> some IntentResult {
        LogStore.current.refresh()
        LogStore.current.answerPosture(upright: upright)
        return .result()
    }
}

/// Undo today's last entry of a practice.
public struct UndoLastIntent: AppIntent {
    public static let title: LocalizedStringResource = "Undo last"
    public static let openAppWhenRun = false

    @Parameter(title: "Practice") public var practice: String

    public init() {}

    public init(_ practice: PracticeID) { self.practice = practice.rawValue }

    @MainActor
    public func perform() async throws -> some IntentResult {
        LogStore.current.refresh()
        LogStore.current.undoLast(PracticeID(practice))
        return .result()
    }
}
