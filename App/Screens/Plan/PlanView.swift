import DaysCore
import SwiftUI

/// The Plan tab: the week hour by hour. Pick a weekday, see its blocks on a timeline from waking
/// to sleep, tap a block to edit it or an empty hour to add one, and copy a day to other days.
/// Block starts can notify (On it / Skip); Core's planner reads `notify` from the schedule.
struct PlanScreen: View {
    @Environment(LogStore.self) private var store
    @State private var weekday: Int?
    @State private var editing: Draft?
    @State private var copying = false

    struct Draft: Identifiable {
        var block: ScheduleBlock
        var isNew: Bool
        var id: UUID { block.id }
    }

    var body: some View {
        let today = store.clock.day(containing: store.now()).weekday
        let selected = weekday ?? today
        VStack(alignment: .leading, spacing: 0) {
            PlanHeader(weekday: selected, blocks: store.schedule.blocks(on: selected))
                .padding(.bottom, 14)
            WeekdayStrip(selected: selected, today: today, schedule: store.schedule) { weekday = $0 }
                .padding(.bottom, 14)
            ScrollView {
                DayTimeline(
                    blocks: store.schedule.blocks(on: selected),
                    wake: store.settings.wake,
                    sleep: store.settings.sleep,
                    now: selected == today ? nowTime : nil,
                    open: { editing = Draft(block: $0, isNew: false) },
                    add: { editing = Draft(block: newBlock(weekday: selected, at: $0), isNew: true) }
                )
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                OutlineButton(label: "Copy this day to other days") {
                    Text("Copy day").textStyle(.bodyMedium)
                } action: { copying = true }
                .frame(width: 120)
                FillButton(title: "ADD BLOCK", label: "Add a block") {
                    editing = Draft(block: newBlock(weekday: selected, at: nextFreeStart(selected)), isNew: true)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Palette.background.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: selected)
        .sheet(item: $editing) { draft in
            BlockEditor(
                block: draft.block,
                isNew: draft.isNew,
                practices: store.settings.practices,
                save: { block in store.updateSchedule { $0.upsert(block) }; editing = nil },
                delete: { id in store.updateSchedule { $0.remove(id: id) }; editing = nil },
                cancel: { editing = nil }
            )
        }
        .sheet(isPresented: $copying) {
            CopyDaySheet(source: selected) { targets in
                store.updateSchedule { $0.copyDay(selected, to: targets) }
                copying = false
            } cancel: { copying = false }
        }
    }

    private var nowTime: ClockTime {
        let c = store.clock.calendar.dateComponents([.hour, .minute], from: store.now())
        return ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private func newBlock(weekday: Int, at start: ClockTime) -> ScheduleBlock {
        ScheduleBlock(weekday: weekday, start: start, minutes: 60, title: "")
    }

    /// The first whole hour after the day's last block, or after waking.
    private func nextFreeStart(_ weekday: Int) -> ClockTime {
        let last = store.schedule.blocks(on: weekday).map(\.end.minuteOfLogicalDay).max()
            ?? store.settings.wake.minuteOfLogicalDay
        let rounded = min(((last + 59) / 60) * 60, 1380)
        return ClockTime(minuteOfLogicalDay: rounded)
    }
}

// MARK: - Header and weekday strip

private struct PlanHeader: View {
    var weekday: Int
    var blocks: [ScheduleBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text.label("The week")
            HStack(alignment: .firstTextBaseline) {
                Text(Weekdays.name(weekday).uppercased())
                    .textStyle(.headline)
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(summary)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard !blocks.isEmpty else { return "Nothing planned" }
        let minutes = blocks.reduce(0) { $0 + $1.minutes }
        let time = minutes % 60 == 0 ? "\(minutes / 60) h" : (minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min")
        return "\(blocks.count) \(blocks.count == 1 ? "block" : "blocks") · \(time)"
    }
}

enum Weekdays {
    /// 1 = Sunday … 7 = Saturday, in the user's week order.
    static var ordered: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func name(_ weekday: Int) -> String { Calendar.current.weekdaySymbols[weekday - 1] }
    static func short(_ weekday: Int) -> String { Calendar.current.shortWeekdaySymbols[weekday - 1] }
    static func initial(_ weekday: Int) -> String { Calendar.current.veryShortWeekdaySymbols[weekday - 1] }
}

private struct WeekdayStrip: View {
    var selected: Int
    var today: Int
    var schedule: WeekSchedule
    var pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Weekdays.ordered, id: \.self) { day in
                let isSelected = day == selected
                Button { pick(day) } label: {
                    VStack(spacing: 4) {
                        Text(Weekdays.initial(day))
                            .textStyle(.button)
                            .foregroundStyle(isSelected ? Palette.onFill : Palette.text)
                        Rectangle()
                            .fill(day == today ? Palette.accent : .clear)
                            .frame(width: 14, height: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTarget + 4)
                    .background(isSelected ? Palette.text : .clear)
                    .overlay(Rectangle().strokeBorder(isSelected ? .clear : Palette.rule, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Weekdays.name(day)))
                .accessibilityValue(Text(accessibilityValue(day)))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func accessibilityValue(_ day: Int) -> String {
        let n = schedule.blocks(on: day).count
        let blocks = n == 0 ? "nothing planned" : "\(n) \(n == 1 ? "block" : "blocks")"
        return day == today ? "today, \(blocks)" : blocks
    }
}

// MARK: - Timeline

private struct DayTimeline: View {
    var blocks: [ScheduleBlock]
    var wake: ClockTime
    var sleep: ClockTime
    var now: ClockTime?
    var open: (ScheduleBlock) -> Void
    var add: (ClockTime) -> Void

    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 56
    private let labelWidth: CGFloat = 48

    /// Whole hours (logical minutes) from waking, or the first block, to sleep, or the last block's end.
    private var range: (start: Int, end: Int) {
        let first = min(wake.minuteOfLogicalDay, blocks.map(\.start.minuteOfLogicalDay).min() ?? .max)
        let last = max(sleep.minuteOfLogicalDay, blocks.map(\.end.minuteOfLogicalDay).max() ?? 0)
        let start = max(0, (first / 60) * 60)
        let end = min(1440, max(start + 60, ((last + 59) / 60) * 60))
        return (start, end)
    }

    var body: some View {
        let r = range
        let hours = Array(stride(from: r.start, to: r.end, by: 60))
        let perMinute = hourHeight / 60
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { m in
                    HourRow(time: ClockTime(minuteOfLogicalDay: m), labelWidth: labelWidth)
                        .frame(height: hourHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { add(ClockTime(minuteOfLogicalDay: m)) }
                }
            }
            .accessibilityHidden(true)

            ForEach(blocks) { block in
                let y = CGFloat(block.start.minuteOfLogicalDay - r.start) * perMinute
                BlockCard(block: block, compact: CGFloat(block.minutes) * perMinute < 48) { open(block) }
                    .frame(height: max(CGFloat(block.minutes) * perMinute - 2, 30), alignment: .top)
                    .padding(.leading, labelWidth)
                    .offset(y: y + 1)
            }

            if let now, now.minuteOfLogicalDay >= r.start, now.minuteOfLogicalDay < r.end {
                let y = CGFloat(now.minuteOfLogicalDay - r.start) * perMinute
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.accent).frame(width: 6, height: 6)
                    Rectangle().fill(Palette.accent).frame(height: 1.5)
                }
                .padding(.leading, labelWidth - 6)
                .offset(y: y - 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(height: CGFloat(hours.count) * hourHeight, alignment: .top)
    }
}

private struct HourRow: View {
    var time: ClockTime
    var labelWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(time.description)
                .textStyle(.small)
                .foregroundStyle(Palette.muted)
                .frame(width: labelWidth, alignment: .leading)
                .offset(y: -1)
            Rule()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct BlockCard: View {
    var block: ScheduleBlock
    var compact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(block.practice == nil ? Palette.text : Palette.accent)
                    .frame(width: 3)
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title
                        Text(times).textStyle(.small).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 5)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        Text(times).textStyle(.caption).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 4)
                if block.notify {
                    Image(systemName: "bell")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, compact ? 7 : 10)
                        .padding(.trailing, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.track)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(block.title.isEmpty ? "Untitled block" : block.title))
        .accessibilityValue(Text("\(times)\(block.notify ? ", asks at the start" : "")"))
        .accessibilityHint(Text("Edit"))
    }

    private var title: some View {
        Text(block.title.isEmpty ? "Untitled" : block.title)
            .textStyle(.bodyMedium)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
    }

    private var times: String { "\(block.start.description)–\(block.end.description)" }
}

// MARK: - Block editor

private struct BlockEditor: View {
    @State var block: ScheduleBlock
    var isNew: Bool
    var practices: [Practice]
    var save: (ScheduleBlock) -> Void
    var delete: (UUID) -> Void
    var cancel: () -> Void

    @FocusState private var titleFocused: Bool
    private static let lengths = [15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text.label(isNew ? "New block · \(Weekdays.name(block.weekday))" : Weekdays.name(block.weekday))
                Spacer()
                Button("Cancel", action: cancel)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.muted)
                    .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .trailing)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    TextField("", text: $block.title, prompt: Text("What it's for").foregroundStyle(Palette.ghost))
                        .textStyle(.blockTitle)
                        .foregroundStyle(Palette.text)
                        .tint(Palette.accent)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rule() }
                        .accessibilityLabel(Text("Title"))

                    EditorSection("Starts") {
                        DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, maxHeight: 150)
                            .clipped()
                            .colorScheme(.dark)
                            .accessibilityLabel(Text("Start time"))
                    }

                    EditorSection("Length") {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Self.lengths, id: \.self) { m in
                                Chip(title: m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"),
                                     selected: block.minutes == m) { block.minutes = m }
                            }
                        }
                        Text("Ends \(block.end.description)").textStyle(.caption).foregroundStyle(Palette.muted)
                    }

                    EditorSection("For") {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            Chip(title: "Nothing in particular", selected: block.practice == nil) { block.practice = nil }
                            ForEach(practices) { p in
                                Chip(title: p.name, selected: block.practice == p.id) { block.practice = p.id }
                            }
                        }
                    }

                    Toggle(isOn: $block.notify) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask at the start").textStyle(.bodyMedium).foregroundStyle(Palette.text)
                            Text("A notification with On it / Skip.").textStyle(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    .tint(Palette.accent)
                    .padding(.top, Metrics.ruleGap)
                    .overlay(alignment: .top) { Rule() }
                }
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 8) {
                if !isNew {
                    OutlineButton(label: "Delete block") {
                        Text("Delete").textStyle(.bodyMedium).foregroundStyle(Palette.accent)
                    } action: { delete(block.id) }
                    .frame(width: 96)
                }
                FillButton(title: isNew ? "ADD" : "SAVE", label: isNew ? "Add block" : "Save block") {
                    var b = block
                    b.title = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(b)
                }
                .disabled(block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: block.minutes)
        .onAppear { if isNew { titleFocused = true } }
    }

    private var startBinding: Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                calendar.date(bySettingHour: block.start.hour, minute: block.start.minute, second: 0,
                              of: calendar.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let c = calendar.dateComponents([.hour, .minute], from: date)
                block.start = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }
}

