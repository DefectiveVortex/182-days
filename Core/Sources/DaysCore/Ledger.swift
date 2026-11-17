import Foundation

/// What a day came to.
public enum DayOutcome: String, Codable, Sendable {
    /// Something for himself was logged.
    case kept
    /// Closed empty. The next day is a must day.
    case slipped
    /// Today, still open.
    case open
    /// Before the first day, or in the future.
    case none
}

/// One run at the 182 days. Ends on the second slip in a row.
public struct Attempt: Hashable, Codable, Sendable {
    /// 1-based.
    public var number: Int
    public var start: DayKey
    /// The second slip day, for a failed attempt; nil while it runs.
    public var end: DayKey?
    /// Days from `start` through `end` (failed) or through today (running).
    public var length: Int
    public var keptDays: Int
    public var failed: Bool { end != nil }
}

/// The rules engine. Pure: the same kept days and today always give the same ledger.
///
/// - A day counts if anything for himself was logged (see `Practice.keepsDay`).
/// - A closed empty day is a slip; the next day is a must day.
/// - Two slips in a row end the attempt. Attempt N+1 starts at day 1 the next day; history stays.
/// - Day count runs on past 182; the half-year view restarts every 182 days.
public struct Ledger: Sendable, Equatable {
    public static let halfYear = 182

    public let firstDay: DayKey
    public let today: DayKey
    public let keptDays: Set<DayKey>
    /// Oldest first. The last one is the current attempt.
    public let attempts: [Attempt]
    /// Consecutive slips immediately before today, within the current attempt (0 or 1).
    public let slipsBeforeToday: Int

    /// - Parameters:
    ///   - firstDay: the day onboarding finished; day 1 of attempt 1.
    ///   - today: the current logical day. Earlier than `firstDay` is treated as `firstDay`.
    ///   - keptDays: every day that had something counted. Days outside the range are ignored.
    public init(firstDay: DayKey, today: DayKey, keptDays: Set<DayKey>) {
        let today = max(today, firstDay)
        self.firstDay = firstDay
        self.today = today
        self.keptDays = keptDays

        var attempts: [Attempt] = []
        var number = 1
        var start = firstDay
        var kept = 0
        var slips = 0
        var day = firstDay
        while day < today {
            if keptDays.contains(day) {
                kept += 1
                slips = 0
            } else {
                slips += 1
                if slips == 2 {
                    attempts.append(Attempt(number: number, start: start, end: day,
                                            length: start.distance(to: day) + 1, keptDays: kept))
                    number += 1
                    start = day.next
                    kept = 0
                    slips = 0
                }
            }
            day = day.next
        }
        if keptDays.contains(today) { kept += 1 }
        attempts.append(Attempt(number: number, start: start, end: nil,
                                length: start.distance(to: today) + 1, keptDays: kept))
        self.attempts = attempts
        self.slipsBeforeToday = slips
    }

    public var current: Attempt { attempts[attempts.count - 1] }
    public var failedAttempts: [Attempt] { attempts.filter(\.failed) }

    /// Today's place in the current attempt, 1-based: `DAY n / 182`. Keeps counting past 182.
    public var dayNumber: Int { current.start.distance(to: today) + 1 }

    /// 0 for days 1–182, 1 for 183–364, …
    public var halfYearIndex: Int { (dayNumber - 1) / Self.halfYear }
    /// 1…182 within the current half-year.
    public var dayInHalfYear: Int { (dayNumber - 1) % Self.halfYear + 1 }
    /// The first day of the current half-year view.
    public var halfYearStart: DayKey { current.start.adding(halfYearIndex * Self.halfYear) }

    /// Yesterday slipped: today must have something, or the attempt ends.
    public var isMustDay: Bool { slipsBeforeToday == 1 }
    public var todayKept: Bool { keptDays.contains(today) }

    /// The attempt that ended at the close of yesterday, if one did (today is day 1 of a new attempt).
    public var attemptEndedYesterday: Attempt? {
        guard let last = failedAttempts.last, last.end == today.previous else { return nil }
        return last
    }

    public func outcome(of day: DayKey) -> DayOutcome {
        if day < firstDay || day > today { return .none }
        if keptDays.contains(day) { return .kept }
        return day == today ? .open : .slipped
    }

    /// The attempt a day belongs to.
    public func attempt(containing day: DayKey) -> Attempt? {
        attempts.first { day >= $0.start && day <= ($0.end ?? today) }
    }

    /// Tomorrow, if today closes as it stands now.
    public func projectedTomorrow() -> Ledger {
        Ledger(firstDay: firstDay, today: today.next, keptDays: keptDays)
    }

    /// The same ledger with today counted (what logging one thing would do).
    public func keepingToday() -> Ledger {
        Ledger(firstDay: firstDay, today: today, keptDays: keptDays.union([today]))
    }
}
