import SwiftUI

/// Today, built to design/AC-Today.dc.html: the day count, the must banner or the run status,
/// push-ups on the ghost tally, sit-ups on the ghost bar, posture, and the current block.
struct TodayView: View {
    var model: TodayModel
    var actions: TodayActions

    @State private var customSet: CustomSetTarget?
    @State private var askingPosture = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                header
                if let ended = model.endedAttempt {
                    Banner(
                        title: "ATTEMPT \(ended.number) ENDED AT \(ended.length) DAYS.",
                        line: "Two slips in a row. Attempt \(ended.number + 1) starts today, at day 1. The history stays."
                    )
                } else if model.kind == .must {
                    Banner(title: "YESTERDAY WAS YOUR SLIP.", line: "Today can't be. One set of anything keeps the run alive.")
                } else {
                    status
                }
                pushUps
                sitUps
                posture
                if let block = model.block { NowBlock(block: block) }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(item: $customSet) { target in
            LogSetSheet(title: target.title) { amount in
                switch target {
                case .pushUps: actions.addPushUps(amount)
                case .sitUps: actions.addSitUps(amount)
                }
            }
        }
        .confirmationDialog("Posture check", isPresented: $askingPosture, titleVisibility: .visible) {
            Button("Upright") { actions.answerPosture(.upright) }
            Button("Slouching") { actions.answerPosture(.slouching) }
        } message: {
            Text("How are you sitting right now?")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("DAY \(model.day)").textStyle(.dayNumber).foregroundStyle(Palette.text)
                Text("/ \(model.span)").textStyle(.dayTotal).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Day \(model.day) of \(model.span)"))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(model.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private var status: some View {
        Text(model.statusLine)
            .textStyle(.caption)
            .foregroundStyle(Palette.muted)
    }

    // MARK: Push-ups

    private var pushUps: some View {
        let note = model.pushUps.note(kind: model.kind)
        let ghost = model.pushUps.ghost
        return RuledSection {
            HStack(alignment: .firstTextBaseline) {
                Text.label("Push-ups")
                Spacer(minLength: 8)
                NoteText(text: note.text, ahead: note.ahead)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(model.pushUps.today)")
                    .textStyle(.hero)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: Double(model.pushUps.today)))
                Text(model.pushUps.ghostLabel)
                    .textStyle(.ghostLabel)
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Push-ups"))
            .accessibilityValue(Text("\(model.pushUps.today) today, \(model.pushUps.ghost) yesterday. \(note.text)"))
            GhostTally(today: model.pushUps.today, ghost: model.pushUps.ghost)
                .accessibilityHidden(true)
            WeightedRow(weights: [1, 1, 1.3], spacing: 8) {
                FillButton(title: "+5", label: "Add 5 push-ups") { actions.addPushUps(5) }
                FillButton(title: "+10", label: "Add 10 push-ups") { actions.addPushUps(10) }
                OutlineButton(label: "Log a set of push-ups") {
                    Text("Log a set").textStyle(.bodyMedium)
                } action: {
                    customSet = .pushUps
                }
            }
            .padding(.top, 2)
            .contextMenu { undoMenu(sets: model.pushUps.sets, noun: "push-ups", undo: actions.undoPushUps) }
        }
        .sensoryFeedback(trigger: model.pushUps.today) { old, new in
            Self.feedback(old: old, new: new, ghost: ghost)
        }
    }

    // MARK: Sit-ups

    private var sitUps: some View {
        let note = model.sitUps.note(kind: model.kind)
        let ghost = model.sitUps.ghost
        return RuledSection {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text.label("Sit-ups")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(model.sitUps.today)")
                            .textStyle(.count)
                            .foregroundStyle(Palette.text)
                            .contentTransition(.numericText(value: Double(model.sitUps.today)))
                        NoteText(text: note.text, ahead: note.ahead)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Sit-ups"))
                    .accessibilityValue(Text("\(model.sitUps.today) today, \(model.sitUps.ghost) yesterday. \(note.text)"))
                }
                Spacer(minLength: 8)
                OutlineButton(label: "Add 10 sit-ups") {
                    Text("+10").textStyle(.button)
                } action: {
                    actions.addSitUps(10)
                }
                .frame(width: 72)
                .contextMenu {
                    Button("Log a set…") { customSet = .sitUps }
                    undoMenu(sets: model.sitUps.sets, noun: "sit-ups", undo: actions.undoSitUps)
                }
            }
            GhostBar(today: model.sitUps.today, ghost: model.sitUps.ghost, scale: model.sitUpScale)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(trigger: model.sitUps.today) { old, new in
            Self.feedback(old: old, new: new, ghost: ghost)
        }
    }

    // MARK: Posture

    private var posture: some View {
        let line = model.postureLine
        return RuledSection {
            Button {
                askingPosture = true
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text.label("Posture")
                        postureText(line).textStyle(.body)
                    }
                    Spacer(minLength: 8)
                    PostureMarks(answers: model.posture)
                }
                .frame(minHeight: Metrics.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Posture"))
            .accessibilityValue(Text([line.main, line.yesterday].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHint(Text("Answer a posture check now"))
        }
        .sensoryFeedback(.selection, trigger: model.posture)
    }

    // MARK: Helpers

    private func postureText(_ line: (main: String, yesterday: String?)) -> Text {
        let main = Text(line.main).foregroundStyle(Palette.text)
        guard let yesterday = line.yesterday else { return main }
        return Text("\(main)\(Text(" · \(yesterday)").foregroundStyle(Palette.muted))")
    }

    @ViewBuilder
    private func undoMenu(sets: [Int], noun: String, undo: @escaping @MainActor () -> Void) -> some View {
        if let last = sets.last {
            Button("Undo last set (\(last) \(noun))", role: .destructive) { undo() }
        }
    }

    private nonisolated static func feedback(old: Int, new: Int, ghost: Int) -> SensoryFeedback? {
        if new < old { return .impact(weight: .light) }
        if ghost > 0, old <= ghost, new > ghost { return .success }
        return .impact(weight: .medium)
    }
}

private enum CustomSetTarget: String, Identifiable {
    case pushUps, sitUps
    var id: String { rawValue }
    var title: String { self == .pushUps ? "Push-ups" : "Sit-ups" }
}

// MARK: - Pieces

/// A section: a hairline rule across the top, 14 pt under it, rows 10 pt apart. No cards.
private struct RuledSection<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowGap) { content }
            .padding(.top, Metrics.ruleGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rule() }
    }
}

