import Foundation
import SwiftData
import WidgetKit
import DaysCore

/// The one place the app, the widgets and the intents read and write the log. Owner: Days 1.
///
/// Lives in the App Group container so every process sees the same data. All reads are computed by
/// DaysCore from the raw log; the store only persists. Only today can be written (no backfilling).
///
/// SwiftUI: read `store.today()`, `store.stats()` etc. inside `body`; every write bumps `revision`,
/// which those reads observe, so views refresh by themselves.
@MainActor
@Observable
public final class LogStore {
    public static let appGroup = "group.com.viraajrandhawa.182days"

    @ObservationIgnored public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    /// Bumps after every write (and on `refresh()`).
    public private(set) var revision = 0
    public private(set) var settings: DaysSettings
    public private(set) var schedule: WeekSchedule

    /// The clock. Overridable for `-demo` (a fixed "now" and zone); live it is the real time and current zone.
    @ObservationIgnored public var now: @Sendable () -> Date = { Date() }
    @ObservationIgnored public var timeZone: @Sendable () -> TimeZone = { TimeZone.current }
    /// In-memory demo store: never touches notifications or widgets.
    @ObservationIgnored public let isEphemeral: Bool

    @ObservationIgnored private var cache: (revision: Int, entries: [Entry], journal: [DayKey: String])?

    // MARK: Process-wide store

    private static var installed: LogStore?

    /// The store this process uses: the one the app installed (demo), else the on-disk one.
    public static var current: LogStore {
        if let installed { return installed }
        let store = (try? onDisk()) ?? (try! inMemory())
        installed = store
        return store
    }

    public static func install(_ store: LogStore) { installed = store }

    /// The store on disk, shared through the App Group.
    public static func onDisk() throws -> LogStore { try LogStore(url: storeURL()) }

    /// A throwaway store for `-demo`, previews and tests.
    public static func inMemory() throws -> LogStore { try LogStore(url: nil) }

    init(url: URL?) throws {
        let schema = Schema([LogEntry.self, JournalLine.self, StoredBlob.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let c = try ModelContainer(for: schema, configurations: config)
        container = c
        isEphemeral = url == nil
        let ctx = c.mainContext
        settings = StoredBlob.load(DaysSettings.self, key: StoredBlob.settingsKey, in: ctx) ?? DaysSettings()
        schedule = StoredBlob.load(WeekSchedule.self, key: StoredBlob.scheduleKey, in: ctx) ?? WeekSchedule()
    }

    /// The App Group container when signed with the entitlement; Application Support otherwise
    /// (unsigned simulator builds in CI).
    static func storeURL() throws -> URL {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Days.store")
    }

    // MARK: Reading

    public var clock: DayClock { DayClock(timeZone: timeZone()) }

    public var isOnboarded: Bool { settings.isOnboarded }

    /// Everything the Today screen shows: day number, must day, each practice against its ghost, the line.
    public func today() -> TodayState {
        let (entries, journal) = load()
        return DayBook.today(now: now(), clock: clock, settings: settings, entries: entries, journal: journal)
    }

    /// The 182 view.
    public func stats() -> Stats {
        let (entries, _) = load()
        return Stats(ledger: today().ledger, settings: settings, entries: entries)
    }

    /// One past (or the current) day, read-only: each practice against its own ghost, and its line.
    public func day(_ day: DayKey) -> (practices: [PracticeDay], line: String?) {
        let (entries, journal) = load()
        let byDay = entries.byDay()
        return (settings.practices.map { DayBook.practiceDay($0, on: day, byDay: byDay, settings: settings) },
                journal[day])
    }

    public func allEntries() -> [Entry] { load().entries }
    public func journal() -> [DayKey: String] { load().journal }

    // MARK: Writing (today only)

    /// Adds `value` (reps, seconds, 1/0, rating) to today. Returns nil if the value is not allowed.
    @discardableResult
    public func log(_ practice: PracticeID, _ value: Int) -> Entry? {
        guard let p = settings.practice(practice) else { return nil }
        switch p.kind {
        case .count, .duration: guard value > 0 else { return nil }
        case .check: guard value == 0 || value == 1 else { return nil }
        case .rating: guard (1...5).contains(value) else { return nil }
        }
        let t = now()
        let entry = Entry(practice: practice, day: today().day, at: t, value: value)
        context.insert(LogEntry(entry, timeZone: timeZone()))
        commit()
        return entry
    }

    /// A posture check answered.
    @discardableResult
    public func answerPosture(upright: Bool) -> Entry? { log(.posture, upright ? 1 : 0) }

    /// Removes today's most recent entry for `practice`. Returns what was removed.
    @discardableResult
    public func undoLast(_ practice: PracticeID) -> Entry? {
        guard let last = today()[practice]?.entries.last else { return nil }
        return remove(last.id) ? last : nil
    }

    /// Removes one of today's entries. Entries of closed days cannot be removed.
    @discardableResult
    public func remove(_ id: UUID) -> Bool {
        let todayOrdinal = today().day.ordinal
        let fd = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.id == id && $0.dayOrdinal == todayOrdinal })
        guard let row = try? context.fetch(fd).first else { return false }
        context.delete(row)
        commit()
        return true
    }

