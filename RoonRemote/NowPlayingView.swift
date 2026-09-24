import SwiftUI

struct NowPlayingView: View {
  /// The compact root has nowhere else to put the playback sheets, so Now
  /// Playing presents them. The regular root presents them itself, above the
  /// split view, so the mini player can reach them from any destination.
  var presentsSheets = true

  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize

  var body: some View {
    GeometryReader { geo in
      let wide = geo.size.width > 700
      ZStack {
        Palette.background.ignoresSafeArea()
        if wide {
          HStack(spacing: 0) {
            phoneColumn
              .frame(maxWidth: .infinity)
            Divider().background(Palette.hairline)
            QueueList(embedded: true)
              .frame(width: min(380, geo.size.width * 0.4))
          }
        } else {
          phoneColumn
        }
      }
    }
    .playbackSheets(enabled: presentsSheets)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("now-playing-screen")
  }

  private var phoneColumn: some View {
    VStack(spacing: 0) {
      header
      Spacer(minLength: 12)
      art
      Spacer(minLength: 16)
      metadata
      progress
      TransportControls()
      chips
      if store.showQueuePeek {
        queuePeek
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .padding(.bottom, 8)
  }

  private var header: some View {
    HStack {
      Button {
        store.showZonePicker = true
      } label: {
        HStack(spacing: 6) {
          Text(store.selectedZone.name)
            .font(.subheadline.weight(.medium))
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Palette.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.surface)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
      }
      Spacer()
      Button {
        store.showVolume = true
      } label: {
        Image(systemName: "speaker.wave.2.fill")
          .font(.body)
          .foregroundStyle(Palette.primary)
          .frame(width: 36, height: 36)
          .background(Palette.surface)
          .clipShape(Circle())
          .overlay { Circle().stroke(Palette.hairline, lineWidth: 1) }
      }
    }
  }

  private var art: some View {
    CoverArt(
      title: store.currentTrack?.album ?? "empty",
      image: store.imageData(
        for: store.currentTrack?.imageKey,
        pixels: ArtworkCache.heroPixels
      ),
      corner: 12
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: Layout.heroArtWidth(hSize))
    .animation(Motion.sheet, value: store.currentTrack?.id)
  }

  @ViewBuilder
  private var metadata: some View {
    if let track = store.currentTrack {
      VStack(spacing: 6) {
        Text(track.title)
          .font(.system(size: 28, weight: .semibold))
          .multilineTextAlignment(.center)
        Text("on \(track.album)")
          .font(.system(size: 16))
          .foregroundStyle(Palette.secondary)
        NowPlayingArtistLinks(track: track, showsByPrefix: true)
          .font(.system(size: 16))
      }
    } else {
      Text("Nothing playing")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(Palette.secondary)
        .padding(.vertical, 12)
    }
  }

  @ViewBuilder
  private var progress: some View {
    if let track = store.currentTrack {
      ProgressScrubber(track: track) { progress in
        store.seek(toProgress: progress)
      }
      .padding(.top, 10)
    }
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chipButton(label: "Story", symbol: "text.book.closed") {
          store.showStory = true
        }
        chipButton(label: "Cinema", symbol: "sparkles.tv") {
          store.cinema.openLibrary()
        }
        ForEach(store.toolbar) { action in
          chipButton(label: action.label, symbol: action.symbol) {
            store.runToolbar(action)
          }
        }
        ForEach(store.customActions) { action in
          chipButton(label: action.label, symbol: action.symbol) {
            store.runCustomAction(action)
          }
        }
      }
    }
    .padding(.top, 8)
  }

  private func chipButton(
    label: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(label, systemImage: symbol)
        .font(.footnote.weight(.medium))
        .foregroundStyle(Palette.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surface)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
    }
  }

  private var queuePeek: some View {
    Button {
      store.showQueue = true
    } label: {
      HStack {
        Image(systemName: "list.bullet")
        Text(store.upNext.map { "Up next  \($0.title)" } ?? "Nothing up next")
          .lineLimit(1)
        Spacer()
        Image(systemName: "chevron.up")
          .font(.caption)
      }
      .font(.subheadline)
      .foregroundStyle(Palette.secondary)
      .padding(12)
      .background(Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Palette.hairline, lineWidth: 1)
      }
    }
    .padding(.top, 10)
  }

}

struct NowPlayingArtistLinks: View {
  @Environment(MockStore.self) private var store
  let track: Track
  var showsByPrefix = false
  var alignment: HorizontalAlignment = .center

  var body: some View {
    let names = store.artistNames(for: track)
    ArtistCreditLayout(alignment: alignment) {
      ForEach(Array(names.enumerated()), id: \.offset) { index, name in
        Button {
          store.openArtistDiscography(name)
        } label: {
          (Text(showsByPrefix && index == 0 ? "by " : "").foregroundColor(Palette.secondary)
            + Text(name).underline().foregroundColor(Palette.accent)
            + Text(index < names.count - 1 ? "," : "").foregroundColor(Palette.secondary))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityHint("Opens artist discography in Library")
        .accessibilityIdentifier(index == 0 ? "now-playing-artist-link" : "now-playing-artist-link-\(index)")
      }
    }
    .multilineTextAlignment(alignment == .leading ? .leading : .center)
    .task(id: NowPlayingAlbum(track: track)) { await store.loadArtistCredits(for: track) }
  }
}

/// Wrap whole artist links, keeping every name independently tappable.
private struct ArtistCreditLayout: SwiftUI.Layout {
  var alignment: HorizontalAlignment
  private let spacing: CGFloat = 4

  private func rows(width: CGFloat, subviews: Subviews) -> [[Int]] {
    var rows: [[Int]] = []
    var used: CGFloat = 0
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
      if rows.isEmpty || used + spacing + size.width > width {
        rows.append([index])
        used = size.width
      } else {
        rows[rows.count - 1].append(index)
        used += spacing + size.width
      }
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
    let height = rows(width: width, subviews: subviews).reduce(CGFloat.zero) { total, row in
      total + (row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0)
    }
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(width: bounds.width, subviews: subviews) {
      let sizes = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }
      let width = sizes.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * spacing
      var x = bounds.minX + (alignment == .leading ? 0 : (bounds.width - width) / 2)
      for (index, size) in zip(row, sizes) {
        subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
          proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += sizes.map(\.height).max() ?? 0
    }
  }
}

private extension MockStore {
  var showQueuePeek: Bool {
    true
  }
}

struct TransportControls: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    HStack(spacing: 36) {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.previous()
      } label: {
        Image(systemName: "backward.end.fill")
          .font(.system(size: 22))
          .frame(width: 44, height: 44)
      }
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.togglePlay()
      } label: {
        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 28))
          .frame(width: 64, height: 64)
          .background(Palette.accent)
          .foregroundStyle(Palette.onAccent)
          .clipShape(Circle())
      }
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.skip()
      } label: {
        Image(systemName: "forward.end.fill")
          .font(.system(size: 22))
          .frame(width: 44, height: 44)
      }
    }
    .foregroundStyle(Palette.primary)
    .padding(.top, 18)
  }
}
