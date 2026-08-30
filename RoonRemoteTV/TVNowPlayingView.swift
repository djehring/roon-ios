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

        VStack(alignment: .leading, spacing: 28) {
          HStack(spacing: 16) {
            Button {
              store.selectedTab = .rooms
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "hifispeaker.fill")
                Text(store.selectedZone.name)
                Image(systemName: "chevron.down")
                  .font(.caption.weight(.semibold))
              }
              .font(.title3.weight(.medium))
              .padding(.horizontal, 20)
              .padding(.vertical, 12)
              .background(Palette.surface.opacity(0.85))
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            headerButton(symbol: "speaker.wave.2.fill") {
              store.showVolume = true
            }
            headerButton(symbol: "list.bullet") {
              store.showQueue = true
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
              HStack(spacing: 12) {
                Image(systemName: "list.bullet")
                Text(store.queue.first.map { "Up next  ·  \($0.title)" } ?? "Queue")
                  .lineLimit(1)
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
              }
              .font(.title3)
              .foregroundStyle(Palette.secondary)
              .padding(.top, 8)
            }
            .buttonStyle(.plain)
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

            HStack(spacing: 20) {
              secondaryChip(title: "Volume", symbol: "speaker.wave.2.fill") {
                store.showVolume = true
              }
              secondaryChip(title: "Queue", symbol: "list.bullet") {
                store.showQueue = true
              }
            }
            .padding(.top, 8)
          }
        }
        .frame(maxWidth: 620, alignment: .leading)
      }
      .padding(64)
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

  private func headerButton(symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title3.weight(.medium))
        .frame(width: 56, height: 56)
        .background(Palette.surface.opacity(0.85))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }

  private func secondaryChip(title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.title3.weight(.medium))
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.85))
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
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
        Text(track.remaining)
      }
      .font(.callout)
      .foregroundStyle(Palette.tertiary)
    }
    .padding(.top, 4)
  }
}

struct TVTransportControls: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    HStack(spacing: 40) {
      Button { store.previous() } label: {
        Image(systemName: "backward.end.fill")
          .font(.system(size: 32))
          .frame(width: 72, height: 72)
      }
      .buttonStyle(.plain)

      Button { store.togglePlay() } label: {
        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 40))
          .frame(width: 96, height: 96)
          .background(Palette.accent)
          .foregroundStyle(Palette.onAccent)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      Button { store.skip() } label: {
        Image(systemName: "forward.end.fill")
          .font(.system(size: 32))
          .frame(width: 72, height: 72)
      }
      .buttonStyle(.plain)
    }
    .foregroundStyle(Palette.primary)
    .padding(.top, 8)
  }
}
