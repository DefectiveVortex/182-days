import DaysCore
import SwiftUI

/// Today as the app shows it: Core's TodayState from the store, mapped to the screen model.
struct TodayScreen: View {
    @Environment(LogStore.self) private var store
    @State private var writing = LaunchScreen.argument == "letter"
    @State private var photographing = LaunchScreen.argument == "camera"

    var body: some View {
        // Reading the store inside body observes its revision; a minute timeline rolls the day at 04:00.
        TimelineView(.everyMinute) { _ in
            TodayView(model: TodayModel(store: store), actions: actions)
        }
        .sheet(isPresented: $writing) { LetterSheet() }
        .fullScreenCover(isPresented: $photographing) { PostureCameraSheet() }
        .onChange(of: AppRoute.shared.pending, initial: true) { _, pending in
            switch pending {
            case "camera":
                writing = false
                photographing = true
            case "letter":
                photographing = false
                writing = true
            default: return
            }
            AppRoute.shared.pending = nil
        }
    }

    private var actions: TodayActions {
        var a = TodayActions.live(store)
        a.writeLetter = { writing = true }
        a.takePhoto = { photographing = true }
        return a
    }
}

extension TodayActions {
    @MainActor static func live(_ store: LogStore) -> TodayActions {
        TodayActions(
            addPushUps: { _ = store.log(.pushUps, $0) },
            addSitUps: { _ = store.log(.sitUps, $0) },
            undoPushUps: { _ = store.undoLast(.pushUps) },
            undoSitUps: { _ = store.undoLast(.sitUps) },
            answerPosture: { _ = store.answerPosture(upright: $0 == .upright) }
        )
    }
}

extension TodayModel {
    @MainActor init(store: LogStore) {
        let state = store.today()
        let ledger = state.ledger
        let clock = store.clock
        let today = state.day

        // Slips in this attempt: closed days since it started that weren't kept.
        let closed = ledger.current.start.distance(to: today)
        let slips = (0..<max(closed, 0)).map { ledger.current.start.adding($0) }.filter { !ledger.keptDays.contains($0) }

        func count(_ id: PracticeID) -> Count {
            guard let p = state[id] else { return Count(today: 0, ghost: 0) }
            return Count(today: p.value, ghost: p.ghost, sets: p.entries.map(\.value))
        }
        let sit = state[.sitUps]
        let sitScale = Int((Double(max(sit?.target ?? 100, sit?.ghost ?? 0, sit?.value ?? 0)) * 1.1).rounded(.up))

        let postureEntries = state[.posture]?.entries ?? []
        var answers: [PostureAnswer?] = postureEntries.map { $0.value > 0 ? .upright : .slouching }
        answers += Array(repeating: nil, count: max(0, store.settings.posturePingsPerDay - answers.count))
        let yesterday = store.day(today.previous).practices.first { $0.id == .posture }

        let ended = ledger.attemptEndedYesterday
        self.init(
            day: state.dayNumber,
            span: Ledger.halfYear * (ledger.halfYearIndex + 1),
            date: state.now,
            kind: state.isMustDay ? .must : .normal,
            attempt: state.attemptNumber,
            slipsThisAttempt: slips.count,
            lastSlipDaysAgo: slips.last.map { $0.distance(to: today) },
            endedAttempt: ended.map { EndedAttempt(number: $0.number, length: $0.length) },
            pushUps: count(.pushUps),
            sitUps: count(.sitUps),
            sitUpScale: sitScale,
            posture: answers,
            postureYesterdayUpright: (yesterday?.answered ?? 0) > 0 ? yesterday?.value : nil,
            block: Self.block(schedule: store.schedule, day: today, now: state.now, clock: clock)
        )
        letterDue = LetterSummary.dueToday(store)
        if letterDue != nil {
            letterOpens = clock.date(on: LetterSummary.opensForToday(store), at: ClockTime(hour: 12))
        }
        photoDue = store.isPhotoDay
        photoWeek = PhotoSummary.weekToday(store)
    }

    /// The block running now and the one after it, if the schedule has one.
    static func block(schedule: WeekSchedule, day: DayKey, now: Date, clock: DayClock) -> Block? {
        let blocks = schedule.blocks(on: day).sorted { $0.start.minuteOfLogicalDay < $1.start.minuteOfLogicalDay }
        let c = clock.calendar.dateComponents([.hour, .minute], from: now)
        let minute = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0).minuteOfLogicalDay
        guard let i = blocks.firstIndex(where: {
            $0.start.minuteOfLogicalDay <= minute && minute < $0.end.minuteOfLogicalDay
        }) else { return nil }
        let block = blocks[i]
        return Block(
            title: block.title,
            until: clock.date(on: day, at: block.end),
            next: blocks.indices.contains(i + 1) ? blocks[i + 1].title : nil
        )
    }
}
