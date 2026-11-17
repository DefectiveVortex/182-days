import DaysCore
import Foundation

/// `-demo <scenario>` (CI screenshots, .github/screenshots.txt). Owner: Days 2.
/// Seeds the in-memory store with a believable history and fixes the clock at Tue 17 Nov 2026, 12:00,
/// so every screen reads real data through Core exactly as the app does.
///
///   normal      day 23: 18 push-ups against a ghost of 31, one slip 14 days ago (the design)
///   must        day 23: yesterday was empty, nothing logged yet today
///   ahead       day 23: past the ghost on push-ups and sit-ups
///   ended       two slips in a row ended attempt 1 yesterday; today is attempt 2, day 1
///   onboarding  nothing: a fresh install
@MainActor
enum DemoData {
    static func seed(_ store: LogStore, scenario: String) {
        let now = fixedNow
        store.now = { now }
        guard scenario != "onboarding" else { return }

        let clock = store.clock
        let today = clock.day(containing: now)
        var entries: [Entry] = []
        func add(_ id: PracticeID, _ day: DayKey, hour: Int, _ value: Int) {
            entries.append(Entry(practice: id, day: day, at: clock.date(on: day, at: ClockTime(hour: hour)), value: value))
        }

        let length = scenario == "ended" ? 26 : 22   // days before today
        let first = today.adding(-length)
        var slips: Set<Int> = [14]                     // days ago
        if scenario == "must" { slips.insert(1) }
        if scenario == "ended" { slips.formUnion([1, 2]) }

        for ago in stride(from: length, through: 1, by: -1) where !slips.contains(ago) {
            let day = today.adding(-ago)
            let n = length - ago                       // 0, 1, 2… a slow climb with small dips
            let push = ago == 1 ? 31 : 12 + n - (n % 4 == 3 ? 3 : 0)
            let sit = ago == 1 ? 58 : 25 + n * 2 - (n % 5 == 4 ? 6 : 0)
            add(.pushUps, day, hour: 8, push - push / 3)
            add(.pushUps, day, hour: 19, push / 3)
            add(.sitUps, day, hour: 8, sit / 2)
            add(.sitUps, day, hour: 20, sit - sit / 2)
            for (i, upright) in [true, ago % 3 != 0, true, ago == 1 ? false : true].enumerated() {
                add(.posture, day, hour: 10 + i * 3, upright ? 1 : 0)
            }
        }

        switch scenario {
        case "must", "ended":
            break
        case "ahead":
            for (h, v) in [(7, 10), (9, 10), (10, 10), (11, 6)] { add(.pushUps, today, hour: h, v) }
            for (h, v) in [(7, 30), (11, 40)] { add(.sitUps, today, hour: h, v) }
            for h in [5, 8, 11] { add(.posture, today, hour: h, 1) }
        default: // normal
            for (h, v) in [(7, 10), (9, 5), (11, 3)] { add(.pushUps, today, hour: h, v) }
            for (h, v) in [(7, 20), (10, 20)] { add(.sitUps, today, hour: h, v) }
            for (h, v) in [(5, 1), (7, 1), (8, 0), (10, 1), (11, 1)] { add(.posture, today, hour: h, v) }
        }

        var schedule = WeekSchedule()
        for weekday in 1...7 {
            schedule.blocks.append(ScheduleBlock(weekday: weekday, start: ClockTime(hour: 12), minutes: 180, title: "Study block"))
            schedule.blocks.append(ScheduleBlock(weekday: weekday, start: ClockTime(hour: 15), minutes: 45, title: "Walk"))
        }

        store.seedForDemo(
            settings: DaysSettings(
                firstDay: first,
                startingNumbers: [.pushUps: 12, .sitUps: 25],
                posturePingsPerDay: 6
            ),
            entries: entries,
            journal: [today.previous: "Did the second set without stopping."],
            schedule: schedule
        )
    }

    /// Tue 17 Nov 2026, 12:00 local.
    static let fixedNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17; c.hour = 12
        return Calendar.current.date(from: c) ?? .now
    }()
}
