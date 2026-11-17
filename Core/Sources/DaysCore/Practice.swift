import Foundation

/// How a practice is measured.
public enum PracticeKind: String, Codable, Sendable, CaseIterable {
    /// Reps. The day's value is the sum of entries.
    case count
    /// A yes/no answer (posture: upright = 1, slouching = 0). The day's value is the number of yeses.
    case check
    /// Seconds. The day's value is the sum of entries.
    case duration
    /// 1…5. The day's value is the latest entry.
    case rating
}

public struct PracticeID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral,
    CodingKeyRepresentable, CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { rawValue = raw }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }

    public static let pushUps: PracticeID = "pushups"
    public static let sitUps: PracticeID = "situps"
    public static let posture: PracticeID = "posture"

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    public var codingKey: any CodingKey { Key(stringValue: rawValue) }
    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
}

/// Anything he does for himself. Push-ups, sit-ups and posture today; mental and emotional practices later.
public struct Practice: Identifiable, Hashable, Codable, Sendable {
    public var id: PracticeID
    public var name: String
    public var kind: PracticeKind
    /// Logging this keeps the day alive.
    public var countsForDay: Bool
    /// A mark he raises in settings. Not the headline: "beat yesterday" is.
    public var target: Int?

    public init(id: PracticeID, name: String, kind: PracticeKind, countsForDay: Bool = true, target: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.countsForDay = countsForDay
        self.target = target
    }

    public static let pushUps = Practice(id: .pushUps, name: "Push-ups", kind: .count, target: 50)
    public static let sitUps = Practice(id: .sitUps, name: "Sit-ups", kind: .count, target: 100)
    public static let posture = Practice(id: .posture, name: "Posture", kind: .check)
    public static let defaults: [Practice] = [.pushUps, .sitUps, .posture]

    /// The day's value from that day's entries for this practice (any order).
    public func value(of entries: [Entry]) -> Int {
        let mine = entries.filter { $0.practice == id }
        switch kind {
        case .count, .duration: return mine.reduce(0) { $0 + max(0, $1.value) }
        case .check: return mine.filter { $0.value > 0 }.count
        case .rating: return mine.max(by: { $0.at < $1.at })?.value ?? 0
        }
    }

    /// Whether these entries keep the day: ≥1 rep / second, or any check or rating answered.
    public func keepsDay(_ entries: [Entry]) -> Bool {
        guard countsForDay else { return false }
        let mine = entries.filter { $0.practice == id }
        switch kind {
        case .count, .duration: return mine.contains { $0.value > 0 }
        case .check, .rating: return !mine.isEmpty
        }
    }
}

/// One logged thing. Immutable once the day closes: only today's entries can be added or undone.
public struct Entry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var practice: PracticeID
    /// The logical day it was logged on, in the zone the phone was in at that moment.
    public var day: DayKey
    public var at: Date
    /// Reps, seconds, 1/0 for a check, 1…5 for a rating.
    public var value: Int

    public init(id: UUID = UUID(), practice: PracticeID, day: DayKey, at: Date, value: Int) {
        self.id = id
        self.practice = practice
        self.day = day
        self.at = at
        self.value = value
    }
}

extension Sequence where Element == Entry {
    /// Entries grouped by logical day.
    public func byDay() -> [DayKey: [Entry]] { Dictionary(grouping: self, by: \.day) }

    /// The days these entries keep, under the given practices.
    public func keptDays(practices: [Practice]) -> Set<DayKey> {
        var kept = Set<DayKey>()
        for (day, entries) in byDay() where practices.contains(where: { $0.keepsDay(entries) }) {
            kept.insert(day)
        }
        return kept
    }
}
