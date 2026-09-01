import SwiftUI
import UIKit

struct TVNowPlayingView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    ZStack {
      HStack(alignment: .center, spacing: 64) {
        CoverArt(
          title: store.currentTrack?.album ?? "empty",
          image: store.imageData(
            for: store.currentTrack?.imageKey,
            pixels: ArtworkCache.heroPixels
          ),
          corner: 18
        )
        .frame(width: 420, height: 420)
        .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
        .animation(Motion.sheet, value: store.currentTrack?.id)

        VStack(alignment: .leading, spacing: 36) {
          VStack(alignment: .leading, spacing: 16) {
            Button {
              store.selectedTab = .rooms
            } label: {
              TVZoneChipLabel(name: store.selectedZone.name)
            }
            .tvUnplated()

            HStack(spacing: 28) {
              TVIconButton(symbol: "speaker.wave.2.fill", size: 56, fontSize: 20) {
                store.showVolume = true
              }
              TVIconButton(symbol: "list.bullet", size: 56, fontSize: 20) {
                store.showQueue = true
              }
              Spacer(minLength: 0)
            }
          }

          if let track = store.currentTrack {
            VStack(alignment: .leading, spacing: 10) {
              Text(track.title)
                .font(.system(size: 48, weight: .bold))
                .lineLimit(2)
              Text(track.artist)
                .font(.title2)
                .foregroundStyle(Palette.secondary)
              Text(track.album)
                .font(.title3)
                .foregroundStyle(Palette.tertiary)
            }

            progress(track)

            TVTransportControls()

            Button {
              store.showQueue = true
            } label: {
              TVUpNextLabel(
                title: store.upNext.map { "Up next  ·  \($0.title)" } ?? "Queue"
              )
            }
            .tvUnplated()
          } else {
            Text("Nothing playing")
              .font(.system(size: 40, weight: .semibold))
              .foregroundStyle(Palette.secondary)
            Text("Pick something from Library or Search")
              .font(.title3)
              .foregroundStyle(Palette.tertiary)
            TVTransportControls()
              .disabled(true)
              .opacity(0.45)

            HStack(spacing: 24) {
              Button {
                store.showVolume = true
              } label: {
                TVChipLabel(title: "Volume", symbol: "speaker.wave.2.fill")
              }
              .tvUnplated()
              Button {
                store.showQueue = true
              } label: {
                TVChipLabel(title: "Queue", symbol: "list.bullet")
              }
              .tvUnplated()
            }
            .padding(.top, 8)
          }
        }
        .frame(maxWidth: 620, alignment: .leading)
      }
      .padding(64)
      .focusSection()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Same reason as the iPad: an unclipped `scaledToFill` cover reports its
    // overscaled size, so as a stack sibling it would push this layout around.
    .background { artBackdrop }
    .sheet(isPresented: $store.showVolume) {
      TVVolumePanel()
    }
    .sheet(isPresented: $store.showQueue) {
      TVQueuePanel()
    }
  }


  @ViewBuilder
  private var artBackdrop: some View {
    if let data = store.imageData(
      for: store.currentTrack?.imageKey,
      pixels: ArtworkCache.heroPixels
    ), let ui = UIImage(data: data) {
      GeometryReader { geometry in
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()
          .blur(radius: 60)
          .opacity(0.35)
          .overlay {
            LinearGradient(
              colors: [Palette.background.opacity(0.55), Palette.background],
              startPoint: .top,
              endPoint: .bottom
            )
          }
      }
      .ignoresSafeArea()
    } else {
      Palette.background.ignoresSafeArea()
    }
  }

  private func progress(_ track: Track) -> some View {
    VStack(spacing: 8) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Palette.hairline)
          Capsule()
            .fill(Palette.accent)
            .frame(width: max(4, geo.size.width * track.progress))
        }
      }
      .frame(height: 6)
      HStack {
        Text(track.position)
        Spacer()
        Text(remainingLabel(for: track))
      }
      .font(.callout)
      .foregroundStyle(Palette.tertiary)
    }
    .padding(.top, 4)
  }

  private func remainingLabel(for track: Track) -> String {
    TimeCode.remaining(
      duration: track.durationSeconds,
      seekPosition: track.position,
      seekPercentage: track.progress * 100
    ) ?? track.remaining
  }
}

struct TVTransportControls: View {
  @Environment(MockStore.self) private var store
  @Namespace private var transport
  @FocusState private var playFocused: Bool

  var body: some View {
    HStack(spacing: 56) {
      TVIconButton(symbol: "backward.end.fill", size: 80, fontSize: 30) {
        store.previous()
      }
      TVIconButton(
        symbol: store.isPlaying ? "pause.fill" : "play.fill",
        size: 104,
        fontSize: 40,
        filled: true
      ) {
        store.togglePlay()
      }
      .focused($playFocused)
      .prefersDefaultFocus(true, in: transport)
      TVIconButton(symbol: "forward.end.fill", size: 80, fontSize: 30) {
        store.skip()
      }
    }
    .padding(.top, 16)
    .focusScope(transport)
    .onAppear { playFocused = true }
  }
}

private struct TVZoneChipLabel: View {
  let name: String
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "hifispeaker.fill")
      Text(name)
      Image(systemName: "chevron.down")
        .font(.caption.weight(.semibold))
    }
    .font(.title3.weight(.medium))
    .foregroundStyle(isFocused ? Palette.onAccent : Palette.accent)
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(isFocused ? Color.white : Palette.surface.opacity(0.85))
    .clipShape(Capsule())
  }
}

private struct TVChipLabel: View {
  let title: String
  let symbol: String
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.title3.weight(.medium))
      .foregroundStyle(isFocused ? Palette.onAccent : Palette.primary)
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      .background(isFocused ? Color.white : Palette.surface.opacity(0.85))
      .clipShape(Capsule())
  }
}

private struct TVUpNextLabel: View {
  let title: String
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "list.bullet")
      Text(title)
        .lineLimit(1)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
    }
    .font(.title3)
    .foregroundStyle(isFocused ? Palette.onAccent : Palette.secondary)
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(isFocused ? Color.white : .clear)
    .clipShape(Capsule())
    .padding(.top, 12)
  }
}
