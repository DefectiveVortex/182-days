import Foundation
import Testing
@testable import DaysCore

private let ny = TimeZone(identifier: "America/New_York")!
private let clock = DayClock(timeZone: ny)
private let d0 = DayKey(year: 2026, month: 11, day: 18)
private func at(_ day: DayKey, _ h: Int, _ m: Int = 0) -> Date { clock.date(on: day, at: ClockTime(hour: h, minute: m)) }

@Suite struct PlannerTests {
    let settings = DaysSettings(firstDay: d0, startingNumbers: [.pushUps: 20])

    func plan(now: Date, entries: [Entry], journal: [DayKey: String] = [:], schedule: WeekSchedule = .init(),
              settings: DaysSettings? = nil) -> [PlannedNotification] {
        let s = settings ?? self.settings
        let today = DayBook.today(now: now, clock: clock, settings: s, entries: entries, journal: journal)
        return NotificationPlanner.plan(now: now, clock: clock, settings: s, today: today, schedule: schedule)
    }

    @Test func notOnboardedPlansNothing() {
        let s = DaysSettings()
        let today = DayBook.today(now: at(d0, 8), clock: clock, settings: s, entries: [], journal: [:])
        #expect(NotificationPlanner.plan(now: at(d0, 8), clock: clock, settings: s, today: today, schedule: .init()).isEmpty)
    }

    @Test func normalDay() {
        let p = plan(now: at(d0, 6), entries: [])
        let today = p.filter { $0.day == d0 }
        #expect(today.filter { $0.kind == .close }.count == 1)
        #expect(today.filter { $0.kind == .posture }.count == 3)
        #expect(today.filter { $0.kind == .nudge }.count == 1)
        #expect(today.filter { $0.kind == .must }.isEmpty)
        #expect(p.allSatisfy { $0.fireDate > at(d0, 6) })
        #expect(Set(p.map(\.id)).count == p.count)
        // Tomorrow is projected as a must day (today is still empty).
        #expect(p.contains { $0.day == d0.next && $0.kind == .must })
    }

    @Test func mustDayEscalatesAndOneLogCancelsIt() {
        let es = [Entry(practice: .pushUps, day: d0, at: at(d0, 9), value: 10)]
        let must = plan(now: at(d0.adding(2), 6), entries: es)
        let escalation = must.filter { $0.kind == .must && $0.day == d0.adding(2) }.map(\.fireDate)
        #expect(escalation.count >= 6)
        #expect(escalation.first == at(d0.adding(2), 7))
        let gaps = zip(escalation.dropFirst(), escalation).map { $0.timeIntervalSince($1) }
        #expect(gaps == gaps.sorted(by: >)) // never gets slower
        #expect(escalation.last! <= at(d0.adding(2), 23, 30))
        // Tomorrow, if today stays empty: attempt 2 starts.
        #expect(must.contains { $0.kind == .attemptEnded && $0.day == d0.adding(3) })

        let logged = es + [Entry(practice: .sitUps, day: d0.adding(2), at: at(d0.adding(2), 12), value: 1)]
        let after = plan(now: at(d0.adding(2), 12, 1), entries: logged)
        #expect(!after.contains { $0.kind == .must })
        #expect(!after.contains { $0.kind == .attemptEnded })
    }

    @Test func closeIsSkippedOnceWrittenAndPastOnesDrop() {
        let es = [Entry(practice: .pushUps, day: d0, at: at(d0, 9), value: 25)]
        let p = plan(now: at(d0, 10), entries: es)
        let close = p.first { $0.kind == .close && $0.day == d0 }!
        #expect(close.body.contains("Push-ups 25 (yesterday 20)"))
        #expect(!p.contains { $0.kind == .nudge && $0.day == d0 })
        let written = plan(now: at(d0, 22), entries: es, journal: [d0: "did 25"])
        #expect(!written.contains { $0.kind == .close && $0.day == d0 })
        #expect(!written.contains { $0.day == d0 && $0.kind == .posture })
    }

    @Test func capKeepsTheImportantOnes() {
        var s = settings
        s.dailyNotificationCap = 2
        s.posturePingsPerDay = 5
        let block = ScheduleBlock(weekday: d0.weekday, start: ClockTime(hour: 18), minutes: 30, title: "Gym")
        let p = plan(now: at(d0, 5), entries: [], schedule: WeekSchedule(blocks: [block]), settings: s)
        let today = p.filter { $0.day == d0 }
        #expect(today.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.block, .close])
        #expect(today.first { $0.kind == .block }?.blockID == block.id)
    }

    @Test func dstDayStillPlansInsideTheDay() {
        let day = DayKey(year: 2026, month: 10, day: 31)
        var s = settings
        s.firstDay = day
        let p = plan(now: at(day, 5), entries: [], settings: s)
        #expect(p.filter { $0.day == day }.allSatisfy { $0.fireDate < clock.end(of: day) && $0.fireDate >= clock.start(of: day) })
    }
}
