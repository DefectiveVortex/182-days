import DaysCore
import SwiftUI

/// The Log tab: every day of the attempt, newest first, with its numbers and the line written when
/// it was closed. Read-only: only today can be logged, and that happens on Today. Earlier attempts
/// follow under their own heading; history stays. Targets (the marks he raises) open from the header.
struct LogModel: Equatable {
    struct Row: Equatable, Identifiable {
        enum State: Equatable { case kept, slip, today, todayOpen }
        var id: Int // DayKey ordinal
        var dayNumber: Int
        var date: Date
        var state: State
        /// "18 push-ups", "posture 4 / 5"; empty on a slip or an untouched today.
        var numbers: [String]
        var line: String?
        var beatYesterday: Bool
    }

    struct Section: Equatable, Identifiable {
        var id: Int // attempt number
        /// nil for the attempt that is running.
        var title: String?
        var rows: [Row]
    }

    var title: String
    var headline: String
    var sections: [Section]
}

extension LogModel.Row {
    var accessibilityText: String {
        var parts = ["Day \(dayNumber), \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"]
        switch state {
        case .slip: parts.append("slipped, nothing logged")
        case .todayOpen: parts.append("today, nothing logged yet")
        case .today: parts.append("today")
        case .kept: break
        }
        if !numbers.isEmpty { parts.append(numbers.joined(separator: ", ")) }
        if beatYesterday { parts.append("beat yesterday") }
        if let line { parts.append("line: \(line)") }
        return parts.joined(separator: ". ")
    }
}

extension LogModel {
    @MainActor init(store: LogStore) {
        let ledger = store.stats().ledger
        let clock = store.clock
        let settings = store.settings
        let practices = settings.practices
        let byDay = store.allEntries().byDay()
        let journal = store.journal()

        func date(_ d: DayKey) -> Date { clock.date(on: d, at: ClockTime(hour: 12)) }

        func numbers(_ d: DayKey) -> [String] {
            let entries = byDay[d] ?? []
            return practices.compactMap { p in
                let mine = entries.filter { $0.practice == p.id }
                guard !mine.isEmpty else { return nil }
                let v = p.value(of: mine)
                switch p.kind {
                case .count: return v > 0 ? "\(v) \(p.name.lowercased())" : nil
                case .duration: return v > 0 ? "\(max(1, v / 60)) min \(p.name.lowercased())" : nil
                case .check: return "\(p.name.lowercased()) \(v) / \(mine.count)"
                case .rating: return "\(p.name.lowercased()) \(v) / 5"
                }
            }
        }

        /// Matches Today: any practice but a rating past its ghost (yesterday, or the starting number on day 1).
        func beat(_ d: DayKey, first: Bool) -> Bool {
            practices.contains { p in
                guard p.kind != .rating else { return false }
                let ghost = first ? (settings.startingNumbers[p.id] ?? 0) : p.value(of: byDay[d.previous] ?? [])
                return p.value(of: byDay[d] ?? []) > ghost
            }
        }

        var sections: [Section] = []
        for attempt in ledger.attempts.reversed() {
            let last = attempt.end ?? ledger.today
            guard attempt.start <= last else { continue }
            let days = (0...attempt.start.distance(to: last)).map { attempt.start.adding($0) }
            let rows: [Row] = days.enumerated().reversed().map { pair in
                let (i, d) = (pair.offset, pair.element)
                let kept = ledger.keptDays.contains(d)
                let state: Row.State = d == ledger.today ? (kept ? .today : .todayOpen) : (kept ? .kept : .slip)
                return Row(id: d.ordinal, dayNumber: i + 1, date: date(d), state: state,
                           numbers: kept ? numbers(d) : [], line: journal[d],
                           beatYesterday: kept && beat(d, first: i == 0))
            }
            let title: String? = attempt.failed
                ? "Attempt \(attempt.number) · ended day \(days.count) · \(attempt.keptDays) kept"
                : nil
            sections.append(Section(id: attempt.number, title: title, rows: rows))
        }

        let current = ledger.current
        let closed = current.start.distance(to: ledger.today) // days before today
        let keptBefore = (0..<max(0, closed)).filter { ledger.keptDays.contains(current.start.adding($0)) }.count
        let slips = closed - keptBefore
        let kept = keptBefore + (ledger.todayKept ? 1 : 0)
        let slipText = slips == 0 ? "NO SLIPS." : (slips == 1 ? "1 SLIP." : "\(slips) SLIPS.")
        self.init(
            title: current.number > 1 ? "The log · attempt \(current.number)" : "The log",
            headline: "\(kept) KEPT. \(slipText)",
            sections: sections
        )
    }
}

struct LogScreen: View {
    @Environment(LogStore.self) private var store
    @State private var showTargets = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            LogView(model: LogModel(store: store)) { showTargets = true }
        }
        .sheet(isPresented: $showTargets) { TargetsSheet() }
    }
}

// MARK: - View

