import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

struct SnapshotEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchSnapshot
  let cover: Data?
}

struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: Date(), snapshot: .empty, cover: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    completion(Self.load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    let entry = Self.load()
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
  }

  private static func load() -> SnapshotEntry {
    let defaults = UserDefaults(suiteName: WatchShared.suiteName)
    let snapshot: WatchSnapshot
    if let data = defaults?.data(forKey: WatchShared.snapshotKey),
       let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    {
      snapshot = value
    } else {
      snapshot = .empty
    }
    return SnapshotEntry(
      date: Date(),
      snapshot: snapshot,
      cover: defaults?.data(forKey: WatchShared.coverKey)
    )
  }
}

struct CircularComplicationView: View {
  var entry: SnapshotEntry

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      if let cover = entry.cover, let image = UIImage(data: cover) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
          .font(.title3)
          .foregroundStyle(Color(hex: 0xC4A46A))
      }
    }
    .containerBackground(.clear, for: .widget)
  }
}

struct RectangularComplicationView: View {
  var entry: SnapshotEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.snapshot.zoneName)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(entry.snapshot.title ?? "Nothing playing")
        .font(.headline)
        .lineLimit(1)
      Text(entry.snapshot.artist ?? "")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .containerBackground(.clear, for: .widget)
  }
}

struct RoonCircularWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RoonCircular", provider: SnapshotProvider()) { entry in
      CircularComplicationView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Album art for the room the phone is controlling.")
    .supportedFamilies([.accessoryCircular, .accessoryCorner])
  }
}

struct RoonRectangularWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RoonRectangular", provider: SnapshotProvider()) { entry in
      RectangularComplicationView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Track title on the selected room.")
    .supportedFamilies([.accessoryRectangular, .accessoryInline])
  }
}

@main
struct RoonWatchWidgets: WidgetBundle {
  var body: some Widget {
    RoonCircularWidget()
    RoonRectangularWidget()
  }
}
