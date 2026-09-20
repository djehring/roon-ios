import SwiftUI

/// Shared controls retain native focus on TV and normal touch targets on iOS.
enum CinemaLayout {
  #if os(tvOS)
  static let isTV = true
  static let inset: CGFloat = 56
  static let controlHeight: CGFloat = 64
  static let thumbnail: CGFloat = 88
  #else
  static let isTV = false
  static let inset: CGFloat = 24
  static let controlHeight: CGFloat = 48
  static let thumbnail: CGFloat = 64
  #endif
}

struct CinemaButtonStyle: ButtonStyle {
  var prominent = false
  var destructive = false

  func makeBody(configuration: Configuration) -> some View {
    Content(configuration: configuration, prominent: prominent, destructive: destructive)
  }

  private struct Content: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let destructive: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
      configuration.label
        .font(CinemaLayout.isTV ? .system(size: 23, weight: .semibold) : .body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: CinemaLayout.controlHeight)
        .padding(.horizontal, 14)
        .foregroundStyle(focused || prominent ? Palette.onAccent : destructive ? .red : Palette.primary)
        .background(focused ? .white : prominent ? Palette.accent : Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline, lineWidth: prominent ? 0 : 1) }
        .opacity(enabled ? configuration.isPressed ? 0.75 : 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
  }
}

struct CinemaArtwork: View {
  let capsule: TimeCapsule
  var preferAlbum = false
  var fitted = false
  @Environment(MockStore.self) private var store
  @State private var photograph: UIImage?

  private var preview: CapsuleImage? { capsule.montageFrames.first?.image ?? capsule.contextImage }
  private var albumData: Data? {
    if let cover = store.cinema.artwork(for: capsule.request.tracks) { return cover }
    guard let track = store.currentTrack, preferAlbum || capsule.request.tracks.contains(where: {
      RoonVoiceMatch.titlesMatch($0.track, track.title) && AISearchPlayback.artistsAlign($0.artist, track.artist)
    }) else { return nil }
    return store.imageData(for: track.imageKey, pixels: ArtworkCache.heroPixels)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Palette.surface
        if let picture = selectedImage {
          Image(uiImage: picture)
            .resizable()
            .aspectRatio(contentMode: fitted ? .fit : .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
          Image(systemName: "music.note.list")
            .font(.system(size: min(geometry.size.width * 0.28, 72), weight: .light))
            .foregroundStyle(Palette.accent)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(selectedImage == nil ? "Artwork loading" : "Cinema artwork")
    .accessibilityIdentifier(selectedImage == nil ? "cinema-artwork-loading" : "cinema-artwork-image")
    .task(id: capsule.id) {
      guard preferAlbum || capsule.montageFrames.isEmpty else { return }
      store.cinema.warmArtwork(tracks: capsule.request.tracks, zoneId: store.selectedZoneId, client: store.client)
    }
    .task(id: preview?.file) {
      photograph = nil
      guard let preview else { return }
      let result = try? await MontageImageLoader.previews.load(preview, client: store.client)
      guard !Task.isCancelled else { return }
      photograph = result
    }
  }

  private var selectedImage: UIImage? {
    let album = albumData.flatMap(UIImage.init(data:))
    return preferAlbum ? album ?? photograph : photograph ?? album
  }
}

struct CinemaRoomButton: View {
  @Environment(MockStore.self) private var store
  @State private var showingRooms = false

  var body: some View {
    Button { showingRooms = true } label: {
      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2.fill")
        Text(store.selectedZoneId.isEmpty ? "Choose a room" : "Music in \(store.selectedZone.name)")
          .lineLimit(1)
        Image(systemName: "chevron.down").font(.caption)
      }
      .font(CinemaLayout.isTV ? .title3 : .subheadline)
      .foregroundStyle(Palette.accent)
      .padding(.vertical, 12)
    }
    .buttonStyle(CinemaRoomButtonStyle())
    .sheet(isPresented: $showingRooms) {
      NavigationStack {
        List(store.zones) { zone in
          Button {
            store.selectZone(zone.id)
            showingRooms = false
          } label: {
            HStack {
              Label(zone.name, systemImage: RoomPresentation.symbol(for: zone.name))
              Spacer()
              if zone.id == store.selectedZoneId { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
            }
          }
        }
        .navigationTitle("Music in…")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingRooms = false } } }
      }
      .preferredColorScheme(.dark)
    }
  }
}


extension View {
  @ViewBuilder func cinemaPlainButton() -> some View {
    #if os(tvOS)
    tvUnplated()
    #else
    buttonStyle(.plain)
    #endif
  }

  @ViewBuilder func cinemaFocusSection() -> some View {
    #if os(tvOS)
    focusSection()
    #else
    self
    #endif
  }
}


private struct CinemaRoomButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Highlight(configuration: configuration)
  }
  private struct Highlight: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focused
    var body: some View {
      configuration.label.padding(.horizontal, 8)
        .background(focused ? Palette.surface : .clear)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(focused ? Palette.accent : .clear, lineWidth: 2) }
    }
  }
}
