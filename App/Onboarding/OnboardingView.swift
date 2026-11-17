import DaysCore
import SwiftUI

/// First launch, three steps in the Tally language: the rule, the starting numbers (the first ghost),
/// and the shape of the day (wake, sleep, the evening close). Ends in `store.completeOnboarding`.
struct OnboardingView: View {
    @Environment(LogStore.self) private var store
    @State private var step: Step
    @State private var pushUps = 10
    @State private var sitUps = 20
    @State private var wake = ClockTime(hour: 7)
    @State private var sleep = ClockTime(hour: 23, minute: 30)
    @State private var close = ClockTime(hour: 21, minute: 30)
    @State private var editing: TimeField = .wake

    enum Step: Int, CaseIterable { case rule, numbers, day }
    enum TimeField: CaseIterable { case wake, close, sleep }

    init(step: Step = .rule) { _step = State(initialValue: step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    switch step {
                    case .rule: rule
                    case .numbers: numbers
                    case .day: day
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                if step != .rule {
                    OutlineButton(label: "Back") {
                        Text("Back").textStyle(.bodyMedium)
                    } action: {
                        withAnimation(.easeOut(duration: 0.2)) { step = Step(rawValue: step.rawValue - 1) ?? .rule }
                    }
                    .frame(width: 96)
                }
                FillButton(title: step == .day ? "BEGIN DAY 1" : "NEXT", label: step == .day ? "Begin day 1" : "Next") {
                    advance()
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Palette.background.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: step)
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            withAnimation(.easeOut(duration: 0.2)) { step = next }
        } else {
            store.completeOnboarding(
                startingNumbers: [.pushUps: pushUps, .sitUps: sitUps],
                wake: wake, sleep: sleep, eveningClose: close
            )
        }
    }

    /// Three tally-weight bars: done, current, to come.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Rectangle()
                    .fill(s.rawValue <= step.rawValue ? (s == step ? Palette.accent : Palette.text) : Palette.rule)
                    .frame(height: 2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    // MARK: Step 1, the rule

    private var rule: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("182").textStyle(.hero).foregroundStyle(Palette.text)
                Text("DAYS").textStyle(.dayNumber).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
            Text("Do one thing for yourself every day. Then do a little more than yesterday.")
                .textStyle(.blockTitle)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            RuleLine(number: "1", text: "A day counts when you log a set of anything or answer a posture check.")
            RuleLine(number: "2", text: "Miss a day and the next one is a must day.")
            RuleLine(number: "3", text: "Miss two in a row and the attempt ends. The next starts at day 1. Nothing is erased.")
            RuleLine(number: "4", text: "Only today can be logged. No filling in yesterday.")
        }
    }

    // MARK: Step 2, the first ghost

    private var numbers: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            Text("Where you start.")
                .textStyle(.blockTitle)
                .foregroundStyle(Palette.text)
            Text("Roughly what you could do today. It becomes day 1's ghost: the number to beat.")
                .textStyle(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            NumberField(label: "Push-ups", value: $pushUps)
            NumberField(label: "Sit-ups", value: $sitUps)
        }
    }

    // MARK: Step 3, the day

    private var day: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            Text("Your day.")
                .textStyle(.blockTitle)
                .foregroundStyle(Palette.text)
            Text("Reminders stay between waking and sleep. In the evening you close the day with one line.")
                .textStyle(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                timeRow(.wake, "Wake", wake)
                timeRow(.close, "Close the day", close)
                timeRow(.sleep, "Sleep", sleep)
            }
            DatePicker("", selection: timeBinding(editing), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .colorScheme(.dark)
        }
    }

    private func timeRow(_ field: TimeField, _ title: String, _ time: ClockTime) -> some View {
        let selected = editing == field
        return Button {
            editing = field
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text.label(title)
                Spacer()
                Text(time.description)
                    .textStyle(.blockTitle)
                    .foregroundStyle(selected ? Palette.accent : Palette.text)
            }
            .padding(.vertical, 10)
            .frame(minHeight: Metrics.minTarget)
            .overlay(alignment: .top) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(time.description))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func timeBinding(_ field: TimeField) -> Binding<Date> {
        let calendar = Calendar.current
        func get() -> ClockTime {
            switch field {
            case .wake: wake
            case .close: close
            case .sleep: sleep
            }
        }
        return Binding(
            get: {
                let t = get()
                return calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: calendar.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let c = calendar.dateComponents([.hour, .minute], from: date)
                let t = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
                switch field {
                case .wake: wake = t
                case .close: close = t
                case .sleep: sleep = t
                }
            }
        )
    }
}

private struct RuleLine: View {
    var number: String
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(number).textStyle(.ghostLabel).foregroundStyle(Palette.accent).frame(width: 14, alignment: .leading)
            Text(text).textStyle(.body).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Metrics.ruleGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
        .accessibilityElement(children: .combine)
    }
}

/// A big numeral with −5 / −1 / +1 / +5.
private struct NumberField: View {
    var label: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowGap) {
            HStack(alignment: .firstTextBaseline) {
                Text.label(label)
                Spacer()
                if value == 0 {
                    Text("starting from nothing")
                        .textStyle(.note)
                        .foregroundStyle(Palette.muted)
                }
            }
            Text("\(value)")
                .textStyle(.count)
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText(value: Double(value)))
                .accessibilityHidden(true)
            WeightedRow(weights: [1, 1, 1, 1], spacing: 8) {
                ForEach([-5, -1, 1, 5], id: \.self) { step in
                    OutlineButton(label: "\(step > 0 ? "Add" : "Remove") \(abs(step))") {
                        Text(step > 0 ? "+\(step)" : "−\(abs(step))").textStyle(.button)
                    } action: {
                        withAnimation(.snappy) { value = min(999, max(0, value + step)) }
                    }
                }
            }
        }
        .padding(.top, Metrics.ruleGap)
        .overlay(alignment: .top) { Rule() }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(999, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}

#Preview("Rule") { OnboardingView().environment(try! LogStore.inMemory()) }
#Preview("Numbers") { OnboardingView(step: .numbers).environment(try! LogStore.inMemory()) }
#Preview("Day") { OnboardingView(step: .day).environment(try! LogStore.inMemory()) }
