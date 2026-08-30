import ActivityKit
import SwiftUI
import WidgetKit

struct RoonNowPlayingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RoonNowPlayingAttributes.self) { context in
      NowPlayingBanner(state: context.state)
        .padding(16)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "hifispeaker.fill")
            .foregroundStyle(Color(hex: 0xC4A46A))
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.title)
              .font(.headline)
              .lineLimit(1)
            Text(context.state.artist)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.zoneName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "hifispeaker.fill")
          .foregroundStyle(Color(hex: 0xC4A46A))
      } compactTrailing: {
        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
      } minimal: {
        Image(systemName: "hifispeaker.fill")
          .foregroundStyle(Color(hex: 0xC4A46A))
      }
    }
    .supplementalActivityFamilies([.small])
  }
}

private struct NowPlayingBanner: View {
  var state: RoonNowPlayingAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "hifispeaker.fill")
        .font(.title2)
        .foregroundStyle(Color(hex: 0xC4A46A))
      VStack(alignment: .leading, spacing: 2) {
        Text(state.title)
          .font(.headline)
          .lineLimit(1)
        Text(state.artist)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(state.zoneName)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
        .font(.title3)
    }
  }
}

@main
struct RoonRemoteWidgets: WidgetBundle {
  var body: some Widget {
    RoonNowPlayingLiveActivity()
  }
}
