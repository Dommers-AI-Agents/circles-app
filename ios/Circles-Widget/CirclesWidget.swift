import WidgetKit
import SwiftUI

// The FavCircles home-screen widget: "what your people saved lately", straight
// from the App Group snapshot the main app writes (WidgetSnapshotService).
// No networking here — a widget process gets milliseconds, and the snapshot
// is always the freshest thing the user has actually seen.

struct SnapshotTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotTimelineEntry {
        SnapshotTimelineEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotTimelineEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotTimelineEntry(date: Date(), snapshot: .sample))
            return
        }
        completion(SnapshotTimelineEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotTimelineEntry>) -> Void) {
        // The app pushes reloads on every refresh; the hourly fallback just
        // keeps relative labels ("2h ago") from going stale on a quiet day.
        let entry = SnapshotTimelineEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        generatedAt: Date(),
        entries: [
            Entry(placeId: nil, title: "Brothers Pizza", subtitle: "Joey · Pizza Spots", timestamp: Date()),
            Entry(placeId: nil, title: "Sunrise Cafe", subtitle: "Margie · Breakfast", timestamp: Date()),
            Entry(placeId: nil, title: "The Boardwalk", subtitle: "Amanda · Jersey Shore", timestamp: Date())
        ],
        coinBalance: 120
    )

    var deepLinkURL: URL? {
        guard let placeId = entries.first?.placeId else { return nil }
        return URL(string: "circles://place/\(placeId)")
    }
}

private func deepLink(for entry: WidgetSnapshot.Entry) -> URL {
    if let placeId = entry.placeId, let url = URL(string: "circles://place/\(placeId)") {
        return url
    }
    return URL(string: "circles://network")!
}

// MARK: - Views

struct CirclesWidgetEntryView: View {
    var entry: SnapshotTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.entries.isEmpty {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot)
                default: MediumView(snapshot: snapshot)
                }
            } else {
                EmptyStateView()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

/// Latest save from the network, one place, full-bleed.
struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FavCircles")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer(minLength: 2)
            if let first = snapshot.entries.first {
                Text(first.title)
                    .font(.headline)
                    .lineLimit(2)
                if !first.subtitle.isEmpty {
                    Text(first.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if let coins = snapshot.coinBalance {
                Text("🪙 \(coins, format: .number.precision(.fractionLength(0...2)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(snapshot.deepLinkURL)
    }
}

/// Up to three recent saves, each row deep-linking to its place.
struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New from your people")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            ForEach(Array(snapshot.entries.prefix(3).enumerated()), id: \.offset) { _, item in
                Link(destination: deepLink(for: item)) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(item.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("FavCircles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Open the app to see what your people are saving")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget

struct CirclesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CirclesNetworkWidget", provider: SnapshotProvider()) { entry in
            CirclesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Your People's Places")
        .description("The latest places saved by the people you follow.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CirclesWidgetBundle: WidgetBundle {
    var body: some Widget {
        CirclesWidget()
    }
}
