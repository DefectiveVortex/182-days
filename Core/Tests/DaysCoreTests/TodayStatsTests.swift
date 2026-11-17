import Foundation
import Testing
@testable import DaysCore

private let ny = TimeZone(identifier: "America/New_York")!
private let clock = DayClock(timeZone: ny)
private let d0 = DayKey(year: 2026, month: 11, day: 18)

private func at(_ day: DayKey, _ h: Int, _ m: Int = 0) -> Date { clock.date(on: day, at: ClockTime(hour: h, minute: m)) }
private func e(_ p: PracticeID, _ day: DayKey, _ v: Int, _ h: Int = 9) -> Entry {
    Entry(practice: p, day: day, at: at(day, h), value: v)
}

@Suite struct TodayTests {
    let settings = DaysSettings(firstDay: d0, startingNumbers: [.pushUps: 20, .sitUps: 30])

    @Test func dayOneGhostIsTheStartingNumber() {
        let s = DayBook.today(now: at(d0, 10), clock: clock, settings: settings,
                              entries: [e(.pushUps, d0, 25)], journal: [:])
        let p = s[.pushUps]!
        #expect(p.ghost == 20 && p.value == 25 && p.overGhost == 20 && p.pastGhost == 5 && p.beatsGhost)
        #expect(s[.sitUps]!.ghost == 30 && s[.sitUps]!.value == 0)
        #expect(s.dayNumber == 1 && s.kept && s.beatYesterday)
    }

    @Test func ghostIsYesterday() {
        let es = [e(.pushUps, d0, 30), e(.pushUps, d0.next, 10), e(.pushUps, d0.next, 10, 11)]
        let s = DayBook.today(now: at(d0.next, 12), clock: clock, settings: settings, entries: es,
                              journal: [d0.next: "more"])
        let p = s[.pushUps]!
        #expect(p.ghost == 30 && p.value == 20 && p.pastGhost == 0 && !p.beatsGhost)
        #expect(p.entries.count == 2 && p.entries.last!.at == at(d0.next, 11))
        #expect(s.journalLine == "more")
        #expect(s.dayNumber == 2)
    }

    @Test func slipMeansZeroGhost() {
        let es = [e(.pushUps, d0, 30)]
        let s = DayBook.today(now: at(d0.adding(2), 9), clock: clock, settings: settings, entries: es, journal: [:])
        #expect(s.isMustDay && s[.pushUps]!.ghost == 0)
    }

    @Test func the4amEdge() {
        // 03:59 on the 19th still belongs to the 18th.
        let late = clock.date(on: d0, at: ClockTime(hour: 3, minute: 59))
        #expect(clock.day(containing: late) == d0)
        let s = DayBook.today(now: late, clock: clock, settings: settings, entries: [], journal: [:])
        #expect(s.day == d0)
        let s2 = DayBook.today(now: late.addingTimeInterval(60), clock: clock, settings: settings, entries: [], journal: [:])
        #expect(s2.day == d0.next && s2.isMustDay)
    }

    @Test func flyingWestDoesNotReopenAClosedDay() {
        // Logged on the 19th in Kolkata, then in New York where it's still the 18th.
        let es = [e(.pushUps, d0, 10), e(.pushUps, d0.next, 10)]
        let s = DayBook.today(now: at(d0, 20), clock: clock, settings: settings, entries: es, journal: [:])
        #expect(s.day == d0.next)
    }
}

@Suite struct StatsTests {
    let settings = DaysSettings(firstDay: d0, startingNumbers: [.pushUps: 20])

    @Test func runsBestsAndBeats() {
        // Day values: 0:20, 1:25, 2:slip, 3:30, 4:10(today)
        let es = [e(.pushUps, d0, 20), e(.pushUps, d0.adding(1), 25), e(.pushUps, d0.adding(3), 30),
                  e(.pushUps, d0.adding(4), 10), e(.sitUps, d0.adding(4), 5)]
        let ledger = Ledger(firstDay: d0, today: d0.adding(4), keptDays: es.keptDays(practices: settings.practices))
        let st = Stats(ledger: ledger, settings: settings, entries: es)
        #expect(st.currentRun == 2)
        #expect(st.longestRun == 2)
        #expect(st.daysKept == 4)
        // Beat: day1 (25>20), day3 (30>0), day4 (sit-ups 5>0). Day 0: 20 vs start 20, no.
        #expect(st.beatYesterdayDays == 3)
        let push = st.practices.first { $0.practice.id == .pushUps }!
        #expect(push.total == 85 && push.best?.value == 30 && push.best?.day == d0.adding(3))
        #expect(push.firstDayValue == 20 && push.latestValue == 10)
        #expect(st.grid.count == 182)
        #expect(st.grid[2].outcome == .slipped && st.grid[4].outcome == .kept && st.grid[5].outcome == .none)
        #expect(st.grid[1].beatYesterday && !st.grid[0].beatYesterday)
    }
}

@Suite struct ScheduleTests {
    @Test func copyDayReplacesTargets() {
        var w = WeekSchedule(blocks: [
            ScheduleBlock(weekday: 2, start: ClockTime(hour: 7), minutes: 30, title: "Push-ups", practice: .pushUps),
            ScheduleBlock(weekday: 2, start: ClockTime(hour: 1), minutes: 60, title: "Read"),
            ScheduleBlock(weekday: 3, start: ClockTime(hour: 9), minutes: 60, title: "Old"),
        ])
        w.copyDay(2, to: [3, 4, 2])
        #expect(w.blocks(on: 3).map(\.title) == ["Push-ups", "Read"]) // 01:00 sorts after 07:00
        #expect(w.blocks(on: 4).count == 2)
        #expect(w.blocks(on: 2).count == 2)
        #expect(Set(w.blocks.map(\.id)).count == 6)
    }
}