struct Rule: View {
    var body: some View {
        Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
    }
}

private struct NoteText: View {
    var text: String
    var ahead: Bool
    var body: some View {
        Text(text)
            .textStyle(.note)
            .foregroundStyle(ahead ? Palette.accent : Palette.muted)
            .multilineTextAlignment(.trailing)
    }
}

/// Orange block, dark text: the only filled surface on Today, kept for must days and an ended attempt.
private struct Banner: View {
    var title: String
    var line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textStyle(.banner)
            Text(line)
                .textStyle(.bannerBody)
        }
        .foregroundStyle(Palette.onFill)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent)
        .accessibilityElement(children: .combine)
    }
}

private struct NowBlock: View {
    var block: TodayModel.Block
    var body: some View {
        RuledSection {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text.label("Now · until \(block.until.formatted(.dateTime.hour().minute()))")
                    Text(block.title).textStyle(.blockTitle).foregroundStyle(Palette.text)
                }
                Spacer(minLength: 8)
                if let next = block.next {
                    Text("Next: \(next)").textStyle(.caption).foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Cream fill, dark Barlow numerals: the quick-add buttons.
struct FillButton: View {
    var title: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.button)
                .foregroundStyle(Palette.onFill)
                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                .background(Palette.text)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Transparent with a 1 pt outline: secondary actions.
struct OutlineButton<Label: View>: View {
    var label: String
    @ViewBuilder var content: Label
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                .overlay(Rectangle().strokeBorder(Palette.outline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Square, no glass: dims while pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Previews

/// Holds a TodayModel and applies actions to it, for previews and `-demo`.
@MainActor @Observable
final class PreviewTodayStore {
    var model: TodayModel
    init(_ model: TodayModel) { self.model = model }

    var actions: TodayActions {
        TodayActions(
            addPushUps: { [self] n in model.pushUps.today += n; model.pushUps.sets.append(n) },
            addSitUps: { [self] n in model.sitUps.today += n; model.sitUps.sets.append(n) },
            undoPushUps: { [self] in
                if let last = model.pushUps.sets.popLast() { model.pushUps.today -= last }
            },
            undoSitUps: { [self] in
                if let last = model.sitUps.sets.popLast() { model.sitUps.today -= last }
            },
            answerPosture: { [self] answer in
                if let i = model.nextPostureIndex { model.posture[i] = answer } else { model.posture.append(answer) }
            }
        )
    }
}

private struct TodayPreview: View {
    @State var store: PreviewTodayStore
    var body: some View {
        TodayView(model: store.model, actions: store.actions)
            .preferredColorScheme(.dark)
    }
}

#Preview("Normal") { TodayPreview(store: PreviewTodayStore(.preview)) }
#Preview("Must") { TodayPreview(store: PreviewTodayStore(.previewMust)) }
#Preview("Ahead") { TodayPreview(store: PreviewTodayStore(.previewAhead)) }
