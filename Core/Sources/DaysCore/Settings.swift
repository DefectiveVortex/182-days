import Foundation

/// Everything he sets: in onboarding (starting numbers, wake/sleep, evening time) and later in settings.
public struct DaysSettings: Codable, Sendable, Equatable {
    /// Day 1 of attempt 1. Nil until onboarding finishes.
    public var firstDay: DayKey?
    /// What he could do before day 1. The ghost on day 1, when there is no yesterday.
    public var startingNumbers: [PracticeID: Int]
    public var wake: ClockTime
    public var sleep: ClockTime
    /// "Close the day": the evening prompt for one line.
    public var eveningClose: ClockTime
    public var posturePingsPerDay: Int
    /// Most notifications on one day, must-day escalation excluded.
    public var dailyNotificationCap: Int
    public var practices: [Practice]

    public init(
        firstDay: DayKey? = nil,
        startingNumbers: [PracticeID: Int] = [:],
        wake: ClockTime = ClockTime(hour: 7),
        sleep: ClockTime = ClockTime(hour: 23, minute: 30),
        eveningClose: ClockTime = ClockTime(hour: 21, minute: 30),
        posturePingsPerDay: Int = 3,
        dailyNotificationCap: Int = 6,
        practices: [Practice] = Practice.defaults
    ) {
        self.firstDay = firstDay
        self.startingNumbers = startingNumbers
        self.wake = wake
        self.sleep = sleep
        self.eveningClose = eveningClose
        self.posturePingsPerDay = posturePingsPerDay
        self.dailyNotificationCap = dailyNotificationCap
        self.practices = practices
    }

    public var isOnboarded: Bool { firstDay != nil }

    public func practice(_ id: PracticeID) -> Practice? { practices.first { $0.id == id } }
}
