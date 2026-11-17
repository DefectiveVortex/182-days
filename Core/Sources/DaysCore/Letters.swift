import Foundation

/// A sealed letter to his future self. It cannot be read or edited before `opens`, and it survives a failed
/// attempt (letters belong to the half-year, not the attempt).
public struct Letter: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let written: DayKey
    public let opens: DayKey
    public let text: String

    public init(id: UUID = UUID(), written: DayKey, opens: DayKey, text: String) {
        self.id = id
        self.written = written
        self.opens = opens
        self.text = text
    }

    public func isOpen(on today: DayKey) -> Bool { today >= opens }
}

/// When letters are asked for and when they open. Half-years count from `settings.firstDay` in blocks of 182
/// days, whatever happens to attempts.
public enum LetterMarks {
    public static let halfYear = 182
    /// Days of the half-year (1-based) a letter is asked for: day 1, then every 30 days.
    public static let markDays = [1, 30, 60, 90, 120, 150, 180]

    /// 1-based day of the half-year `day` falls in (day 183 is day 1 of the second half-year).
    public static func dayOfHalfYear(_ day: DayKey, firstDay: DayKey) -> Int {
        max(0, firstDay.distance(to: day)) % halfYear + 1
    }

    public static func isMarkDay(_ day: DayKey, firstDay: DayKey) -> Bool {
        markDays.contains(dayOfHalfYear(day, firstDay: firstDay))
    }

    /// The default opening day: the last day (day 182) of the half-year the letter is written in.
    public static func defaultOpens(written: DayKey, firstDay: DayKey) -> DayKey {
        let index = max(0, firstDay.distance(to: written)) / halfYear
        return firstDay.adding(index * halfYear + halfYear - 1)
    }
}

/// The weekly posture photo. The week runs Sunday to Saturday (logical days, 04:00 to 04:00).
public enum PhotoWeek {
    /// The Sunday that starts the week `day` is in.
    public static func sunday(of day: DayKey) -> DayKey { day.adding(1 - day.weekday) }

    /// A photo is due when none has been taken since this week's Sunday. The first photo ever is due at once,
    /// so week 1 has its ghost.
    public static func isDue(today: DayKey, photoDays: [DayKey]) -> Bool {
        let from = sunday(of: today)
        return !photoDays.contains { $0 >= from && $0 <= today }
    }
}
