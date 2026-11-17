import DaysCore
import SwiftUI

/// The 182 view (design/A-HalfYear.dc.html): the half-year grid, the run, beat-yesterday,
/// totals with bests, and push-ups per day from the first day of the attempt to now.
struct HalfYearModel: Equatable, Sendable {
    enum Cell: Equatable, Sendable { case done, slip, today, todayOpen, future }

    struct Total: Equatable, Sendable {
        var name: String
        var total: Int
        var best: Int?
        /// "today", or a short date.
        var bestWhen: String?
    }

    /// 0 for the first half-year; after day 182 the grid starts the next one.
    var halfYear: Int = 0
    var dayInHalfYear: Int
    var cells: [Cell]
    var firstDate: Date
    var lastDate: Date

    var run: Int
    var slips: Int
    var beatDays: Int
    var beatOutOf: Int

    var totals: [Total]

    /// Push-ups per day of the attempt (at most the last 182); nil = a slip.
    var perDay: [Int?]
    var firstDayValue: Int
    /// Today so far (the last bar), and yesterday's count (nil on day 1 or after a slip).
    var todayValue: Int
    var yesterdayValue: Int?
}

extension HalfYearModel {
    var headline: String { "\(dayInHalfYear) IN. \(Ledger.halfYear - dayInHalfYear) TO GO." }
    var title: String { halfYear == 0 ? "The half-year" : "Half-year \(halfYear + 1)" }

    var slipLine: String {
        switch slips {
        case 0: "no slips"
        case 1: "1 slip, never two"
        default: "\(slips) slips, never two"
        }
    }

    var gridSummary: String {
        let done = cells.filter { $0 == .done || $0 == .today }.count
        let slipDays = cells.enumerated().filter { $0.element == .slip }.map { "\($0.offset + 1)" }
        var parts = ["182 days: \(done) done"]
        if !slipDays.isEmpty {
            parts.append("\(slipDays.count == 1 ? "1 slip, on day" : "\(slipDays.count) slips, on days") \(slipDays.joined(separator: ", "))")
        }
        parts.append("today is day \(dayInHalfYear)")
        parts.append("\(Ledger.halfYear - dayInHalfYear) still to come")
        return parts.joined(separator: ", ")
    }

    var perDayLine: String {
        let yesterday = yesterdayValue.map { "\($0) yesterday, " } ?? ""
        return run <= 1
            ? "Push-ups per day. \(todayValue) so far on day one."
            : "Push-ups per day. \(firstDayValue) on day one. \(yesterday)\(todayValue) so far today."
    }
}

// MARK: - From the store

extension HalfYearModel {
    @MainActor init(store: LogStore) {
        let stats = store.stats()
        let ledger = stats.ledger
        let clock = store.clock
        func date(_ d: DayKey) -> Date { clock.date(on: d, at: ClockTime(hour: 12)) }
        func short(_ d: DayKey) -> String {
            d == ledger.today ? "today" : date(d).formatted(.dateTime.day().month(.abbreviated))
        }

        let cells: [Cell] = stats.grid.map { c in
            if c.day == ledger.today { return ledger.todayKept ? .today : .todayOpen }
            switch c.outcome {
            case .kept: return .done
            case .slipped: return .slip
            case .open: return .todayOpen
            case .none: return .future
            }
        }

        let attemptDays = (0..<ledger.dayNumber).map { ledger.current.start.adding($0) }
        let closedSlips = attemptDays.dropLast().filter { !ledger.keptDays.contains($0) }.count
        let todayBeat = stats.grid.first { $0.day == ledger.today }?.beatYesterday ?? false

        let totals = stats.practices
            .filter { $0.practice.kind == .count || $0.practice.kind == .duration }
            .map { p in
                Total(name: p.practice.name, total: p.total, best: p.best?.value, bestWhen: p.best.map { short($0.day) })
            }

        let push = store.settings.practices.first { $0.id == .pushUps } ?? .pushUps
        let byDay = store.allEntries().filter { $0.practice == push.id }.byDay()
        let shown = attemptDays.suffix(Ledger.halfYear)
        let perDay: [Int?] = shown.map { d in
            d == ledger.today || ledger.keptDays.contains(d) ? push.value(of: byDay[d] ?? []) : nil
        }
        let todayValue = push.value(of: byDay[ledger.today] ?? [])
        let yesterday = ledger.today.previous
        let yesterdayValue = ledger.dayNumber > 1 && ledger.keptDays.contains(yesterday)
            ? push.value(of: byDay[yesterday] ?? []) : nil
        let pushStats = stats.practices.first { $0.practice.id == push.id }

        self.init(
            halfYear: ledger.halfYearIndex,
            dayInHalfYear: ledger.dayInHalfYear,
            cells: cells,
            firstDate: date(ledger.halfYearStart),
            lastDate: date(ledger.halfYearStart.adding(Ledger.halfYear - 1)),
            run: ledger.dayNumber,
            slips: closedSlips,
            beatDays: stats.beatYesterdayDays,
            beatOutOf: ledger.dayNumber - 1 + (todayBeat ? 1 : 0),
            totals: totals,
            perDay: perDay,
            firstDayValue: pushStats?.firstDayValue ?? 0,
            todayValue: todayValue,
            yesterdayValue: yesterdayValue
        )
    }
}

