import Foundation

/// One practice on one day, against its ghost.
public struct PracticeDay: Sendable, Equatable, Identifiable {
    public var id: PracticeID { practice.id }
    public let practice: Practice
    public let day: DayKey
    /// The day's value (see `Practice.value`).
    public let value: Int
    /// The ghost: the previous day's value, or the starting number on day 1.
    public let ghost: Int
    /// That day's entries, oldest first. On today the last one is what undo removes.
    public let entries: [Entry]

    /// Marks drawn over the ghost (`min(value, ghost)`), and marks past it (orange).
    public var overGhost: Int { min(value, ghost) }
    public var pastGhost: Int { max(0, value - ghost) }
    public var beatsGhost: Bool { value > ghost }
    /// Checks answered either way (posture: upright + slouching).
    public var answered: Int { entries.count }
    public var target: Int? { practice.target }
}

/// Everything the Today screen and the widgets show, computed from the log. Pure.
public struct TodayState: Sendable, Equatable {
    public let now: Date
    public let ledger: Ledger
    /// In `DaysSettings.practices` order.
    public let practices: [PracticeDay]
    /// Today's evening line, if written.
    public let journalLine: String?

    public var day: DayKey { ledger.today }
    public var dayNumber: Int { ledger.dayNumber }
    public var attemptNumber: Int { ledger.current.number }
    public var isMustDay: Bool { ledger.isMustDay }
    public var kept: Bool { ledger.todayKept }
    /// Today beat yesterday in at least one practice.
    public var beatYesterday: Bool { practices.contains { $0.practice.kind != .rating && $0.beatsGhost } }

    public subscript(id: PracticeID) -> PracticeDay? { practices.first { $0.id == id } }
}

public enum DayBook {
    /// - Parameters:
    ///   - entries: the whole log (only today, yesterday and kept-day membership are read).
    ///   - journal: lines by day.
    public static func today(
        now: Date, clock: DayClock, settings: DaysSettings, entries: [Entry], journal: [DayKey: String]
    ) -> TodayState {
        let latest = entries.map(\.day).max()
        let today = effectiveToday(now: now, clock: clock, latestLogged: latest)
        let firstDay = settings.firstDay ?? today
        let ledger = Ledger(firstDay: firstDay, today: today,
                            keptDays: entries.keptDays(practices: settings.practices))
        let byDay = entries.byDay()
        return TodayState(
            now: now, ledger: ledger,
            practices: settings.practices.map {
                practiceDay($0, on: ledger.today, byDay: byDay, settings: settings)
            },
            journalLine: journal[ledger.today])
    }

    /// One practice on any day, with its ghost.
    public static func practiceDay(
        _ practice: Practice, on day: DayKey, byDay: [DayKey: [Entry]], settings: DaysSettings
    ) -> PracticeDay {
        let mine = (byDay[day] ?? []).filter { $0.practice == practice.id }.sorted { $0.at < $1.at }
        let ghost: Int
        if let first = settings.firstDay, day <= first {
            ghost = settings.startingNumbers[practice.id] ?? 0
        } else {
            ghost = practice.value(of: byDay[day.previous] ?? [])
        }
        return PracticeDay(practice: practice, day: day, value: practice.value(of: mine), ghost: ghost, entries: mine)
    }

    /// Today never moves backwards: after flying west, the day already logged stays "today"
    /// until the local clock catches up, so a closed day can't be reopened.
    public static func effectiveToday(now: Date, clock: DayClock, latestLogged: DayKey?) -> DayKey {
        let local = clock.day(containing: now)
        guard let latestLogged else { return local }
        return max(local, latestLogged)
    }
}
