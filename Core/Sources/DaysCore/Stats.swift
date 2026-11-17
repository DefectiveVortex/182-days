import Foundation

/// One square of the 182 grid.
public struct DayCell: Sendable, Equatable, Identifiable {
    public var id: DayKey { day }
    public let day: DayKey
    /// 1…182 within the half-year.
    public let index: Int
    public let outcome: DayOutcome
    /// Beat the previous day in at least one count practice.
    public let beatYesterday: Bool
}

public struct PracticeStats: Sendable, Equatable {
    public let practice: Practice
    public let total: Int
    public let best: (day: DayKey, value: Int)?
    /// The value on the first day of the current attempt.
    public let firstDayValue: Int
    /// Today's value, or the last kept day's if today is still empty.
    public let latestValue: Int

    public static func == (a: PracticeStats, b: PracticeStats) -> Bool {
        a.practice == b.practice && a.total == b.total && a.best?.day == b.best?.day
            && a.best?.value == b.best?.value && a.firstDayValue == b.firstDayValue && a.latestValue == b.latestValue
    }
}

/// The 182 view. Pure.
public struct Stats: Sendable, Equatable {
    public let ledger: Ledger
    /// The current half-year, 182 cells (future days have outcome `.none`).
    public let grid: [DayCell]
    /// Consecutive kept days ending today (or yesterday, if today is still open).
    public let currentRun: Int
    public let longestRun: Int
    /// Kept days in the current attempt.
    public let daysKept: Int
    /// Days in the current attempt that beat the day before.
    public let beatYesterdayDays: Int
    public let practices: [PracticeStats]

    public init(ledger: Ledger, settings: DaysSettings, entries: [Entry]) {
        self.ledger = ledger
        let byDay = entries.byDay()
        let countPractices = settings.practices.filter { $0.kind == .count || $0.kind == .duration }

        func beat(_ day: DayKey) -> Bool {
            countPractices.contains {
                DayBook.practiceDay($0, on: day, byDay: byDay, settings: settings).beatsGhost
            }
        }

        let start = ledger.halfYearStart
        grid = (0..<Ledger.halfYear).map { i in
            let day = start.adding(i)
            let outcome = ledger.outcome(of: day)
            return DayCell(day: day, index: i + 1, outcome: outcome,
                           beatYesterday: outcome == .kept && beat(day))
        }

        var run = 0
        var day = ledger.todayKept ? ledger.today : ledger.today.previous
        while day >= ledger.firstDay && ledger.keptDays.contains(day) {
            run += 1
            day = day.previous
        }
        currentRun = run

        var longest = 0
        var streak = 0
        day = ledger.firstDay
        while day <= ledger.today {
            if ledger.keptDays.contains(day) {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
            day = day.next
        }
        longestRun = longest

        let attemptStart = ledger.current.start
        let attemptDays = (0..<ledger.dayNumber).map { attemptStart.adding($0) }
        daysKept = attemptDays.filter { ledger.keptDays.contains($0) }.count
        beatYesterdayDays = attemptDays.filter { ledger.keptDays.contains($0) && beat($0) }.count

        let inRange = entries.filter { $0.day >= ledger.firstDay && $0.day <= ledger.today }
        let rangeByDay = inRange.byDay()
        practices = settings.practices.map { p in
            var best: (day: DayKey, value: Int)?
            var total = 0
            for (d, es) in rangeByDay {
                let v = p.value(of: es)
                if p.kind == .count || p.kind == .duration || p.kind == .check { total += v }
                if v > 0, best == nil || v > best!.value || (v == best!.value && d < best!.day) { best = (d, v) }
            }
            let latestDay = ledger.todayKept ? ledger.today
                : (rangeByDay.keys.filter { $0 < ledger.today }.max() ?? ledger.today)
            return PracticeStats(
                practice: p, total: total, best: best,
                firstDayValue: p.value(of: rangeByDay[attemptStart] ?? []),
                latestValue: p.value(of: rangeByDay[latestDay] ?? []))
        }
    }

    public static func == (a: Stats, b: Stats) -> Bool {
        a.ledger == b.ledger && a.grid == b.grid && a.currentRun == b.currentRun && a.longestRun == b.longestRun
            && a.daysKept == b.daysKept && a.beatYesterdayDays == b.beatYesterdayDays && a.practices == b.practices
    }
}