struct HalfYearScreen: View {
    @Environment(LogStore.self) private var store

    var body: some View {
        TimelineView(.everyMinute) { _ in
            HalfYearView(model: HalfYearModel(store: store))
        }
    }
}

// MARK: - View

struct HalfYearView: View {
    var model: HalfYearModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text.label(model.title)
                    Text(model.headline)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 8) {
                    DayGrid(cells: model.cells)
                        .accessibilityElement()
                        .accessibilityLabel(Text(model.gridSummary))
                        .accessibilityAddTraits(.isImage)
                    HStack {
                        Text(model.firstDate, format: .dateTime.day().month(.abbreviated))
                        Spacer()
                        Text(model.lastDate, format: .dateTime.day().month(.abbreviated))
                    }
                    .textStyle(.small)
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
                    Legend()
                }

                StatGrid(model: model)

                VStack(alignment: .leading, spacing: 10) {
                    Text.label("First day vs now")
                    PerDayBars(values: model.perDay, ghost: model.yesterdayValue)
                        .frame(height: 96)
                        .accessibilityElement()
                        .accessibilityLabel(Text(model.perDayLine))
                        .accessibilityAddTraits(.isImage)
                    Text(model.perDayLine)
                        .textStyle(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// 182 squares, seven to a column, filled column by column: a week per column.
private struct DayGrid: View {
    var cells: [HalfYearModel.Cell]
    static let rows = 7
    static let gap: CGFloat = 3

    var body: some View {
        let columns = (cells.count + Self.rows - 1) / Self.rows
        GeometryReader { geo in
            let side = min(14, (geo.size.width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns))
            Canvas { ctx, _ in
                for (i, cell) in cells.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(i / Self.rows) * (side + Self.gap),
                        y: CGFloat(i % Self.rows) * (side + Self.gap),
                        width: side, height: side
                    )
                    switch cell {
                    case .done: ctx.fill(Path(rect), with: .color(Palette.text))
                    case .today: ctx.fill(Path(rect), with: .color(Palette.accent))
                    case .todayOpen:
                        ctx.stroke(Path(rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(Palette.accent), lineWidth: 1.5)
                    case .slip:
                        ctx.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.accent), lineWidth: 1)
                    case .future: ctx.fill(Path(rect), with: .color(Palette.track))
                    }
                }
            }
        }
        .aspectRatio(gridAspect(columns: columns), contentMode: .fit)
    }

    /// Width : height for 10 pt cells and 3 pt gaps, so the grid keeps its shape at any width.
    private func gridAspect(columns: Int) -> CGFloat {
        let w = CGFloat(columns) * 10 + CGFloat(columns - 1) * Self.gap
        let h = CGFloat(Self.rows) * 10 + CGFloat(Self.rows - 1) * Self.gap
        return w / h
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 16) {
            item("Done") { Rectangle().fill(Palette.text).frame(width: 10, height: 10) }
            item("Slip") { Rectangle().strokeBorder(Palette.accent, lineWidth: 1).frame(width: 10, height: 10) }
            item("Today") { Rectangle().fill(Palette.accent).frame(width: 10, height: 10) }
        }
        .textStyle(.small)
        .foregroundStyle(Palette.muted)
        .accessibilityHidden(true)
    }

    private func item(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(title)
        }
    }
}

