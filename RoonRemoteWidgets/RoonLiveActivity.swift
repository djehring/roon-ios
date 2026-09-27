import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct RoonNowPlayingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RoonNowPlayingAttributes.self) { context in
      NowPlayingActivityContent(state: context.state)
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
          playPauseButton(state: context.state, size: 36)
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

private struct NowPlayingActivityContent: View {
  @Environment(\.activityFamily) private var activityFamily
  var state: RoonNowPlayingAttributes.ContentState

  var body: some View {
    switch activityFamily {
    case .small:
      SmallNowPlayingBanner(state: state)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    case .medium:
      NowPlayingBanner(state: state)
        .padding(16)
    @unknown default:
      NowPlayingBanner(state: state)
        .padding(16)
    }
  }
}

private struct SmallNowPlayingBanner: View {
  var state: RoonNowPlayingAttributes.ContentState

  var body: some View {
    // Keep the title above the artwork and controls so they cannot squeeze it
    // into the narrow text column of the iPhone Lock Screen layout.
    VStack(alignment: .leading, spacing: 4) {
      Text(state.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
      HStack(spacing: 6) {
        artwork(state: state, size: 28, corner: 4)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(state.artist)
          Text(state.zoneName)
            .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        playPauseButton(state: state, size: 32)
      }
    }
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
      playPauseButton(state: state)
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
private func playPauseButton(
  state: RoonNowPlayingAttributes.ContentState, size: CGFloat = 44
) -> some View {
  let symbol = state.isPlaying ? "pause.fill" : "play.fill"
  Button(intent: NowPlayingPlayPauseIntent(zoneID: state.zoneID)) {
    Image(systemName: symbol)
      .font(size >= 40 ? .title3 : .caption)
      .frame(width: size, height: size)
      .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
}

@main
struct RoonRemoteWidgets: WidgetBundle {
  var body: some Widget {
    RoonNowPlayingLiveActivity()
  }
}

#Preview("Now Playing", as: .content, using: RoonNowPlayingAttributes(zoneId: "office")) {
  RoonNowPlayingLiveActivity()
} contentStates: {
  RoonNowPlayingAttributes.ContentState(
    zoneName: "Office", title: "The Prayer", artist: "Céline Dion & Andrea Bocelli",
    isPlaying: true
  )
  RoonNowPlayingAttributes.ContentState(
    zoneName: "Living Room & Kitchen",
    title: "Piano Concerto No. 2 in C Minor, Op. 18: II. Adagio sostenuto",
    artist: "Sergei Rachmaninoff", isPlaying: false
  )
}
