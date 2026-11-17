import Foundation

/// One block of the hour-by-hour week. Belongs to a logical day, so 01:00 sits at the end of the evening before.
public struct ScheduleBlock: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// 1 = Sunday … 7 = Saturday, of the logical day.
    public var weekday: Int
    public var start: ClockTime
    public var minutes: Int
    public var title: String
    /// The practice this block is for, if any.
    public var practice: PracticeID?
    /// Notify at the start: On it / Skip.
    public var notify: Bool

    public init(id: UUID = UUID(), weekday: Int, start: ClockTime, minutes: Int, title: String,
                practice: PracticeID? = nil, notify: Bool = true) {
        self.id = id
        self.weekday = weekday
        self.start = start
        self.minutes = minutes
        self.title = title
        self.practice = practice
        self.notify = notify
    }

    public var end: ClockTime { ClockTime(minuteOfLogicalDay: min(start.minuteOfLogicalDay + minutes, 1439)) }
}

public struct WeekSchedule: Codable, Sendable, Equatable {
    public var blocks: [ScheduleBlock]

    public init(blocks: [ScheduleBlock] = []) { self.blocks = blocks }

    /// A weekday's blocks in day order (04:00 first).
    public func blocks(on weekday: Int) -> [ScheduleBlock] {
        blocks.filter { $0.weekday == weekday }.sorted { $0.start < $1.start }
    }

    public func blocks(on day: DayKey) -> [ScheduleBlock] { blocks(on: day.weekday) }

    /// Replaces each target weekday's blocks with copies of `weekday`'s (new ids).
    public mutating func copyDay(_ weekday: Int, to targets: [Int]) {
        let source = blocks(on: weekday)
        for t in Set(targets) where t != weekday {
            blocks.removeAll { $0.weekday == t }
            blocks += source.map {
                ScheduleBlock(weekday: t, start: $0.start, minutes: $0.minutes, title: $0.title,
                              practice: $0.practice, notify: $0.notify)
            }
        }
    }

    public mutating func upsert(_ block: ScheduleBlock) {
        if let i = blocks.firstIndex(where: { $0.id == block.id }) { blocks[i] = block } else { blocks.append(block) }
    }

    public mutating func remove(id: UUID) { blocks.removeAll { $0.id == id } }
}
