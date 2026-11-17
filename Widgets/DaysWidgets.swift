import SwiftUI
import WidgetKit

@main
struct DaysWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { entry in
            Text("DAY \(entry.dayNumber)")
                .containerBackground(Color(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0C / 255), for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's count.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let dayNumber: Int
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, dayNumber: 1) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