/// A labelled group in the editor: a label over its content, under a hairline.
private struct EditorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowGap) {
            Text.label(title)
            content
        }
        .padding(.top, Metrics.ruleGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
    }
}

/// A square choice: outlined, or filled cream when chosen.
private struct Chip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.bodyMedium)
                .foregroundStyle(selected ? Palette.onFill : Palette.text)
                .padding(.horizontal, 14)
                .frame(minHeight: Metrics.minTarget)
                .background(selected ? Palette.text : .clear)
                .overlay(Rectangle().strokeBorder(selected ? .clear : Palette.outline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Copy a day

private struct CopyDaySheet: View {
    var source: Int
    var copy: ([Int]) -> Void
    var cancel: () -> Void
    @State private var targets: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            HStack {
                Text.label("Copy \(Weekdays.name(source)) to")
                Spacer()
                Button("Cancel", action: cancel)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.muted)
                    .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .trailing)
            }
            VStack(spacing: 0) {
                ForEach(Weekdays.ordered.filter { $0 != source }, id: \.self) { day in
                    let on = targets.contains(day)
                    Button {
                        if on { targets.remove(day) } else { targets.insert(day) }
                    } label: {
                        HStack {
                            Text(Weekdays.name(day)).textStyle(.body).foregroundStyle(Palette.text)
                            Spacer()
                            Rectangle()
                                .fill(on ? Palette.text : .clear)
                                .overlay(Rectangle().strokeBorder(on ? .clear : Palette.outline, lineWidth: 1))
                                .frame(width: 18, height: 18)
                        }
                        .frame(minHeight: Metrics.minTarget + 4)
                        .overlay(alignment: .top) { Rule() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            Text("Their blocks are replaced by \(Weekdays.name(source))'s.")
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                OutlineButton(label: "Select every other day") {
                    Text("All").textStyle(.bodyMedium)
                } action: { targets = Set(Weekdays.ordered.filter { $0 != source }) }
                .frame(width: 96)
                FillButton(title: "COPY", label: "Copy") { copy(Array(targets)) }
                    .disabled(targets.isEmpty)
                    .opacity(targets.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .sensoryFeedback(.selection, trigger: targets)
    }
}

#Preview("Plan") {
    PlanScreen().environment(try! LogStore.inMemory())
}
