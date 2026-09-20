import SwiftUI
import UIKit

/// Hands Now Playing over to the cover art once the remote has been still, and
/// gives it back on the remote's back button.
struct TVCoverScreensaverPresentation: ViewModifier {
  @Environment(MockStore.self) private var store
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @State private var showing = false

  func body(content: Content) -> some View {
    let allowed = isAllowed
    content
      .fullScreenCover(isPresented: $showing, onDismiss: {
        // The back press that closed this is what starts the idle wait again,
        // so a modal dismissal that swallowed the press cannot reopen it.
        TVRemoteActivity.shared.note()
      }) {
        TVCoverScreensaverView()
      }
      .task(id: showing) {
        guard !showing else { return }
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          guard isAllowed,
                TVRemoteActivity.shared.idleSeconds >= CoverScreensaver.idleSeconds
          else { continue }
          showing = true
          return
        }
      }
      .onChange(of: allowed) { _, stillAllowed in
        // Pausing, or opening the queue from the screensaver's own play/pause
        // handler, means the viewer is back: return the controls to them.
        if !stillAllowed { showing = false }
      }
  }

  private var isAllowed: Bool {
    CoverScreensaver.canShow(
      hasArtwork: hasHeroArtwork,
      isPlaying: store.isPlaying,
      isPresenting: store.showVolume || store.showQueue || isPresentingCinema,
      isAwaitingServer: store.showsFindingServer,
      voiceOverEnabled: voiceOver
    )
  }

  /// Read from the cache rather than through `imageData`, which would start a
  /// fetch: a cover worth filling a television with is one already in hand at
  /// full size, not a list thumbnail stretched over 1080 lines.
  private var hasHeroArtwork: Bool {
    guard let imageKey = store.currentTrack?.imageKey else { return false }
    return store.artwork.contains(
      ArtworkCache.Key(imageKey: imageKey, pixels: ArtworkCache.heroPixels)
    )
  }

  private var isPresentingCinema: Bool {
    let cinema = store.cinema
    return cinema.showingLibrary || cinema.presented != nil || cinema.setup != nil
  }
}

/// The current track's cover, full screen, drifting.
struct TVCoverScreensaverView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var leg = 0

  private var imageKey: String? { store.currentTrack?.imageKey }
  private var waypoint: CoverScreensaver.Waypoint {
    guard !reduceMotion else {
      return CoverScreensaver.Waypoint(scale: 1, unitOffset: .zero)
    }
    return CoverScreensaver.waypoint(at: leg)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black
        if let data = store.imageData(for: imageKey, pixels: ArtworkCache.heroPixels),
           let ui = UIImage(data: data)
        {
          Image(uiImage: ui)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(waypoint.scale)
            .offset(
              x: waypoint.unitOffset.width * geometry.size.width,
              y: waypoint.unitOffset.height * geometry.size.height
            )
            // Square art drawn to fill a 16:9 screen already overhangs top and
            // bottom, and the drift adds to it. Clip to the screen, not to the
            // moved picture.
            .clipped()
            .id(imageKey)
            .transition(.opacity)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .ignoresSafeArea()
    .background(Color.black.ignoresSafeArea())
    .animation(.easeInOut(duration: 1.2), value: imageKey)
    .task(id: driftKey) {
      leg = 0
      guard !reduceMotion, imageKey != nil else { return }
      while !Task.isCancelled {
        withAnimation(.easeInOut(duration: CoverScreensaver.legSeconds)) { leg += 1 }
        do { try await Task.sleep(for: .seconds(CoverScreensaver.legSeconds)) } catch { return }
      }
    }
    .focusable()
    .focusEffectDisabled()
    .onExitCommand { dismiss() }
    .onPlayPauseCommand {
      store.resumeSync()
      store.togglePlay()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("cover-screensaver")
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isImage)
    .accessibilityAction(named: "Show Now Playing") { dismiss() }
  }

  /// A new track starts its own move, from the top of the loop.
  private var driftKey: String { [imageKey ?? "", reduceMotion ? "still" : "drift"].joined(separator: "|") }

  private var label: String {
    guard let track = store.currentTrack else { return "Album cover" }
    return "Cover of \(track.album.isEmpty ? track.title : track.album) by \(track.artist)"
  }
}
