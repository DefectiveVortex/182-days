import Foundation
import Testing
@testable import DaysCore

private let ny = TimeZone(identifier: "America/New_York")!
private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

private func instant(_ tz: TimeZone, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = tz
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Suite struct DayKeyTests {
    @Test func roundTripsCivilDates() {
        for (y, m, d) in [(1970, 1, 1), (2000, 2, 29), (2026, 11, 17), (2027, 5, 18), (1969, 12, 31)] {
            let k = DayKey(year: y, month: m, day: d)
            #expect(k.year == y && k.month == m && k.day == d)
        }
        #expect(DayKey(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(DayKey(year: 1969, month: 12, day: 31).ordinal == -1)
    }

    @Test func weekday() {
        #expect(DayKey(year: 2026, month: 11, day: 17).weekday == 3) // Tuesday
        #expect(DayKey(year: 1970, month: 1, day: 1).weekday == 5)   // Thursday
        #expect(DayKey(year: 2026, month: 11, day: 22).weekday == 1) // Sunday
    }

    @Test func arithmeticAndCoding() throws {
        let a = DayKey(year: 2026, month: 12, day: 31)
        #expect(a.next == DayKey(year: 2027, month: 1, day: 1))
        #expect(a.distance(to: a.adding(181)) == 181)
        #expect(a.description == "2026-12-31")
        let data = try JSONEncoder().encode([a])
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [a])
    }
}

@Suite struct DayClockTests {
    let clock = DayClock(timeZone: ny)

    @Test func boundaryIsFourAM() {
        let day = DayKey(year: 2026, month: 11, day: 17)
        #expect(clock.day(containing: instant(ny, 2026, 11, 18, 3, 59)) == day)
        #expect(clock.day(containing: instant(ny, 2026, 11, 18, 4, 0)) == day.next)
        #expect(clock.day(containing: instant(ny, 2026, 11, 17, 4, 0)) == day)
        #expect(clock.day(containing: instant(ny, 2026, 11, 17, 0, 30)) == day.previous)
        #expect(clock.start(of: day) == instant(ny, 2026, 11, 17, 4))
        #expect(clock.end(of: day) == instant(ny, 2026, 11, 18, 4))
    }

    @Test func dstSpringForwardDayIs23Hours() {
        let day = DayKey(year: 2026, month: 3, day: 7) // 04:00 Mar 7 → 04:00 Mar 8, clocks jump at 02:00 Mar 8
        #expect(clock.end(of: day).timeIntervalSince(clock.start(of: day)) == 23 * 3600)
    }

    @Test func dstFallBackDayIs25Hours() {
        let day = DayKey(year: 2026, month: 10, day: 31) // clocks fall back at 02:00 Nov 1
        #expect(clock.end(of: day).timeIntervalSince(clock.start(of: day)) == 25 * 3600)
        // Both 01:30s belong to Oct 31's logical day.
        let first = instant(ny, 2026, 11, 1, 1, 30)
        #expect(clock.day(containing: first) == day)
        #expect(clock.day(containing: first.addingTimeInterval(3600)) == day)
    }

    @Test func travelUsesTheLocalZone() {
        // 2026-11-18 03:00 in Kolkata is 2026-11-17 16:30 in New York.
        let t = instant(kolkata, 2026, 11, 18, 3)
        #expect(DayClock(timeZone: kolkata).day(containing: t) == DayKey(year: 2026, month: 11, day: 17))
        #expect(clock.day(containing: t) == DayKey(year: 2026, month: 11, day: 17))
        let t2 = instant(kolkata, 2026, 11, 18, 9)
        #expect(DayClock(timeZone: kolkata).day(containing: t2) == DayKey(year: 2026, month: 11, day: 18))
        #expect(clock.day(containing: t2) == DayKey(year: 2026, month: 11, day: 17))
    }

    @Test func timesAfterMidnightLandOnTheNextDate() {
        let day = DayKey(year: 2026, month: 11, day: 17)
        #expect(clock.date(on: day, at: ClockTime(hour: 1, minute: 15)) == instant(ny, 2026, 11, 18, 1, 15))
        #expect(clock.date(on: day, at: ClockTime(hour: 22)) == instant(ny, 2026, 11, 17, 22))
        #expect(ClockTime(hour: 1) > ClockTime(hour: 23))
        #expect(ClockTime(minuteOfLogicalDay: 0) == ClockTime(hour: 4))
        #expect(ClockTime(hour: 3, minute: 59).minuteOfLogicalDay == 1439)
    }
}
