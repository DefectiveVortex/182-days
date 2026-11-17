import Foundation
import SwiftData
import DaysCore

/// The one place the app, the widgets and the intents read and write the log.
/// Lives in the App Group container so every process sees the same data.
@MainActor
@Observable
public final class LogStore {
    public static let appGroup = "group.com.viraajrandhawa.182days"

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    /// The store on disk, shared through the App Group.
    public static func onDisk() throws -> LogStore {
        try LogStore(url: storeURL())
    }

    /// A throwaway store for `-demo`, previews and tests.
    public static func inMemory() throws -> LogStore {
        try LogStore(url: nil)
    }

    init(url: URL?) throws {
        let schema = Schema(LogStore.models)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        container = try ModelContainer(for: schema, configurations: config)
    }

    static let models: [any PersistentModel.Type] = [LogEntry.self]

    /// The App Group container when signed with the entitlement; Application Support otherwise
    /// (unsigned simulator builds in CI).
    static func storeURL() throws -> URL {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Days.store")
    }
}

@Model
public final class LogEntry {
    public var id: UUID = UUID()
    public var practiceID: String = ""
    public var dayOrdinal: Int = 0
    public var at: Date = Date.distantPast
    public var value: Int = 0

    public init(practiceID: String, day: DayKey, at: Date, value: Int) {
        self.practiceID = practiceID
        self.dayOrdinal = day.ordinal
        self.at = at
        self.value = value
    }
}
