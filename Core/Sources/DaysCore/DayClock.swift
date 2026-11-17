import Foundation

/// A wall-clock time of day, e.g. 07:30.
public struct ClockTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    /// Minutes after midnight, 0..<1440.
    public var minuteOfDay: Int { hour * 60 + minute }

    /// Minutes after the 04:00 day boundary, 0..<1440. 03:30 is 1410: the very end of a day.
    public var minuteOfLogicalDay: Int {
        ((minuteOfDay - DayClock.boundaryHour * 60) % 1440 + 1440) % 1440
    }

    public init(minuteOfLogicalDay m: Int) {
        let wall = ((m + DayClock.boundaryHour * 60) % 1440 + 1440) % 1440
        self.init(hour: wall / 60, minute: wall % 60)
    }

    /// Ordered by position within a logical day, so 23:00 < 01:00 < 03:59.
    public static func < (a: ClockTime, b: ClockTime) -> Bool {
        a.minuteOfLogicalDay < b.minuteOfLogicalDay
    }

    public var description: String {
        (hour < 10 ? "0\(hour)" : "\(hour)") + ":" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }
}

/// Maps instants to logical days. A day runs 04:00 to 04:00 in the given time zone.
/// Travel: the day is always computed in the zone the phone is in at that moment.
public struct DayClock: Sendable, Equatable {
    public static let boundaryHour = 4

    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) { self.timeZone = timeZone }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// The logical day containing `date`.
    public func day(containing date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let key = DayKey(year: c.year!, month: c.month!, day: c.day!)
        return c.hour! < Self.boundaryHour ? key.previous : key
    }

    /// The instant `time` falls on during logical day `day`. Times before 04:00 land on the next calendar date.
    /// In a DST gap the time moves forward to the first valid instant.
    public func date(on day: DayKey, at time: ClockTime) -> Date {
        let calendarDay = time.hour < Self.boundaryHour ? day.next : day
        let c = calendarDay.civil
        var comps = DateComponents()
        comps.year = c.year
        comps.month = c.month
        comps.day = c.day
        comps.hour = time.hour
        comps.minute = time.minute
        if let d = calendar.date(from: comps) { return d }
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
    }

    /// 04:00 on `day`.
    public func start(of day: DayKey) -> Date { date(on: day, at: ClockTime(hour: Self.boundaryHour)) }

    /// 04:00 on the day after `day`: the instant `day` closes.
    public func end(of day: DayKey) -> Date { start(of: day.next) }
}
