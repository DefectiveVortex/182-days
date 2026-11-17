import DaysCore
import SwiftUI
import UIKit

/// A weekly posture photo as the screens show it. Week 1 is the first photo ever: the ghost.
struct PhotoSummary: Equatable, Sendable, Identifiable {
    var id: Int
    var week: Int
    var date: Date
    var url: URL

    var caption: String { "Week \(week) · \(date.formatted(.dateTime.day().month(.abbreviated)))" }
    var spoken: String { "Week \(week) posture photo, \(date.formatted(.dateTime.day().month(.wide)))" }
}

extension PhotoSummary {
    @MainActor static func all(_ store: LogStore) -> [PhotoSummary] {
        let photos = store.posturePhotos()
        guard let first = photos.first else { return [] }
        return photos.map { p in
            PhotoSummary(id: p.day.ordinal, week: week(of: p.day, first: first.day),
                         date: store.clock.date(on: p.day, at: ClockTime(hour: 12)), url: p.url)
        }
    }

    /// The week number a photo taken today gets.
    @MainActor static func weekToday(_ store: LogStore) -> Int {
        guard let first = store.posturePhotos().first?.day else { return 1 }
        return week(of: store.today().day, first: first)
    }

    static func week(of day: DayKey, first: DayKey) -> Int {
        max(0, PhotoWeek.sunday(of: first).distance(to: PhotoWeek.sunday(of: day))) / 7 + 1
    }

    /// The ghost for today's photo: the first photo, unless that one was taken today.
    @MainActor static func ghost(_ store: LogStore) -> URL? {
        let today = store.today().day
        return store.posturePhotos().first { $0.day != today }?.url
    }
}

/// A photo from the App Group, 3:4, filled and cropped. Loads off the main thread.
struct PhotoImage: View {
    var url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .background(Palette.track)
            .task(id: url) { image = await Self.load(url) }
    }

    static func load(_ url: URL) async -> UIImage? {
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        return data.flatMap { UIImage(data: $0) }
    }
}

/// The 182 view's posture block: week 1 beside the latest week, and this week's photo when it's due.
struct PhotoSection: View {
    var photos: [PhotoSummary]
    var due: Bool
    var take: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text.label("Posture, weekly")
            if let first = photos.first {
                HStack(alignment: .top, spacing: 8) {
                    tile(first)
                    if let last = photos.last, last != first {
                        tile(last)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Color.clear
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                .overlay(Rectangle().strokeBorder(Palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            Text("Week 2").textStyle(.small).foregroundStyle(Palette.ghost)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Text(line)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if due {
                    OutlineButton(label: "Take this week's posture photo") {
                        Text("Take").textStyle(.bodyMedium)
                    } action: {
                        take()
                    }
                    .frame(width: 96)
                }
            }
        }
    }

    private var line: String {
        if photos.isEmpty { return "None yet. The first one is the ghost you line up with every Sunday." }
        if due { return "This week's photo is due." }
        return photos.count == 1 ? "1 photo. The next one is on Sunday." : "\(photos.count) photos. The next one is on Sunday."
    }

    private func tile(_ p: PhotoSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotoImage(url: p.url)
                .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
            Text(p.caption).textStyle(.small).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(p.spoken))
        .accessibilityAddTraits(.isImage)
    }
}
