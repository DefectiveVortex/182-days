import SwiftUI

/// The app's shell: four tabs under a hairline, drawn to the design (square, no glass).
/// DaysApp shows `RootView()` with the LogStore in the environment.
struct RootView: View {
    @Environment(LogStore.self) private var store
    @State private var tab: AppTab = LaunchScreen.argument.flatMap(AppTab.init(screen:)) ?? .today

    var body: some View {
        if store.isOnboarded {
            tabs
        } else {
            OnboardingView(step: LaunchScreen.argument.flatMap(OnboardingView.Step.init(screen:)) ?? .rule)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
    }

    private var tabs: some View {
        Group {
            switch tab {
            case .today: TodayScreen()
            case .plan: Placeholder(title: "Plan", line: "Your week, hour by hour.")
            case .log: Placeholder(title: "Log", line: "Every day you've closed.")
            case .halfYear: HalfYearScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(selection: $tab) }
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
    }
}

/// `-screen <name>` (CI screenshots): today | plan | log | 182 | onboarding | onboarding-numbers | onboarding-day.
enum LaunchScreen {
    static var argument: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

extension OnboardingView.Step {
    init?(screen: String) {
        switch screen {
        case "onboarding": self = .rule
        case "onboarding-numbers": self = .numbers
        case "onboarding-day": self = .day
        default: return nil
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, plan, log, halfYear
    var id: String { rawValue }
    init?(screen: String) {
        switch screen {
        case "today": self = .today
        case "plan": self = .plan
        case "log": self = .log
        case "182": self = .halfYear
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .log: "Log"
        case .halfYear: "182"
        }
    }
}

private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        TabIcon(tab: tab)
                            .stroke(style: StrokeStyle(lineWidth: 2 * 22 / 24, lineCap: .butt, lineJoin: .miter))
                            .frame(width: 22, height: 22)
                        Text(tab.title)
                            .font(selected ? TextStyle.tab.font : .custom(Typeface.Inter.medium.rawValue, size: 11, relativeTo: .caption2))
                    }
                    .foregroundStyle(selected ? Palette.text : Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab == .halfYear ? "182 days" : tab.title))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .background(Palette.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rule() }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The four tab icons from the design, as 24-unit paths scaled to the frame.
private struct TabIcon: Shape {
    var tab: AppTab

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func line(_ p: inout Path, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
            p.move(to: pt(a.0, a.1)); p.addLine(to: pt(b.0, b.1))
        }
        func square(_ p: inout Path, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.addRect(CGRect(origin: pt(x, y), size: CGSize(width: w * s, height: h * s)))
        }
        var p = Path()
        switch tab {
        case .today: // a tally of four with a slash
            for x in [5, 9, 13, 17] as [CGFloat] { line(&p, (x, 4), (x, 20)) }
            line(&p, (3, 15), (21, 9))
        case .plan: // a week grid
            square(&p, 4, 4, 16, 16)
            line(&p, (4, 9), (20, 9))
            line(&p, (9, 4), (9, 20))
        case .log: // a page of lines
            square(&p, 6, 3, 12, 18)
            line(&p, (9, 8), (15, 8))
            line(&p, (9, 12), (15, 12))
            line(&p, (9, 16), (13, 16))
        case .halfYear: // the day grid, part filled
            for (x, y) in [(4, 4), (10, 4), (16, 4), (4, 10), (10, 10), (4, 16)] as [(CGFloat, CGFloat)] {
                square(&p, x, y, 4, 4)
            }
        }
        return p
    }
}

/// A quiet stand-in for screens that arrive in later milestones.
private struct Placeholder: View {
    var title: String
    var line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).textStyle(.dayNumber).foregroundStyle(Palette.text)
            Text(line).textStyle(.caption).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Root") {
    RootView().environment(try! LogStore.inMemory())
}
