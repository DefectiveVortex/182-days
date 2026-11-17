import AppIntents
import DaysCore
import SwiftUI
import WidgetKit

/// The widget extension. Owner: Days 1. Look comes from App/Theme (Days 2), compiled into this target too.
@main
struct DaysWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LogPushUpsControl()
    }
}

// MARK: Data

/// What every widget shows: one practice against its ghost.
struct Count: Equatable {
    var value: Int
    var ghost: Int
    var target: Int?

    /// "14 to pass your ghost", "3 past your ghost", "no ghost today".
    var ghostLine: String {
        if ghost == 0 { return value > 0 ? "no ghost today" : "anything counts" }
        if value > ghost { return "\(value - ghost) past your ghost" }
        if value == ghost { return "level with your ghost" }
        return "\(ghost - value) to pass your ghost"
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let onboarded: Bool
    let dayNumber: Int
    let isMustDay: Bool
    let kept: Bool
    let pushUps: Count
    let sitUps: Count
    /// When the day turns over (04:00): the timeline reloads then.
    let dayEnds: Date

    static let sample = TodayEntry(
        date: .now, onboarded: true, dayNumber: 23, isMustDay: false, kept: true,
        pushUps: Count(value: 18, ghost: 31, target: 50), sitUps: Count(value: 40, ghost: 59, target: 100),
        dayEnds: .now.addingTimeInterval(3600))

    @MainActor static func load() -> TodayEntry {
        let store = LogStore.current
        store.reload()
        let t = store.today()
        func count(_ id: PracticeID) -> Count {
            let p = t[id]
            return Count(value: p?.value ?? 0, ghost: p?.ghost ?? 0, target: p?.target)
        }
        return TodayEntry(
            date: t.now, onboarded: store.isOnboarded, dayNumber: t.dayNumber, isMustDay: t.isMustDay,
            kept: t.kept, pushUps: count(.pushUps), sitUps: count(.sitUps),
            dayEnds: store.clock.end(of: t.day))
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview { completion(.sample); return }
        nonisolated(unsafe) let completion = completion
        Task { @MainActor in completion(TodayEntry.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { @MainActor in
            let entry = TodayEntry.load()
            // A minute past the boundary, so the new day (and yesterday's ghost) is what loads.
            completion(Timeline(entries: [entry], policy: .after(entry.dayEnds.addingTimeInterval(60))))
        }
    }
}

// MARK: Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today against yesterday's ghost. +10 logs without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular,
                            .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if !entry.onboarded {
            Text("Open 182 Days to start.")
                .textStyle(.caption)
                .foregroundStyle(Palette.muted)
        } else {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    // Home, small: push-ups and +10.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            Text("\(entry.pushUps.value)")
                .textStyle(.count)
                .foregroundStyle(entry.pushUps.value > entry.pushUps.ghost ? Palette.accent : Palette.text)
            Text(entry.pushUps.ghostLine)
                .textStyle(.small)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Spacer(minLength: 6)
            plusTen(.pushUps, noun: "push-ups", filled: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Home, medium: both counts with their ghost bars, +10 each.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 16) {
                column("Push-ups", .pushUps, entry.pushUps, filled: true)
                column("Sit-ups", .sitUps, entry.sitUps, filled: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ name: String, _ id: PracticeID, _ c: Count, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text.label(name)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(c.value)")
                    .textStyle(.stat)
                    .foregroundStyle(c.value > c.ghost ? Palette.accent : Palette.text)
                if c.ghost > 0 {
                    Text("ghost \(c.ghost)")
                        .textStyle(.small)
                        .foregroundStyle(Palette.muted)
                }
            }
            GhostBar(today: c.value, ghost: c.ghost, scale: max(c.value, c.ghost, c.target ?? 0, 1))
            Spacer(minLength: 4)
            plusTen(id, noun: name.lowercased(), filled: filled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("DAY \(entry.dayNumber)")
                .textStyle(.banner)
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
            if entry.isMustDay && !entry.kept {
                Text("MUST DAY")
                    .textStyle(.label)
                    .foregroundStyle(Palette.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func plusTen(_ id: PracticeID, noun: String, filled: Bool) -> some View {
        Button(intent: LogPracticeIntent(id, 10)) {
            Text("+10")
                .textStyle(.button)
                .foregroundStyle(filled ? Palette.onFill : Palette.text)
                .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                .background(filled ? Palette.text : Color.clear)
                .overlay(Rectangle().strokeBorder(filled ? Color.clear : Palette.outline, lineWidth: Metrics.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Log 10 \(noun)"))
    }

    // Lock screen.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.isMustDay && !entry.kept ? "DAY \(entry.dayNumber) · MUST DAY" : "DAY \(entry.dayNumber)")
                .font(TextStyle.banner.font)
                .widgetAccentable()
            Text("Push-ups \(entry.pushUps.value) · ghost \(entry.pushUps.ghost)")
                .font(TextStyle.small.font)
            Text("Sit-ups \(entry.sitUps.value) · ghost \(entry.sitUps.ghost)")
                .font(TextStyle.small.font)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: Double(min(entry.pushUps.value, max(entry.pushUps.ghost, 1))),
              in: 0...Double(max(entry.pushUps.ghost, 1))) {
            Text("Push-ups")
        } currentValueLabel: {
            Text("\(entry.pushUps.value)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(Text("Push-ups \(entry.pushUps.value), ghost \(entry.pushUps.ghost)"))
    }

    private var inline: some View {
        Text(entry.isMustDay && !entry.kept
             ? "Day \(entry.dayNumber) · must day"
             : "Day \(entry.dayNumber) · \(entry.pushUps.value)/\(entry.pushUps.ghost) push-ups")
    }
}

// MARK: Control (Control Center, lock screen, Action button)

struct LogPushUpsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.viraajrandhawa.182days.pushups10") {
            ControlWidgetButton(action: LogPracticeIntent(.pushUps, 10)) {
                Label("+10 push-ups", systemImage: "plus")
            }
        }
        .displayName("+10 push-ups")
        .description("Logs 10 push-ups to today without opening the app.")
    }
}
