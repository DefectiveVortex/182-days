import DaysCore
import Foundation
import UIKit

/// `-demo <scenario>` (CI screenshots, .github/screenshots.txt). Owner: Days 2.
/// Seeds the in-memory store with a believable history and fixes the clock at Tue 17 Nov 2026, 12:00,
/// so every screen reads real data through Core exactly as the app does.
///
///   normal      day 23: 18 push-ups against a ghost of 31, one slip 14 days ago (the design)
///   must        day 23: yesterday was empty, nothing logged yet today
///   ahead       day 23: past the ghost on push-ups and sit-ups
///   ended       two slips in a row ended attempt 1 yesterday; today is attempt 2, day 1
///   onboarding  nothing: a fresh install
///
/// Every scenario but onboarding also has the day-1 letter (sealed until day 182) and a posture photo on day 1
/// and each Sunday since; `ahead` leaves out this week's, so Today asks for it.
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
            func block(_ h: Int, _ m: Int, _ minutes: Int, _ title: String, _ p: PracticeID? = nil, notify: Bool = true) {
                schedule.blocks.append(ScheduleBlock(weekday: weekday, start: ClockTime(hour: h, minute: m), minutes: minutes,
                                                     title: title, practice: p, notify: notify))
            }
            block(7, 30, 20, "Push-ups", .pushUps)
            if (2...6).contains(weekday) {
                block(9, 0, 120, "Classes", notify: false)
                block(12, 0, 180, "Study block")
                block(15, 0, 45, "Walk")
            } else {
                block(10, 0, 90, "Long walk")
            }
            block(19, 0, 20, "Sit-ups", .sitUps)
            block(21, 30, 30, "Read", notify: false)
        }

        store.seedForDemo(
            settings: DaysSettings(
                firstDay: first,
                startingNumbers: [.pushUps: 12, .sitUps: 25],
                posturePingsPerDay: 6
            ),
            entries: entries,
            journal: [
                today.adding(-1): "Did the second set without stopping.",
                today.adding(-2): "Sat up straight through the whole lecture.",
                today.adding(-3): "Walked instead of the bus.",
                today.adding(-5): "Pushed past the ghost on sit-ups.",
                today.adding(-7): "Hard day. Did the minimum and it counted.",
                today.adding(-13): "Back after the slip.",
            ],
            schedule: schedule
        )

        store.seedLetterForDemo(Letter(
            written: first,
            opens: LetterMarks.defaultOpens(written: first, firstDay: first),
            text: "You started with 12 push-ups and a back that hurt by lunch. If you are reading this on day 182, you did not quit. Stand up straight and do one more set."
        ))
        var photoDays = [first]
        var sunday = PhotoWeek.sunday(of: first).adding(7)
        while sunday <= today { photoDays.append(sunday); sunday = sunday.adding(7) }
        if scenario == "ahead" { photoDays.removeAll { $0 == PhotoWeek.sunday(of: today) } }
        for (i, day) in photoDays.enumerated() {
            let progress = photoDays.count > 1 ? CGFloat(i) / CGFloat(photoDays.count - 1) : 0
            store.seedPhotoForDemo(posturePhoto(lean: 52 - 38 * progress), on: day)
        }
    }

    /// A side-on figure against a wall, drawn rather than photographed: `lean` is how far the head sits
    /// forward of the hips, in pixels of a 600×800 frame.
    static func posturePhoto(lean: CGFloat) -> Data {
        let size = CGSize(width: 600, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { ctx in
            let c = ctx.cgContext
            UIColor(white: 0.17, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.23, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 700, width: 600, height: 100))
            let figure = UIColor(white: 0.58, alpha: 1)
            figure.setStroke()
            figure.setFill()
            c.setLineCap(.round)
            c.setLineJoin(.round)
            let hip = CGPoint(x: 280, y: 470)
            let shoulder = CGPoint(x: 284 + lean * 0.45, y: 285)
            let head = CGPoint(x: 296 + lean, y: 200)
            c.setLineWidth(48)
            c.move(to: CGPoint(x: 292, y: 690))
            c.addLine(to: CGPoint(x: 290, y: 585))
            c.addLine(to: hip)
            c.strokePath()
            c.setLineWidth(96)
            c.move(to: hip)
            c.addQuadCurve(to: shoulder, control: CGPoint(x: hip.x - lean * 0.55, y: 385))
            c.strokePath()
            c.setLineWidth(36)
            c.move(to: shoulder)
            c.addLine(to: CGPoint(x: head.x - 6, y: head.y + 36))
            c.strokePath()
            c.fillEllipse(in: CGRect(x: head.x - 44, y: head.y - 52, width: 88, height: 100))
        }
    }

    /// Tue 17 Nov 2026, 12:00 local.
    static let fixedNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17; c.hour = 12
        return Calendar.current.date(from: c) ?? .now
    }()
}
