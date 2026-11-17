import Foundation

/// One logical day, identified by the calendar date on which it starts (at 04:00 local).
/// Stored as a plain day number so it compares, hashes and persists without a time zone.
public struct DayKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Days since 1970-01-01 (proleptic Gregorian).
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(year: Int, month: Int, day: Int) {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146097 + doe - 719468
    }

    /// (year, month, day) of the calendar date this logical day starts on.
    public var civil: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var day: Int { civil.day }

    /// 1 = Sunday … 7 = Saturday (the `Calendar` convention).
    public var weekday: Int { (((ordinal + 4) % 7) + 7) % 7 + 1 }

    public func adding(_ days: Int) -> DayKey { DayKey(ordinal: ordinal + days) }
    public var previous: DayKey { adding(-1) }
    public var next: DayKey { adding(1) }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func distance(to other: DayKey) -> Int { other.ordinal - ordinal }

    public static func < (a: DayKey, b: DayKey) -> Bool { a.ordinal < b.ordinal }

    public var description: String {
        let c = civil
        let mm = c.month < 10 ? "0\(c.month)" : "\(c.month)"
        let dd = c.day < 10 ? "0\(c.day)" : "\(c.day)"
        return "\(c.year)-\(mm)-\(dd)"
    }

    public init(from decoder: Decoder) throws {
        ordinal = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(ordinal)
    }
}
