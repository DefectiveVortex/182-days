import SwiftUI

/// Tally marks in groups of five, with yesterday drawn underneath as the ghost.
///
/// Matches design/AC-Today.dc.html:
/// - Marks are 2 × 24 pt, 4 pt apart; four uprights plus a slash make a 22 pt group.
/// - Groups wrap with 9 pt between them and 10 pt between rows.
/// - Today's marks are cream; marks past yesterday's count are orange.
/// - Yesterday's marks not yet matched today stay solid in the dim ghost colour (dashes blurred at phone size).
/// - With nothing today and no ghost, one empty group in the rule colour holds the row's place.
struct GhostTally: View {
    var today: Int
    var ghost: Int

    var body: some View {
        let total = max(today, ghost, 0)
        FlowLayout(spacing: 9, lineSpacing: 10) {
            if total == 0 {
                TallyGroup(start: 0, count: 5, today: 0, ghost: 0, empty: true)
            }
            ForEach(Array(stride(from: 0, to: total, by: 5)), id: \.self) { start in
                TallyGroup(start: start, count: min(5, total - start), today: today, ghost: ghost)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text("Tally"))
        .accessibilityValue(Text("\(today) today, \(ghost) yesterday"))
    }
}

/// How one mark is drawn.
enum MarkStyle: Equatable {
    case today        // done, within yesterday's count
    case pastGhost    // done, beyond yesterday's count
    case ghost        // yesterday's, not yet matched

    init(index: Int, today: Int, ghost: Int) {
        if index < today {
            self = index >= ghost ? .pastGhost : .today
        } else {
            self = .ghost
        }
    }

    var color: Color {
        switch self {
        case .today: Palette.text
        case .pastGhost: Palette.accent
        case .ghost: Palette.ghost
        }
    }

    var stroke: StrokeStyle { StrokeStyle(lineWidth: 2, lineCap: .butt) }
}

private struct TallyGroup: View {
    let start: Int
    let count: Int
    let today: Int
    let ghost: Int
    var empty = false

    static let markHeight: CGFloat = 24
    static let width: CGFloat = 22

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(count, 4), id: \.self) { j in
                let style = MarkStyle(index: start + j, today: today, ghost: ghost)
                Upright(x: CGFloat(j) * 6 + 1)
                    .stroke(empty ? Palette.rule : style.color, style: style.stroke)
            }
            if count == 5 {
                let style = MarkStyle(index: start + 4, today: today, ghost: ghost)
                Slash()
                    .stroke(empty ? Palette.rule : style.color, style: style.stroke)
            }
        }
        .frame(width: Self.width, height: Self.markHeight)
        .animation(.easeOut(duration: 0.18), value: today)
    }
}

/// A 2 pt upright, stroked down its centre line at `x`.
private struct Upright: Shape {
    var x: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
        }
    }
}

/// The fifth mark: a 28 pt stroke centred on the group, rising at 28°. It overhangs the
/// 22 pt group a little on both sides, as in the design (shapes don't clip).
private struct Slash: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: 12)
        let half: CGFloat = 14
        let angle = 28 * CGFloat.pi / 180
        let dx = half * cos(angle), dy = half * sin(angle)
        return Path { p in
            p.move(to: CGPoint(x: centre.x - dx, y: centre.y + dy))
            p.addLine(to: CGPoint(x: centre.x + dx, y: centre.y - dy))
        }
    }
}

/// A horizontal bar with yesterday as a dashed outline underneath: the sit-up ghost bar.
struct GhostBar: View {
    var today: Int
    var ghost: Int
    /// The count that fills the whole width.
    var scale: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = w / CGFloat(max(scale, 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.track)
                if ghost > 0 {
                    Rectangle()
                        .strokeBorder(Palette.ghost, style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3]))
                        .frame(width: min(w, unit * CGFloat(ghost)))
                }
                Rectangle()
                    .fill(today > ghost ? Palette.accent : Palette.text)
                    .frame(width: min(w, unit * CGFloat(max(today, 0))))
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.2), value: today)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress bar"))
        .accessibilityValue(Text("\(today) today, \(ghost) yesterday"))
    }
}

/// One posture check's answer, or nil while it is still to come.
enum PostureAnswer: Equatable, Sendable {
    case upright
    case slouching
}

/// A row of 14 pt squares: filled = upright, orange outline = slouching, dashed = still to come.
struct PostureMarks: View {
    var answers: [PostureAnswer?]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                switch answer {
                case .upright:
                    Rectangle().fill(Palette.text)
                case .slouching:
                    Rectangle().strokeBorder(Palette.accent, lineWidth: 1.5)
                case nil:
                    Rectangle().strokeBorder(Palette.ghost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
            .frame(width: 14, height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Wraps children left to right, then onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("Tally") {
    VStack(alignment: .leading, spacing: 24) {
        GhostTally(today: 18, ghost: 31)
        GhostTally(today: 36, ghost: 31)
        GhostTally(today: 0, ghost: 0)
        GhostBar(today: 40, ghost: 58, scale: 110)
        GhostBar(today: 70, ghost: 58, scale: 110)
        PostureMarks(answers: [.upright, .upright, .slouching, .upright, .upright, nil])
    }
    .padding(20)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Palette.background)
}
