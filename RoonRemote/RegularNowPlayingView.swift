import SwiftUI
import UIKit

/// The regular-width Now Playing experience. Portrait keeps the artwork above
/// the controls; a wide landscape or Stage Manager window moves them alongside
/// one another. Both arrangements sit over artwork-derived ambience and keep
/// the queue in an inspector rather than permanently surrendering detail width.
struct RegularNowPlayingView: View {
  @Environment(MockStore.self) private var store
  @State private var queuePresented = false

  var body: some View {
    GeometryReader { geometry in
      let mode = RegularNowPlayingLayout.mode(for: geometry.size.width)

      ZStack(alignment: .top) {
        backdrop
        content(mode: mode, width: geometry.size.width)
        topControls
          .padding(.horizontal, 24)
          .padding(.top, 12)
      }
    }
    .inspector(isPresented: $queuePresented) {
      QueueList(embedded: true)
        .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
    }
  }

  @ViewBuilder
  private func content(mode: RegularNowPlayingLayout, width: CGFloat) -> some View {
    switch mode {
    case .stacked:
      ScrollView {
        VStack(spacing: 30) {
          artwork(width: RegularNowPlayingLayout.artWidth(containerWidth: width, mode: mode))
          controls(alignment: .center)
            .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 72)
        .padding(.bottom, 28)
      }
    case .sideBySide:
      HStack(spacing: 56) {
        artwork(width: RegularNowPlayingLayout.artWidth(containerWidth: width, mode: mode))
        controls(alignment: .leading)
          .frame(maxWidth: 620, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(48)
    }
  }

  private var topControls: some View {
    HStack(spacing: 12) {
      Button {
        store.showZonePicker = true
      } label: {
        Label(store.selectedZone.name, systemImage: "hifispeaker.fill")
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 14)
          .frame(height: 38)
          .background(Palette.surface.opacity(0.82))
          .clipShape(Capsule())
          .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
      }
      .buttonStyle(.plain)

      Spacer()

      roundHeaderButton(label: "Volume", symbol: "speaker.wave.2.fill") {
        store.showVolume = true
      }
      roundHeaderButton(label: "Queue", symbol: "list.bullet") {
        queuePresented.toggle()
      }
    }
    .foregroundStyle(Palette.primary)
  }

  private func roundHeaderButton(
    label: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.body.weight(.medium))
        .frame(width: 38, height: 38)
        .background(Palette.surface.opacity(0.82))
        .clipShape(Circle())
        .overlay { Circle().stroke(Palette.hairline, lineWidth: 1) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  private func artwork(width: CGFloat) -> some View {
    CoverArt(
      title: store.currentTrack?.album ?? "empty",
      image: store.imageData(
        for: store.currentTrack?.imageKey,
        pixels: ArtworkCache.heroPixels
      ),
      corner: 18
    )
    .frame(width: width, height: width)
    .shadow(color: .black.opacity(0.38), radius: 32, y: 18)
    .animation(Motion.sheet, value: store.currentTrack?.id)
  }

  private func controls(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 22) {
      metadata(alignment: alignment)

      if let track = store.currentTrack {
        progress(track)
      }

      TransportControls()
        .padding(.top, 0)

      actionChips

      Button {
        queuePresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "list.bullet")
          Text(store.queue.first.map { "Up next  ·  \($0.title)" } ?? "Queue is empty")
            .lineLimit(1)
          Spacer(minLength: 12)
          Image(systemName: "sidebar.right")
            .font(.caption.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(Palette.secondary)
        .padding(14)
        .background(Palette.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.hairline, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func metadata(alignment: HorizontalAlignment) -> some View {
    let textAlignment: TextAlignment = alignment == .leading ? .leading : .center
    if let track = store.currentTrack {
      VStack(alignment: alignment, spacing: 8) {
        Text(track.title)
          .font(.system(size: 44, weight: .bold))
          .multilineTextAlignment(textAlignment)
          .lineLimit(2)
        Text(track.artist)
          .font(.title2)
          .foregroundStyle(Palette.secondary)
        Text(track.album)
          .font(.title3)
          .foregroundStyle(Palette.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    } else {
      VStack(alignment: alignment, spacing: 8) {
        Text("Nothing playing")
          .font(.system(size: 36, weight: .semibold))
        Text("Pick something from Library or Search")
          .font(.title3)
          .foregroundStyle(Palette.secondary)
      }
      .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
  }

  private func progress(_ track: Track) -> some View {
    VStack(spacing: 8) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(Palette.hairline)
          Capsule()
            .fill(Palette.accent)
            .frame(width: max(4, geometry.size.width * track.progress))
        }
      }
      .frame(height: 5)
      HStack {
        Text(track.position)
        Spacer()
        Text(track.remaining)
      }
      .font(.callout.monospacedDigit())
      .foregroundStyle(Palette.tertiary)
    }
  }

  private var actionChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        chip(label: "Story", symbol: "text.book.closed") {
          store.showStory = true
        }
        ForEach(store.toolbar) { action in
          chip(label: action.label, symbol: action.symbol) {
            store.runToolbar(action)
          }
        }
        ForEach(store.customActions) { action in
          chip(label: action.label, symbol: action.symbol) {
            store.runCustomAction(action)
          }
        }
      }
    }
  }

  private func chip(
    label: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(label, systemImage: symbol)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Palette.primary)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Palette.surface.opacity(0.82))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var backdrop: some View {
    if let data = store.imageData(
      for: store.currentTrack?.imageKey,
      pixels: ArtworkCache.heroPixels
    ), let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .blur(radius: 70)
        .opacity(0.36)
        .ignoresSafeArea()
        .overlay { backdropScrim }
    } else {
      let colors = CoverArt.colors(
        for: store.currentTrack?.album ?? "empty",
        scheme: .dark
      )
      LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        .opacity(0.28)
        .ignoresSafeArea()
        .overlay { backdropScrim }
    }
  }

  private var backdropScrim: some View {
    LinearGradient(
      colors: [Palette.background.opacity(0.42), Palette.background.opacity(0.90)],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}
