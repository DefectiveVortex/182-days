import SwiftUI

/// A row whose children share the width by weight (CSS `flex: 1 / 1 / 1.3`).
/// Height is the tallest child.
struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let w = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let sum = w.reduce(0, +)
        let free = max(0, total - spacing * CGFloat(max(count - 1, 0)))
        return w.map { free * $0 / max(sum, 0.0001) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 320
        let ws = widths(total: total, count: subviews.count)
        let height = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (view, w) in zip(subviews, ws) {
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}