/// Two columns of figures split by hairlines, as in the design.
private struct StatGrid: View {
    var model: HalfYearModel

    var body: some View {
        let cells = statCells
        Grid(horizontalSpacing: Metrics.hairline, verticalSpacing: Metrics.hairline) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
                GridRow {
                    cells[i]
                    if i + 1 < cells.count { cells[i + 1] } else { Palette.background }
                }
            }
        }
        .background(Palette.rule)
        .border(Palette.rule, width: Metrics.hairline)
    }

    private var statCells: [StatCell] {
        var cells = [
            StatCell(label: "Run", value: "\(model.run) \(model.run == 1 ? "DAY" : "DAYS")", note: model.slipLine),
            StatCell(label: "Beat yesterday", value: "\(model.beatDays) / \(model.beatOutOf)", note: "days you did more",
                     spoken: "\(model.beatDays) of \(model.beatOutOf) days you did more than the day before"),
        ]
        for t in model.totals {
            let best = t.best.map { "best day \($0)" + (t.bestWhen.map { " (\($0))" } ?? "") } ?? "nothing yet"
            cells.append(StatCell(label: "\(t.name), all", value: t.total.formatted(), note: best))
        }
        return cells
    }
}

private struct StatCell: View {
    var label: String
    var value: String
    var note: String
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text.label(label)
            Text(value)
                .textStyle(.stat)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(note)
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken ?? "\(value), \(note)"))
    }
}

/// Push-ups per day: cream bars, a slip as an orange baseline. Today is unfinished, so it is drawn
/// the ghost way: an outline at yesterday's height, orange filled up to today's count.
private struct PerDayBars: View {
    var values: [Int?]
    var ghost: Int?

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let n = CGFloat(values.count)
            let gap: CGFloat = values.count > 60 ? 1 : 4
            let w = max(1, (size.width - gap * (n - 1)) / n)
            let top = CGFloat(max(1, (values.compactMap { $0 } + [ghost ?? 0]).max() ?? 1))
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * (w + gap)
                let last = i == values.count - 1
                guard let v else {
                    ctx.fill(Path(CGRect(x: x, y: size.height - 2, width: w, height: 2)), with: .color(Palette.accent))
                    continue
                }
                let h = max(2, (CGFloat(v) / top * size.height).rounded())
                if last {
                    if let ghost, ghost > 0 {
                        let gh = (CGFloat(ghost) / top * size.height).rounded()
                        ctx.stroke(Path(CGRect(x: x + 0.5, y: size.height - gh + 0.5, width: w - 1, height: gh - 1)),
                                   with: .color(Palette.ghost), lineWidth: 1)
                    }
                    if v > 0 {
                        ctx.fill(Path(CGRect(x: x, y: size.height - h, width: w, height: h)), with: .color(Palette.accent))
                    }
                    continue
                }
                ctx.fill(Path(CGRect(x: x, y: size.height - h, width: w, height: h)),
                         with: .color(v == 0 ? Palette.ghost : Palette.text))
            }
        }
    }
}

// MARK: - Preview

extension HalfYearModel {
    static let preview: HalfYearModel = {
        let push = [12, 14, 15, 15, 17, 18, 20, 20, 0, 21, 22, 22, 24, 25, 25, 27, 28, 28, 30, 30, 31, 34, 18]
        var cells: [Cell] = (1...182).map { $0 < 23 ? .done : ($0 == 23 ? .today : .future) }
        cells[8] = .slip
        return HalfYearModel(
            dayInHalfYear: 23, cells: cells,
            firstDate: .now.addingTimeInterval(-22 * 86400), lastDate: .now.addingTimeInterval(159 * 86400),
            run: 23, slips: 1, beatDays: 17, beatOutOf: 23,
            totals: [Total(name: "Push-ups", total: 509, best: 34, bestWhen: "today"),
                     Total(name: "Sit-ups", total: 958, best: 60, bestWhen: "today")],
            perDay: push.enumerated().map { $0.offset == 8 ? nil : $0.element },
            firstDayValue: 12, todayValue: 18, yesterdayValue: 34
        )
    }()
}

#Preview("182") { HalfYearView(model: .preview) }
