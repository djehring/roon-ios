import SwiftUI

struct CinemaPreparationView: View {
  let capsule: TimeCapsule
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 600
      let artSize = max(100, min(compact ? geometry.size.width - 48 : CinemaLayout.isTV ? 360 : 520,
        geometry.size.height - (compact ? 440 : CinemaLayout.isTV ? 540 : 330)))
      VStack(spacing: compact ? 16 : 20) {
        HStack {
          Button {
            store.cinema.libraryAfterViewer = true
            dismiss()
          } label: { Label("Cinema", systemImage: "chevron.left").frame(minHeight: 44) }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
          Spacer()
          Text(capsule.title).font(.headline).lineLimit(1)
          Spacer()
          Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel("Close Cinema")
        }
        Spacer(minLength: 0)
        CinemaArtwork(capsule: capsule, preferAlbum: true, fitted: true)
          .frame(width: artSize, height: artSize)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        VStack(spacing: 10) {
          if let error = store.cinema.preparationError {
            Label("Pictures could not be updated", systemImage: "exclamationmark.triangle")
              .font(.headline).foregroundStyle(Palette.accent)
            Text(error).font(.subheadline).foregroundStyle(Palette.secondary)
            Button("Back to playlists") {
              store.cinema.libraryAfterViewer = true
              dismiss()
            }.buttonStyle(CinemaButtonStyle())
          } else {
            HStack(spacing: 12) {
              ProgressView().tint(Palette.accent)
              Text("Updating pictures…").font(.title3.weight(.semibold))
            }
            Text("Your montage will appear automatically.").font(.subheadline).foregroundStyle(Palette.secondary)
            Text(store.cinema.preparationMessage).font(.caption).foregroundStyle(Palette.secondary)
          }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 750)
        Spacer(minLength: 0)
        Divider()
        if compact {
          VStack(spacing: 16) {
            trackDetails
            transport
            CinemaRoomButton()
          }
        } else {
          HStack(spacing: 32) {
            trackDetails.frame(maxWidth: .infinity, alignment: .leading)
            transport.frame(maxWidth: 300)
            CinemaRoomButton().frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
        if let message = store.cinema.playbackMessage, store.cinema.playbackCapsuleId == capsule.id {
          Text(message).font(.caption).foregroundStyle(Palette.accent)
        }
      }
      .padding(compact ? 24 : CinemaLayout.isTV ? 56 : 36)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Palette.background).foregroundStyle(Palette.primary)
    #if os(tvOS)
    .onPlayPauseCommand { store.togglePlay() }
    .onExitCommand { store.cinema.libraryAfterViewer = true; dismiss() }
    #endif
  }

  private var trackDetails: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(store.currentTrack?.title ?? "Music is stopped")
        .font(CinemaLayout.isTV ? .system(size: 32, weight: .semibold) : .headline).lineLimit(1)
      Text(store.currentTrack.map { [$0.artist, $0.album].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "Watch pictures without starting music")
        .font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(1)
      if let track = store.currentTrack {
        HStack(spacing: 10) {
          Text(track.position).font(.caption.monospacedDigit())
          ProgressView(value: min(max(track.progress, 0), 1)).tint(Palette.accent)
          Text(track.remaining).font(.caption.monospacedDigit())
        }.foregroundStyle(Palette.secondary)
      }
    }
  }

  private var transport: some View {
    HStack(spacing: 18) {
      Button { store.previous() } label: { Image(systemName: "backward.end.fill") }
        .buttonStyle(CinemaButtonStyle()).accessibilityLabel("Previous track")
      Button { store.togglePlay() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill") }
        .buttonStyle(CinemaButtonStyle(prominent: true)).accessibilityLabel(store.isPlaying ? "Pause music" : "Play music")
      Button { store.skip() } label: { Image(systemName: "forward.end.fill") }
        .buttonStyle(CinemaButtonStyle()).accessibilityLabel("Next track")
    }
    .disabled(store.currentTrack == nil)
    .cinemaFocusSection()
  }
}
