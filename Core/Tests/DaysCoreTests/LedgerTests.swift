import Foundation
import Testing
@testable import DaysCore

private let d0 = DayKey(year: 2026, month: 11, day: 18)
private func days(_ offsets: [Int]) -> Set<DayKey> { Set(offsets.map { d0.adding($0) }) }

@Suite struct LedgerTests {
    @Test func firstDayIsDayOneAndOpen() {
        let l = Ledger(firstDay: d0, today: d0, keptDays: [])
        #expect(l.dayNumber == 1)
        #expect(l.current.number == 1)
        #expect(!l.isMustDay)
        #expect(l.outcome(of: d0) == .open)
        #expect(l.outcome(of: d0.previous) == .none)
    }

    @Test func oneSlipMakesAMustDay() {
        let l = Ledger(firstDay: d0, today: d0.adding(2), keptDays: days([0]))
        #expect(l.outcome(of: d0.adding(1)) == .slipped)
        #expect(l.isMustDay)
        #expect(l.dayNumber == 3)
        #expect(l.attempts.count == 1)
    }

    @Test func keepingTheMustDayResets() {
        let l = Ledger(firstDay: d0, today: d0.adding(3), keptDays: days([0, 2]))
        #expect(!l.isMustDay)
        #expect(l.attempts.count == 1)
        #expect(l.dayNumber == 4)
    }

    @Test func twoSlipsEndTheAttempt() {
        // Kept 0,1; slipped 2,3; today = 4 is day 1 of attempt 2.
        let l = Ledger(firstDay: d0, today: d0.adding(4), keptDays: days([0, 1]))
        #expect(l.attempts.count == 2)
        let failed = l.attempts[0]
        #expect(failed.failed && failed.end == d0.adding(3) && failed.length == 4 && failed.keptDays == 2)
        #expect(l.current.number == 2 && l.current.start == d0.adding(4))
        #expect(l.dayNumber == 1)
        #expect(!l.isMustDay)
        #expect(l.attemptEndedYesterday == failed)
        // History stays: the old days keep their outcomes.
        #expect(l.outcome(of: d0.adding(1)) == .kept)
        #expect(l.outcome(of: d0.adding(3)) == .slipped)
        #expect(l.attempt(containing: d0.adding(2))?.number == 1)
    }

    @Test func emptyFirstDaysFailTheFirstAttempt() {
        let l = Ledger(firstDay: d0, today: d0.adding(2), keptDays: [])
        #expect(l.attempts.count == 2)
        #expect(l.current.start == d0.adding(2))
        #expect(l.dayNumber == 1)
    }

    @Test func alternatingSlipsNeverFail() {
        let kept = days(Array(stride(from: 0, to: 40, by: 2)))
        let l = Ledger(firstDay: d0, today: d0.adding(40), keptDays: kept)
        #expect(l.attempts.count == 1)
        #expect(l.isMustDay)
        #expect(l.dayNumber == 41)
    }

    @Test func countGoesOnPast182() {
        let kept = days(Array(0..<200))
        let l = Ledger(firstDay: d0, today: d0.adding(199), keptDays: kept)
        #expect(l.dayNumber == 200)
        #expect(l.halfYearIndex == 1)
        #expect(l.dayInHalfYear == 18)
        #expect(l.halfYearStart == d0.adding(182))
        let at182 = Ledger(firstDay: d0, today: d0.adding(181), keptDays: kept)
        #expect(at182.dayInHalfYear == 182 && at182.halfYearIndex == 0)
    }

    @Test func projections() {
        let must = Ledger(firstDay: d0, today: d0.adding(2), keptDays: days([0]))
        let tomorrow = must.projectedTomorrow()
        #expect(tomorrow.current.number == 2 && tomorrow.dayNumber == 1)
        #expect(tomorrow.attemptEndedYesterday != nil)
        let saved = must.keepingToday().projectedTomorrow()
        #expect(saved.current.number == 1 && !saved.isMustDay)
        let normal = Ledger(firstDay: d0, today: d0.adding(1), keptDays: days([0]))
        #expect(normal.projectedTomorrow().isMustDay)
    }

    @Test func todayBeforeFirstDayIsClamped() {
        let l = Ledger(firstDay: d0, today: d0.adding(-3), keptDays: [])
        #expect(l.today == d0 && l.dayNumber == 1)
    }
}

@Suite struct DayRuleTests {
    let t = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func whatKeepsADay() {
        let s = DaysSettings(firstDay: d0)
        func kept(_ es: [Entry]) -> Bool { !es.keptDays(practices: s.practices).isEmpty }
        #expect(kept([Entry(practice: .pushUps, day: d0, at: t, value: 1)]))
        #expect(!kept([Entry(practice: .pushUps, day: d0, at: t, value: 0)]))
        #expect(kept([Entry(practice: .posture, day: d0, at: t, value: 0)])) // slouching still answers
        #expect(!kept([Entry(practice: "journal", day: d0, at: t, value: 1)])) // unknown practice
        #expect(!kept([]))
    }

    @Test func practiceValues() {
        let es = [
            Entry(practice: .pushUps, day: d0, at: t, value: 10),
            Entry(practice: .pushUps, day: d0, at: t, value: 5),
            Entry(practice: .posture, day: d0, at: t, value: 1),
            Entry(practice: .posture, day: d0, at: t, value: 0),
            Entry(practice: .posture, day: d0, at: t, value: 1),
        ]
        #expect(Practice.pushUps.value(of: es) == 15)
        #expect(Practice.posture.value(of: es) == 2)
        let mood = Practice(id: "mood", name: "Mood", kind: .rating)
        let r = [Entry(practice: "mood", day: d0, at: t, value: 2),
                 Entry(practice: "mood", day: d0, at: t.addingTimeInterval(60), value: 4)]
        #expect(mood.value(of: r) == 4)
    }
}
