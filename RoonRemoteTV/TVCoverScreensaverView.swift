import SwiftUI
import UIKit

/// Hands Now Playing over to the cover art once the remote has been still, and
/// gives it back on the remote's back button.
struct TVCoverScreensaverPresentation: ViewModifier {
  @Environment(MockStore.self) private var store
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @State private var showing = false

  func body(content: Content) -> some View {
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
      .onChange(of: isAllowed) { _, stillAllowed in
        // A room that stops, or pausing with the remote's own play/pause button,
        // means the viewer wants the transport back.
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
            .accessibilityHidden(true)
        }
        if let track = store.currentTrack {
          scrim
          caption(track)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .ignoresSafeArea()
    .animation(.easeInOut(duration: 1.2), value: imageKey)
    .animation(.easeInOut(duration: 0.5), value: store.currentTrack?.id)
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
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("cover-screensaver")
    .accessibilityAction(named: "Show Now Playing") { dismiss() }
  }

  /// Only the foot of the picture is darkened, enough to carry white text over a
  /// cover that happens to be pale down there, and no more.
  ///
  /// The stops ease the darkening in. A plain two-stop gradient turns on at a
  /// constant rate from its first pixel, which draws a visible seam across the
  /// artwork where it begins.
  private var scrim: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black.opacity(0.12), location: 0.45),
        .init(color: .black.opacity(0.8), location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: 480)
    .frame(maxHeight: .infinity, alignment: .bottom)
    .accessibilityHidden(true)
  }

  private func caption(_ track: Track) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(track.title)
        .font(.system(size: 52, weight: .bold))
        .lineLimit(2)
      Text(track.artist)
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
    }
    .contentTransition(.opacity)
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
    .frame(maxWidth: 1100, alignment: .leading)
    // The inset the rest of the Apple TV app uses, which keeps the words clear
    // of a set that overscans.
    .padding(64)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }

  /// A new track starts its own move, from the top of the loop.
  private var driftKey: String { "\(imageKey ?? "none")-\(reduceMotion)" }
}