    /// Today's evening line: "What did you do better than yesterday?" Empty text clears it.
    public func setJournalLine(_ text: String) {
        let ordinal = today().day.ordinal
        let fd = FetchDescriptor<JournalLine>(predicate: #Predicate { $0.dayOrdinal == ordinal })
        let existing = (try? context.fetch(fd)) ?? []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let row = existing.first {
            if trimmed.isEmpty { context.delete(row) } else { row.text = trimmed; row.at = now() }
        } else if !trimmed.isEmpty {
            context.insert(JournalLine(dayOrdinal: ordinal, text: trimmed, at: now()))
        }
        commit()
    }

    // MARK: Settings

    /// Finishes onboarding: today becomes day 1. Asks for notification permission.
    public func completeOnboarding(
        startingNumbers: [PracticeID: Int], wake: ClockTime, sleep: ClockTime, eveningClose: ClockTime
    ) {
        updateSettings {
            $0.firstDay = DayBook.effectiveToday(now: now(), clock: clock, latestLogged: nil)
            $0.startingNumbers = startingNumbers
            $0.wake = wake
            $0.sleep = sleep
            $0.eveningClose = eveningClose
        }
        if !isEphemeral {
            Task { await NotificationScheduler.requestAuthorization(); await NotificationScheduler.replan(self) }
        }
    }

    /// Wake/sleep/evening times, posture pings, cap, targets. `firstDay` cannot be moved once set.
    public func updateSettings(_ change: (inout DaysSettings) -> Void) {
        var s = settings
        change(&s)
        if let locked = settings.firstDay { s.firstDay = locked }
        settings = s
        StoredBlob.save(s, key: StoredBlob.settingsKey, in: context)
        commit()
    }

    public func updateSchedule(_ change: (inout WeekSchedule) -> Void) {
        var w = schedule
        change(&w)
        schedule = w
        StoredBlob.save(w, key: StoredBlob.scheduleKey, in: context)
        commit()
    }

    /// Re-read after another process (a widget, an intent) wrote, and replan. Call when the app becomes active.
    public func refresh() {
        context.rollback()
        settings = StoredBlob.load(DaysSettings.self, key: StoredBlob.settingsKey, in: context) ?? settings
        schedule = StoredBlob.load(WeekSchedule.self, key: StoredBlob.scheduleKey, in: context) ?? schedule
        revision += 1
        afterWrite()
    }

    // MARK: Demo

    /// `-demo` only: replaces everything with sample data, past days included.
    public func seedForDemo(settings: DaysSettings, entries: [Entry], journal: [DayKey: String],
                            schedule: WeekSchedule = WeekSchedule()) {
        precondition(isEphemeral, "seedForDemo is for the in-memory demo store")
        try? context.delete(model: LogEntry.self)
        try? context.delete(model: JournalLine.self)
        for e in entries { context.insert(LogEntry(e, timeZone: timeZone())) }
        for (day, text) in journal { context.insert(JournalLine(dayOrdinal: day.ordinal, text: text, at: now())) }
        self.settings = settings
        self.schedule = schedule
        StoredBlob.save(settings, key: StoredBlob.settingsKey, in: context)
        StoredBlob.save(schedule, key: StoredBlob.scheduleKey, in: context)
        commit()
    }

    // MARK: Internals

    private func load() -> (entries: [Entry], journal: [DayKey: String]) {
        _ = revision // observed: views re-render after writes
        if let cache, cache.revision == revision { return (cache.entries, cache.journal) }
        let rows = (try? context.fetch(FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.at)]))) ?? []
        let lines = (try? context.fetch(FetchDescriptor<JournalLine>())) ?? []
        let entries = rows.map(\.entry)
        let journal = Dictionary(lines.map { (DayKey(ordinal: $0.dayOrdinal), $0.text) }, uniquingKeysWith: { a, _ in a })
        cache = (revision, entries, journal)
        return (entries, journal)
    }

    private func commit() {
        do { try context.save() } catch { print("LogStore save failed: \(error)") }
        revision += 1
        afterWrite()
    }

    private func afterWrite() {
        guard !isEphemeral else { return }
        WidgetCenter.shared.reloadAllTimelines()
        Task { await NotificationScheduler.replan(self) }
    }
}

// MARK: SwiftData models (persisted; change only with a migration plan)

@Model
public final class LogEntry {
    public var id: UUID = UUID()
    public var practiceID: String = ""
    public var dayOrdinal: Int = 0
    public var at: Date = Date.distantPast
    public var value: Int = 0
    /// The zone the phone was in, for the record (travel).
    public var timeZoneID: String = ""

    public init(_ e: Entry, timeZone: TimeZone) {
        id = e.id
        practiceID = e.practice.rawValue
        dayOrdinal = e.day.ordinal
        at = e.at
        value = e.value
        timeZoneID = timeZone.identifier
    }

    public var entry: Entry {
        Entry(id: id, practice: PracticeID(practiceID), day: DayKey(ordinal: dayOrdinal), at: at, value: value)
    }
}

@Model
public final class JournalLine {
    public var dayOrdinal: Int = 0
    public var text: String = ""
    public var at: Date = Date.distantPast

    public init(dayOrdinal: Int, text: String, at: Date) {
        self.dayOrdinal = dayOrdinal
        self.text = text
        self.at = at
    }
}

/// Small Codable values (settings, schedule) stored as JSON.
@Model
public final class StoredBlob {
    static let settingsKey = "settings"
    static let scheduleKey = "schedule"

    public var key: String = ""
    public var data: Data = Data()

    init(key: String, data: Data) {
        self.key = key
        self.data = data
    }

    static func load<T: Decodable>(_ type: T.Type, key: String, in ctx: ModelContext) -> T? {
        let fd = FetchDescriptor<StoredBlob>(predicate: #Predicate { $0.key == key })
        guard let row = try? ctx.fetch(fd).first else { return nil }
        return try? JSONDecoder().decode(T.self, from: row.data)
    }

    static func save<T: Encodable>(_ value: T, key: String, in ctx: ModelContext) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let fd = FetchDescriptor<StoredBlob>(predicate: #Predicate { $0.key == key })
        if let row = try? ctx.fetch(fd).first { row.data = data } else { ctx.insert(StoredBlob(key: key, data: data)) }
    }
}
