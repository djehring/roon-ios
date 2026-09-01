import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct RoonNowPlayingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RoonNowPlayingAttributes.self) { context in
      NowPlayingBanner(state: context.state)
        .padding(16)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          artwork(state: context.state, size: 44, corner: 8)
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
          playPauseButton(isPlaying: context.state.isPlaying, size: 36)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.zoneName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        islandGlyph(state: context.state, size: 24)
      } compactTrailing: {
        IslandPlayingWave(isPlaying: context.state.isPlaying)
      } minimal: {
        islandGlyph(state: context.state, size: 20)
      }
    }
    .supplementalActivityFamilies([.small])
  }
}

private struct NowPlayingBanner: View {
  var state: RoonNowPlayingAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      artwork(state: state, size: 52, corner: 8)
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
      playPauseButton(isPlaying: state.isPlaying)
    }
  }
}

private func artwork(
  state: RoonNowPlayingAttributes.ContentState,
  size: CGFloat,
  corner: CGFloat
) -> some View {
  CoverArt(title: state.title, image: state.artworkJPEG, corner: corner)
    .frame(width: size, height: size)
}

/// Compact island holes are 20–24pt. CoverArt's 28pt note and dark gradient
/// disappear into the black pill when radio has no artwork.
private func islandGlyph(
  state: RoonNowPlayingAttributes.ContentState,
  size: CGFloat
) -> some View {
  Group {
    if let data = state.artworkJPEG, let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      Image(systemName: "radio.fill")
        .font(.system(size: size * 0.48, weight: .semibold))
        .foregroundStyle(.white)
    }
  }
  .frame(width: size, height: size)
  .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
}

/// Five bars that bounce while the zone is playing, the same cue Apple Music
/// uses in the compact island. `TimelineView` ticks locally so we do not
/// spend the Live Activity update budget on every beat.
private struct IslandPlayingWave: View {
  var isPlaying: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      HStack(alignment: .center, spacing: 1.6) {
        ForEach(0..<5, id: \.self) { index in
          Capsule()
            .fill(.white)
            .frame(width: 2, height: barHeight(index: index, time: t))
        }
      }
    }
    .frame(width: 20, height: 16)
  }

  private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
    guard isPlaying else { return 4 }
    let phase = sin(time * 7.2 + Double(index) * 0.95)
    return 5 + CGFloat(phase + 1) * 5.5
  }
}

@ViewBuilder
private func playPauseButton(isPlaying: Bool, size: CGFloat = 44) -> some View {
  let symbol = isPlaying ? "pause.fill" : "play.fill"
  Button(intent: NowPlayingPlayPauseIntent()) {
    Image(systemName: symbol)
      .font(size >= 40 ? .title3 : .caption)
      .frame(width: size, height: size)
      .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
}

@main
struct RoonRemoteWidgets: WidgetBundle {
  var body: some Widget {
    RoonNowPlayingLiveActivity()
  }
}
