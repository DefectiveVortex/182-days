import Foundation
import Testing
@testable import DaysCore

private let ny = TimeZone(identifier: "America/New_York")!
private let clock = DayClock(timeZone: ny)
private func at(_ day: DayKey, _ h: Int, _ m: Int = 0) -> Date { clock.date(on: day, at: ClockTime(hour: h, minute: m)) }

@Suite struct LettersPhotoTests {
    let first = DayKey(year: 2026, month: 11, day: 18) // a Wednesday

    @Test func halfYearMarks() {
        #expect(LetterMarks.dayOfHalfYear(first, firstDay: first) == 1)
        #expect(LetterMarks.isMarkDay(first, firstDay: first))
        #expect(LetterMarks.isMarkDay(first.adding(29), firstDay: first)) // day 30
        #expect(!LetterMarks.isMarkDay(first.adding(30), firstDay: first))
        #expect(LetterMarks.dayOfHalfYear(first.adding(182), firstDay: first) == 1) // next half-year
        #expect(LetterMarks.defaultOpens(written: first, firstDay: first) == first.adding(181))
        #expect(LetterMarks.defaultOpens(written: first.adding(59), firstDay: first) == first.adding(181))
        #expect(LetterMarks.defaultOpens(written: first.adding(182), firstDay: first) == first.adding(363))
    }

    @Test func letterSealedUntilOpens() {
        let l = Letter(written: first, opens: first.adding(181), text: "Hold on.")
        #expect(!l.isOpen(on: first.adding(180)))
        #expect(l.isOpen(on: first.adding(181)))
    }

    @Test func photoWeek() {
        let sunday = DayKey(year: 2026, month: 11, day: 22)
        #expect(sunday.weekday == 1)
        #expect(PhotoWeek.sunday(of: first) == DayKey(year: 2026, month: 11, day: 15))
        #expect(PhotoWeek.sunday(of: sunday) == sunday)
        #expect(PhotoWeek.isDue(today: first, photoDays: [])) // the first photo is due at once
        #expect(!PhotoWeek.isDue(today: first.adding(2), photoDays: [first])) // same week
        #expect(PhotoWeek.isDue(today: sunday, photoDays: [first])) // new week
        #expect(!PhotoWeek.isDue(today: sunday.adding(1), photoDays: [first, sunday]))
    }

    @Test func sundayPhotoNotification() {
        let sunday = DayKey(year: 2026, month: 11, day: 22)
        let s = DaysSettings(firstDay: first, startingNumbers: [.pushUps: 20])
        let entries = (0..<4).map { Entry(practice: .pushUps, day: first.adding($0), at: at(first.adding($0), 9), value: 10) }
        func plan(_ photos: [DayKey]) -> [PlannedNotification] {
            let today = DayBook.today(now: at(sunday, 5), clock: clock, settings: s, entries: entries, journal: [:])
            return NotificationPlanner.plan(now: at(sunday, 5), clock: clock, settings: s, today: today,
                                            schedule: .init(), photoDays: photos)
        }
        let due = plan([first]).filter { $0.kind == .photo }
        #expect(due.count == 1)
        #expect(due.first?.day == sunday)
        #expect(due.first?.category == .photo)
        #expect(plan([first, sunday]).filter { $0.kind == .photo }.isEmpty)
        // Not on a weekday, even when a photo is due.
        let wed = DayBook.today(now: at(first, 5), clock: clock, settings: s, entries: [], journal: [:])
        let p = NotificationPlanner.plan(now: at(first, 5), clock: clock, settings: s, today: wed, schedule: .init())
        #expect(p.filter { $0.kind == .photo }.isEmpty)
    }
}