struct LogView: View {
    var model: LogModel
    var openTargets: () -> Void = {}

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text.label(model.title)
                        Text(model.headline)
                            .textStyle(.headline)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button(action: openTargets) {
                        Text("Targets")
                            .textStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 14)
                            .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget)
                            .overlay(Rectangle().strokeBorder(Palette.outline, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint(Text("Raise the push-up and sit-up targets"))
                }
                .padding(.bottom, 10)

                HStack(spacing: 6) {
                    Rectangle().fill(Palette.accent).frame(width: 8, height: 8)
                    Text("beat yesterday").textStyle(.caption).foregroundStyle(Palette.muted)
                }
                .accessibilityHidden(true)
                .padding(.bottom, 8)

                ForEach(model.sections) { section in
                    if let title = section.title {
                        Text.label(title)
                            .padding(.top, 28)
                            .padding(.bottom, 4)
                    }
                    Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
                    ForEach(section.rows) { row in
                        LogRow(row: row)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct LogRow: View {
    var row: LogModel.Row
    @ScaledMetric(relativeTo: .title2) private var numberWidth: CGFloat = 48

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(row.dayNumber)")
                .textStyle(.blockTitle)
                .foregroundStyle(row.state == .slip ? Palette.ghost : Palette.text)
                .frame(width: numberWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .textStyle(.caption)
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    status
                }
                switch row.state {
                case .slip:
                    Text("Slipped. Nothing logged.")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.accent)
                case .todayOpen:
                    Text("Nothing yet today.")
                        .textStyle(.body)
                        .foregroundStyle(Palette.muted)
                case .kept, .today:
                    if !row.numbers.isEmpty {
                        Text(row.numbers.joined(separator: " · "))
                            .textStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let line = row.line {
                    Text("\u{201C}\(line)\u{201D}")
                        .textStyle(.body)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: Metrics.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.accessibilityText))
    }

    @ViewBuilder private var status: some View {
        if row.state == .today || row.state == .todayOpen {
            Text("TODAY").textStyle(.label).foregroundStyle(Palette.accent)
        } else if row.beatYesterday {
            Rectangle().fill(Palette.accent).frame(width: 8, height: 8)
        }
    }
}

// MARK: - Targets

/// Marks he raises: +5 or +10 at a time. Lowering is allowed but asks first.
/// Targets are not the headline; the ghost (yesterday) stays the thing to beat.
struct TargetsSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lowering: Practice?

    var body: some View {
        let practices = store.settings.practices.filter { $0.kind == .count }
        let stats = store.stats()
        let today = store.today()
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text.label("Targets")
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                        .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            Text("Marks you raise. The thing to beat is still yesterday.")
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            ForEach(practices) { p in
                let best = stats.practices.first { $0.practice.id == p.id }?.best?.value ?? 0
                let now = today.practices.first { $0.practice.id == p.id }?.value ?? 0
                TargetRow(practice: p, best: best, today: now,
                          raise: { set(p, to: ($0)) },
                          lower: { lowering = p })
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .confirmationDialog(
            lowering.map { "Lower \($0.name.lowercased()) to \(max(5, ($0.target ?? 5) - 5))?" } ?? "",
            isPresented: Binding(get: { lowering != nil }, set: { if !$0 { lowering = nil } }),
            titleVisibility: .visible,
            presenting: lowering
        ) { p in
            Button("Lower to \(max(5, (p.target ?? 5) - 5))", role: .destructive) {
                set(p, to: max(5, (p.target ?? 5) - 5))
            }
            Button("Keep \(p.target ?? 0)", role: .cancel) {}
        } message: { _ in
            Text("Your ghost doesn't change. Only the mark does.")
        }
    }

    private func set(_ p: Practice, to value: Int) {
        store.updateSettings { s in
            if let i = s.practices.firstIndex(where: { $0.id == p.id }) { s.practices[i].target = value }
        }
    }
}

private struct TargetRow: View {
    var practice: Practice
    var best: Int
    var today: Int
    var raise: (Int) -> Void
    var lower: () -> Void

    private var target: Int? { practice.target }
    /// With no target yet, the first raise starts from the best day, rounded up to the next 5.
    private var base: Int { target ?? (best / 5) * 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text.label(practice.name)
                    Text(target.map(String.init) ?? "No target")
                        .textStyle(.count)
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Text("best day \(best) · today \(today)")
                    .textStyle(.caption)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                FillButton(title: "+5", label: "Raise \(practice.name.lowercased()) target to \(base + 5)") { raise(base + 5) }
                FillButton(title: "+10", label: "Raise \(practice.name.lowercased()) target to \(base + 10)") { raise(base + 10) }
                OutlineButton(label: "Lower \(practice.name.lowercased()) target") {
                    Text("Lower").textStyle(.bodyMedium)
                } action: { lower() }
                .disabled((target ?? 0) <= 5)
                .opacity((target ?? 0) <= 5 ? 0.4 : 1)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: Metrics.hairline) }
        .animation(.snappy, value: target)
        .sensoryFeedback(.increase, trigger: target)
    }
}

#Preview("Log") {
    LogView(model: LogModel(
        title: "The log",
        headline: "22 KEPT. 1 SLIP.",
        sections: [LogModel.Section(id: 1, title: nil, rows: [
            .init(id: 3, dayNumber: 23, date: .now, state: .today, numbers: ["18 push-ups", "40 sit-ups", "posture 4 / 5"],
                  line: nil, beatYesterday: false),
            .init(id: 2, dayNumber: 22, date: .now.addingTimeInterval(-86400), state: .kept,
                  numbers: ["34 push-ups", "62 sit-ups", "posture 3 / 4"], line: "Did the second set without stopping.",
                  beatYesterday: true),
            .init(id: 1, dayNumber: 9, date: .now.addingTimeInterval(-14 * 86400), state: .slip, numbers: [], line: nil,
                  beatYesterday: false),
        ])]
    ))
}
