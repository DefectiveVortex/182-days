import Foundation

/// Everything the Today screen shows, as plain values. The screen never computes rules itself:
/// an adapter fills this from Core/LogStore, and previews and `-demo` fill it from `TodayModel.preview`.
struct TodayModel: Equatable, Sendable {
    enum DayKind: Equatable, Sendable {
        case normal
        /// Yesterday was a slip; an empty today ends the attempt.
        case must
    }

    struct Count: Equatable, Sendable {
        var today: Int
        /// Yesterday's total: the ghost. 0 when yesterday was empty or this is the first day.
        var ghost: Int
        /// Today's sets, newest last, for undo.
        var sets: [Int] = []
    }

    /// The attempt that two slips in a row ended yesterday; today is day 1 of the next.
    struct EndedAttempt: Equatable, Sendable {
        var number: Int
        var length: Int
    }

    struct Block: Equatable, Sendable {
        var title: String
        var until: Date
        var next: String?
    }

    var day: Int
    /// The count the day number is read against ("/ 182"); Core moves it on after 182.
    var span: Int = 182
    var date: Date
    var kind: DayKind = .normal
    var attempt: Int = 1
    var slipsThisAttempt: Int = 0
    var lastSlipDaysAgo: Int?
    var endedAttempt: EndedAttempt?

    var pushUps: Count
    var sitUps: Count
    /// The count that fills the sit-up bar (≈ target × 1.1).
    var sitUpScale: Int = 110

    /// Today's posture checks in order; nil = not answered yet.
    var posture: [PostureAnswer?]
    var postureYesterdayUpright: Int?

    var block: Block?

    /// Today asks for a letter (day 1, 30, 60… of the half-year) and none is written: that day, and when it opens.
    var letterDue: Int?
    var letterOpens: Date?
    /// No posture photo yet this week (Sunday to Saturday); the week number it would be.
    var photoDue: Bool = false
    var photoWeek: Int = 1
}

/// The Today screen's actions. Closures so previews, `-demo` and the real store plug in the same way.
struct TodayActions {
    var addPushUps: @MainActor (Int) -> Void = { _ in }
    var addSitUps: @MainActor (Int) -> Void = { _ in }
    var undoPushUps: @MainActor () -> Void = {}
    var undoSitUps: @MainActor () -> Void = {}
    var answerPosture: @MainActor (PostureAnswer) -> Void = { _ in }
    var writeLetter: @MainActor () -> Void = {}
    var takePhoto: @MainActor () -> Void = {}
}

// MARK: - Copy

extension TodayModel {
    var statusLine: String {
        var parts: [String] = []
        if attempt > 1 { parts.append("Attempt \(attempt)") }
        switch (slipsThisAttempt, lastSlipDaysAgo) {
        case (0, _), (_, nil):
            parts.append("Run intact · no slips")
        case let (n, days?):
            let when = days == 1 ? "yesterday" : "\(days) days ago"
            parts.append(n == 1 ? "Run intact · 1 slip, \(when)" : "Run intact · \(n) slips, last \(when)")
        }
        return parts.joined(separator: " · ")
    }

    var postureLine: (main: String, yesterday: String?) {
        let answered = posture.compactMap { $0 }
        let upright = answered.filter { $0 == .upright }.count
        let main = answered.isEmpty ? "No checks yet" : "\(upright) of \(answered.count) upright"
        return (main, postureYesterdayUpright.map { "\($0) yesterday" })
    }

    var nextPostureIndex: Int? { posture.firstIndex(where: { $0 == nil }) }
}

extension TodayModel.Count {
    /// The line beside the label: the only comparison on Today is yesterday.
    func note(kind: TodayModel.DayKind) -> (text: String, ahead: Bool) {
        if kind == .must { return (today > 0 ? "Run saved" : "Anything counts", today > 0) }
        if ghost == 0 { return (today > 0 ? "Tomorrow's ghost: \(today)" : "No ghost yet", false) }
        if today > ghost { return ("Past your ghost by \(today - ghost)", true) }
        return ("\(ghost - today + 1) to pass your ghost", false)
    }

    var ghostLabel: String { ghost > 0 ? "ghost \(ghost)" : "no ghost today" }
}

// MARK: - Preview data

extension TodayModel {
    /// The normal day from the design: day 23, 18 push-ups against a ghost of 31.
    static let preview = TodayModel(
        day: 23,
        date: previewDate,
        kind: .normal,
        slipsThisAttempt: 1,
        lastSlipDaysAgo: 14,
        pushUps: Count(today: 18, ghost: 31, sets: [10, 5, 3]),
        sitUps: Count(today: 40, ghost: 58, sets: [20, 20]),
        posture: [.upright, .upright, .slouching, .upright, .upright, nil],
        postureYesterdayUpright: 3,
        block: Block(title: "Study block", until: previewDate.addingTimeInterval(3 * 3600), next: "Walk")
    )

    /// A must day: yesterday was empty, nothing logged yet.
    static let previewMust = TodayModel(
        day: 23,
        date: previewDate,
        kind: .must,
        slipsThisAttempt: 2,
        lastSlipDaysAgo: 1,
        pushUps: Count(today: 0, ghost: 0),
        sitUps: Count(today: 0, ghost: 0),
        posture: [nil, nil, nil, nil, nil],
        postureYesterdayUpright: nil,
        block: Block(title: "Study block", until: previewDate.addingTimeInterval(3 * 3600), next: "Walk")
    )

    /// Past the ghost on both counts.
    static let previewAhead = TodayModel(
        day: 41,
        date: previewDate,
        pushUps: Count(today: 36, ghost: 31, sets: [10, 10, 10, 6]),
        sitUps: Count(today: 70, ghost: 58, sets: [30, 40]),
        posture: [.upright, .upright, .upright, .upright, .upright],
        postureYesterdayUpright: 4,
        block: nil
    )

    /// Tue 17 Nov 2026, 12:00 local.
    private static let previewDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17; c.hour = 12
        return Calendar.current.date(from: c) ?? .now
    }()
}
