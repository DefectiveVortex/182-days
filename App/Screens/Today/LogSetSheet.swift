import SwiftUI

/// "Log a set": a number pad for one set of any size. Big numerals, one confirm, nothing else.
struct LogSetSheet: View {
    var title: String
    var onLog: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            HStack(alignment: .firstTextBaseline) {
                Text.label(title)
                Spacer()
                Button("Cancel") { dismiss() }
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.muted)
                    .frame(minWidth: Metrics.minTarget, minHeight: Metrics.minTarget)
            }
            Text(digits.isEmpty ? "0" : digits)
                .textStyle(.hero)
                .foregroundStyle(digits.isEmpty ? Palette.ghost : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("Set of \(amount)"))
            Rule()
            keypad
            FillButton(title: amount > 0 ? "LOG \(amount)" : "LOG", label: "Log \(amount) \(title.lowercased())") {
                guard amount > 0 else { return }
                onLog(amount)
                dismiss()
            }
            .disabled(amount == 0)
            .opacity(amount == 0 ? 0.4 : 1)
        }
        .padding(Metrics.gutter)
        .background(Palette.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .presentationCornerRadius(0)
        .sensoryFeedback(.selection, trigger: digits)
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", Self.delete]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                if key.isEmpty {
                    Color.clear.frame(height: Metrics.buttonHeight)
                } else {
                    OutlineButton(label: key == Self.delete ? "Delete" : key) {
                        if key == Self.delete {
                            DeleteGlyph().stroke(Palette.text, lineWidth: 2).frame(width: 24, height: 16)
                        } else {
                            Text(key).textStyle(.button)
                        }
                    } action: {
                        press(key)
                    }
                }
            }
        }
    }

    private static let delete = "delete"

    private func press(_ key: String) {
        if key == Self.delete {
            if !digits.isEmpty { digits.removeLast() }
        } else if digits.count < 4, !(digits.isEmpty && key == "0") {
            digits += key
        }
    }
}

/// A back-delete key drawn in the tally's line weight.
private struct DeleteGlyph: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let notch = r.height / 2
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + notch, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + notch, y: r.maxY))
            p.closeSubpath()
            let c = CGPoint(x: r.minX + notch + (r.width - notch) / 2, y: r.midY), d = r.height * 0.22
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x + d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
        }
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        LogSetSheet(title: "Push-ups") { _ in }
    }
}
