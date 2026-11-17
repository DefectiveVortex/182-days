import DaysCore
import SwiftData
import SwiftUI

/// Today as the app shows it: the demo scenario under `-demo`, otherwise the live store.
struct TodayScreen: View {
    @Environment(LogStore.self) private var store
    @State private var demo: PreviewTodayStore? = DemoData.scenario.map { PreviewTodayStore(DemoData.todayModel(for: $0)) }

    var body: some View {
        if let demo {
            TodayView(model: demo.model, actions: demo.actions)
        } else {
            LiveToday(store: store)
        }
    }
}

/// Practice ids used in `LogEntry.practiceID` until Core names its practices.
enum PracticeID {
    static let pushUps = "pushups"
    static let sitUps = "situps"
    /// value 1 = upright, 0 = slouching
    static let posture = "posture"
}

/// STAND-IN until Core publishes the rules engine: builds the Today model straight from LogEntry rows
/// (today vs yesterday sums, day number from the first entry, a must day when yesterday was empty).
/// Slips, attempts, targets and the schedule are not modelled here; Core replaces all of this.
private struct LiveToday: View {
    var store: LogStore
    @State private var revision = 0

    private static let postureChecksPerDay = 5

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = revision
            TodayView(model: model(at: context.date), actions: actions)
        }
    }

    private var clock: DayClock { DayClock() }

    private func entries(from day: DayKey) -> [LogEntry] {
        let from = day.ordinal
        let fetch = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.dayOrdinal >= from },
            sortBy: [SortDescriptor(\.at)]
        )
        return (try? store.context.fetch(fetch)) ?? []
    }

    private func firstDay() -> Int? {
        var fetch = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.dayOrdinal)])
        fetch.fetchLimit = 1
        return (try? store.context.fetch(fetch))?.first?.dayOrdinal
    }

    private func model(at now: Date) -> TodayModel {
        let today = clock.day(containing: now)
        let rows = entries(from: today.previous)
        func on(_ day: DayKey, _ id: String) -> [LogEntry] {
            rows.filter { $0.dayOrdinal == day.ordinal && $0.practiceID == id }
        }
        func count(_ id: String) -> TodayModel.Count {
            let t = on(today, id)
            return TodayModel.Count(
                today: t.reduce(0) { $0 + $1.value },
                ghost: on(today.previous, id).reduce(0) { $0 + $1.value },
                sets: t.map(\.value)
            )
        }
        let first = firstDay() ?? today.ordinal
        let yesterdayCounted = rows.contains { $0.dayOrdinal == today.previous.ordinal && ($0.practiceID == PracticeID.posture || $0.value > 0) }
        let answers: [PostureAnswer?] = on(today, PracticeID.posture).map { $0.value > 0 ? .upright : .slouching }
        let padded = answers + Array(repeating: nil, count: max(0, Self.postureChecksPerDay - answers.count))
        let yesterdayPosture = on(today.previous, PracticeID.posture)
        return TodayModel(
            day: max(1, today.ordinal - first + 1),
            date: now,
            kind: (today.ordinal > first && !yesterdayCounted) ? .must : .normal,
            pushUps: count(PracticeID.pushUps),
            sitUps: count(PracticeID.sitUps),
            posture: padded,
            postureYesterdayUpright: yesterdayPosture.isEmpty ? nil : yesterdayPosture.filter { $0.value > 0 }.count,
            block: nil
        )
    }

    private var actions: TodayActions {
        TodayActions(
            addPushUps: { log(PracticeID.pushUps, $0) },
            addSitUps: { log(PracticeID.sitUps, $0) },
            undoPushUps: { undo(PracticeID.pushUps) },
            undoSitUps: { undo(PracticeID.sitUps) },
            answerPosture: { log(PracticeID.posture, $0 == .upright ? 1 : 0) }
        )
    }

    private func log(_ id: String, _ value: Int) {
        let now = Date()
        store.context.insert(LogEntry(practiceID: id, day: clock.day(containing: now), at: now, value: value))
        try? store.context.save()
        revision += 1
    }

    /// Only today can be undone: removes today's newest entry for the practice.
    private func undo(_ id: String) {
        let today = clock.day(containing: Date())
        guard let last = entries(from: today).last(where: { $0.practiceID == id }) else { return }
        store.context.delete(last)
        try? store.context.save()
        revision += 1
    }
}
