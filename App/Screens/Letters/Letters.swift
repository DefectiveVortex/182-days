import DaysCore
import SwiftUI

/// A sealed letter as the screens show it. The text is only carried once the letter is open.
struct LetterSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    /// Day of the half-year it opens on (182 by default) and the day it was written on.
    var toDay: Int
    var fromDay: Int
    var written: Date
    var opens: Date
    var isOpen: Bool
    var text: String?

    var title: String { "Letter to day \(toDay)" }
    var line: String {
        isOpen
            ? "Opened \(Self.short(opens)). Written on day \(fromDay)."
            : "Sealed on day \(fromDay). Opens \(Self.short(opens))."
    }

    static func short(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
}

extension LetterSummary {
    @MainActor static func all(_ store: LogStore) -> [LetterSummary] {
        let today = store.today().day
        let firstDay = store.settings.firstDay ?? today
        func date(_ d: DayKey) -> Date { store.clock.date(on: d, at: ClockTime(hour: 12)) }
        return store.letters().map { l in
            let open = l.isOpen(on: today)
            return LetterSummary(
                id: l.id,
                toDay: LetterMarks.dayOfHalfYear(l.opens, firstDay: firstDay),
                fromDay: LetterMarks.dayOfHalfYear(l.written, firstDay: firstDay),
                written: date(l.written),
                opens: date(l.opens),
                isOpen: open,
                text: open ? l.text : nil
            )
        }
    }

    /// Today's day of the half-year when today asks for a letter (day 1, 30, 60…) and none is written yet.
    @MainActor static func dueToday(_ store: LogStore) -> Int? {
        guard let firstDay = store.settings.firstDay else { return nil }
        let today = store.today().day
        guard LetterMarks.isMarkDay(today, firstDay: firstDay),
              !store.letters().contains(where: { $0.written == today }) else { return nil }
        return LetterMarks.dayOfHalfYear(today, firstDay: firstDay)
    }

    /// When a letter written today opens: day 182 of this half-year, or of the next one on day 182 itself.
    @MainActor static func opensForToday(_ store: LogStore) -> DayKey {
        let today = store.today().day
        let firstDay = store.settings.firstDay ?? today
        let opens = LetterMarks.defaultOpens(written: today, firstDay: firstDay)
        return opens > today ? opens : LetterMarks.defaultOpens(written: today.adding(1), firstDay: firstDay)
    }
}

// MARK: - Write

/// Writing a letter: plain text, sealed until it opens. No edits, no deletes, so sealing asks first.
struct LetterSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirming = false
    @State private var sealed = 0
    @FocusState private var focused: Bool

    var body: some View {
        let today = store.today().day
        let firstDay = store.settings.firstDay ?? today
        let opens = LetterSummary.opensForToday(store)
        let opensDate = store.clock.date(on: opens, at: ClockTime(hour: 12))
        let toDay = LetterMarks.dayOfHalfYear(opens, firstDay: firstDay)
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(label: "Letter · day \(LetterMarks.dayOfHalfYear(today, firstDay: firstDay))",
                            close: "Cancel") { dismiss() }
                Text("TO DAY \(toDay).")
                    .textStyle(.headline)
                    .foregroundStyle(Palette.text)
                Text("Sealed until \(opensDate.formatted(.dateTime.day().month(.wide))). You can't read it or change it before then.")
                    .textStyle(.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What should day \(toDay) know?")
                            .textStyle(.body)
                            .foregroundStyle(Palette.ghost)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .textStyle(.body)
                        .foregroundStyle(Palette.text)
                        .accessibilityLabel(Text("Letter to day \(toDay)"))
                }
                .frame(minHeight: 220)
                .padding(8)
                .overlay(Rectangle().strokeBorder(Palette.outline, lineWidth: 1))

                FillButton(title: "SEAL IT", label: "Seal the letter") { confirming = true }
                    .disabled(empty)
                    .opacity(empty ? 0.35 : 1)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.success, trigger: sealed)
        .confirmationDialog("Seal this letter?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Seal until \(LetterSummary.short(opensDate))") {
                if store.writeLetter(text, opens: opens) != nil {
                    sealed += 1
                    dismiss()
                }
            }
        } message: {
            Text("It stays shut until day \(toDay). No edits after this.")
        }
    }
}

// MARK: - Read

struct LetterReadSheet: View {
    var letter: LetterSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(label: letter.title, close: "Done") { dismiss() }
                Text("FROM DAY \(letter.fromDay).")
                    .textStyle(.headline)
                    .foregroundStyle(Palette.text)
                Text("Written \(letter.written.formatted(.dateTime.day().month(.wide))). Opened \(letter.opens.formatted(.dateTime.day().month(.wide))).")
                    .textStyle(.caption)
                    .foregroundStyle(Palette.muted)
                Rule()
                Text(letter.text ?? "")
                    .textStyle(.body)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: - Pieces

/// A sheet's top line: the label on the left, the close word on the right.
struct SheetHeader: View {
    var label: String
    var close: String
    var action: () -> Void
    var body: some View {
        HStack(alignment: .center) {
            Text.label(label)
            Spacer()
            Button(action: action) {
                Text(close)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// The padlock from design/A-HalfYear: a 14×10 body and a shackle, on a 24-unit grid.
struct LockIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.addRect(CGRect(origin: pt(5, 11), size: CGSize(width: 14 * s, height: 10 * s)))
        p.move(to: pt(8, 11))
        p.addLine(to: pt(8, 8))
        p.addCurve(to: pt(16, 8), control1: pt(8, 2.67), control2: pt(16, 2.67))
        p.addLine(to: pt(16, 11))
        return p
    }
}

/// One letter on the 182 view: title, the sealed/opened line, a padlock while sealed.
struct LetterRowView: View {
    var letter: LetterSummary
    var read: @MainActor () -> Void

    var body: some View {
        if letter.isOpen {
            Button(action: read) { row }
                .buttonStyle(PressStyle())
                .accessibilityLabel(Text("\(letter.title). \(letter.line)"))
                .accessibilityHint(Text("Reads the letter"))
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(letter.title). \(letter.line)"))
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.title).textStyle(.bodyMedium).foregroundStyle(Palette.text)
                Text(letter.line).textStyle(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if letter.isOpen {
                Text("Read").textStyle(.bodyMedium).foregroundStyle(Palette.accent)
            } else {
                LockIcon()
                    .stroke(Palette.muted, style: StrokeStyle(lineWidth: 2 * 22 / 24, lineJoin: .miter))
                    .frame(width: 22, height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.minTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}
