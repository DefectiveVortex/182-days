import Foundation

public enum NotificationKind: String, Codable, Sendable {
    /// Yesterday slipped and nothing is logged yet. Escalates through the day; all cancelled by one log.
    case must
    /// "Close the day": one line, what did you do better than yesterday.
    case close
    /// A schedule block starts: On it / Skip.
    case block
    /// Upright / Slouching.
    case posture
    /// A normal day, nothing logged by the afternoon.
    case nudge
    /// The previous attempt ended overnight; a new one starts today.
    case attemptEnded
}

/// Notification categories, registered by the app with these actions.
public enum NotificationCategory: String, Codable, Sendable, CaseIterable {
    /// Actions: +10 push-ups, +10 sit-ups. Log without opening the app.
    case log = "days.log"
    /// Actions: Upright, Slouching.
    case posture = "days.posture"
    /// Action: a text field for the day's line (+ the log actions).
    case close = "days.close"
    /// Actions: On it, Skip.
    case block = "days.block"
}

public enum NotificationAction: String, Codable, Sendable, CaseIterable {
    case pushUps10 = "days.log.pushups10"
    case sitUps10 = "days.log.situps10"
    case upright = "days.posture.upright"
    case slouching = "days.posture.slouching"
    case closeLine = "days.close.line"
    case blockOnIt = "days.block.onit"
    case blockSkip = "days.block.skip"
}

public struct PlannedNotification: Identifiable, Hashable, Sendable {
    /// Stable per day and slot, e.g. `must-20406-3`, so replanning replaces rather than duplicates.
    public let id: String
    public let kind: NotificationKind
    public let day: DayKey
    public let fireDate: Date
    public let title: String
    public let body: String
    public let category: NotificationCategory
    /// For `.block`.
    public let blockID: UUID?
}

/// Which notifications should be pending, for a state and a clock. Pure; the app replaces every pending
/// notification with this list whenever anything changes (a log, a setting, the app opening, a new day).
///
/// Few, each with a reason, capped per day. Must-day escalation is exempt from the cap and stops the moment
/// one thing is logged (the next plan simply has none).
public enum NotificationPlanner {
    /// Must-day gaps, in minutes, starting at wake: they shrink through the day.
    public static let mustGaps = [0, 180, 150, 120, 90, 60, 45, 30]
    /// iOS keeps at most 64 pending; stay well under.
    public static let maxPending = 48

    public static func plan(
        now: Date, clock: DayClock, settings: DaysSettings, today: TodayState, schedule: WeekSchedule,
        horizonDays: Int = 2
    ) -> [PlannedNotification] {
        guard settings.isOnboarded else { return [] }
        var out: [PlannedNotification] = []
        var ledger = today.ledger
        for offset in 0..<max(1, horizonDays) {
            if offset > 0 { ledger = ledger.projectedTomorrow() }
            let isToday = offset == 0
            out += planDay(
                ledger: ledger, now: now, clock: clock, settings: settings, schedule: schedule,
                kept: isToday ? today.kept : false,
                closed: isToday ? today.journalLine != nil : false,
                today: isToday ? today : nil)
        }
        out.sort { $0.fireDate < $1.fireDate }
        return Array(out.prefix(maxPending))
    }

    static func planDay(
        ledger: Ledger, now: Date, clock: DayClock, settings: DaysSettings, schedule: WeekSchedule,
        kept: Bool, closed: Bool, today: TodayState?
    ) -> [PlannedNotification] {
        let day = ledger.today
        let n = ledger.dayNumber
        let end = clock.end(of: day)
        let wake = clock.date(on: day, at: settings.wake)
        let sleep = clock.date(on: day, at: settings.sleep)
        let tag = "\(day.ordinal)"

        func make(_ id: String, _ kind: NotificationKind, _ at: Date, _ title: String, _ body: String,
                  _ cat: NotificationCategory, block: UUID? = nil) -> PlannedNotification {
            PlannedNotification(id: "\(id)-\(tag)", kind: kind, day: day, fireDate: at, title: title, body: body,
                                category: cat, blockID: block)
        }

        var exempt: [PlannedNotification] = []
        // Lower index = higher priority under the cap.
        var capped: [(priority: Int, note: PlannedNotification)] = []

        if let ended = ledger.attemptEndedYesterday {
            exempt.append(make("ended", .attemptEnded, wake, "Attempt \(ended.number) ended",
                               "Two empty days. It lasted \(ended.length) days. Attempt \(ended.number + 1) starts now: day 1.",
                               .log))
        }

        if ledger.isMustDay && !kept {
            let last = min(sleep > wake ? sleep : end, end.addingTimeInterval(-15 * 60))
            var t = wake
            var i = 0
            while t <= last {
                let body: String
                switch i {
                case 0: body = "Yesterday was empty. One more empty day ends attempt \(ledger.current.number)."
                case 1, 2: body = "Still nothing today. One set is enough to keep it."
                default: body = "Nothing logged yet. Attempt \(ledger.current.number) ends at 4:00 if today stays empty."
                }
                exempt.append(make("must-\(i)", .must, t, "Day \(n). Must day.", body, .log))
                i += 1
                let gap = i < mustGaps.count ? mustGaps[i] : mustGaps[mustGaps.count - 1]
                t = t.addingTimeInterval(Double(gap) * 60)
            }
        }

        if !closed {
            let at = clock.date(on: day, at: settings.eveningClose)
            var body = "What did you do better than yesterday?"
            if let today, today.kept {
                let parts = today.practices.filter { $0.practice.kind == .count && $0.value > 0 }
                    .map { "\($0.practice.name) \($0.value) (yesterday \($0.ghost))" }
                if !parts.isEmpty { body = parts.joined(separator: ", ") + ". " + body }
            } else if !kept {
                body = "Nothing logged today yet. " + body
            }
            capped.append((0, make("close", .close, at, "Close day \(n)", body, .close)))
        }

        for b in schedule.blocks(on: day) where b.notify {
            let at = clock.date(on: day, at: b.start)
            capped.append((1, make("block-\(b.id.uuidString)", .block, at, b.title,
                                   "Starts now, \(b.minutes) min.", .block, block: b.id)))
        }

        let pings = max(0, settings.posturePingsPerDay)
        if pings > 0 {
            let from = wake.addingTimeInterval(90 * 60)
            let to = (sleep > wake ? sleep : end).addingTimeInterval(-60 * 60)
            if to > from {
                let step = to.timeIntervalSince(from) / Double(pings + 1)
                for i in 1...pings {
                    let at = from.addingTimeInterval(step * Double(i))
                    capped.append((2, make("posture-\(i)", .posture, at, "Posture", "Upright or slouching?", .posture)))
                }
            }
        }

        if !ledger.isMustDay && !kept {
            let close = clock.date(on: day, at: settings.eveningClose)
            let at = wake.addingTimeInterval(close.timeIntervalSince(wake) / 2)
            if at > wake {
                capped.append((3, make("nudge", .nudge, at, "Day \(n)",
                                       "Nothing logged yet. An empty day makes tomorrow a must day.", .log)))
            }
        }

        let future = capped.filter { $0.note.fireDate > now && $0.note.fireDate < end }
        let chosen = future.sorted { ($0.priority, $0.note.fireDate) < ($1.priority, $1.note.fireDate) }
            .prefix(max(0, settings.dailyNotificationCap)).map(\.note)
        return exempt.filter { $0.fireDate > now && $0.fireDate < end } + chosen
    }
}
