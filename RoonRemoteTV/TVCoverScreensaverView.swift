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
          // Apple TV's own screen saver would otherwise appear over this one.
          .screenStaysAwake()
      }
      .task(id: showing) {
        guard !showing else { return }
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          guard canStart,
                TVRemoteActivity.shared.idleSeconds >= CoverScreensaver.idleSeconds
          else { continue }
          showing = true
          return
        }
      }
      .onChange(of: canStay) { _, stillAllowed in
        // A room that stops, or pausing with the remote's own play/pause button,
        // means the viewer wants the transport back.
        if !stillAllowed { showing = false }
      }
  }

  private var canStart: Bool {
    CoverScreensaver.canShow(
      hasArtwork: hasHeroArtwork,
      isPlaying: store.isPlaying,
      isPresenting: isPresenting,
      isAwaitingServer: store.showsFindingServer,
      voiceOverEnabled: voiceOver
    )
  }

  private var canStay: Bool {
    CoverScreensaver.canStay(
      isPlaying: store.isPlaying,
      isPresenting: isPresenting,
      isAwaitingServer: store.showsFindingServer,
      voiceOverEnabled: voiceOver
    )
  }

  private var isPresenting: Bool {
    store.showVolume || store.showQueue || isPresentingCinema
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
  @State private var cover: Cover?
  @State private var leg = 0

  /// The cover on screen, which is not always the playing track's: see
  /// `followTrack()`.
  private struct Cover {
    let imageKey: String
    let image: UIImage
  }

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
        if let cover {
          Image(uiImage: cover.image)
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
            .id(cover.imageKey)
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
    .animation(.easeInOut(duration: 0.5), value: store.currentTrack?.id)
    .task(id: imageKey) { await followTrack() }
    // One continuous move for the whole sitting. Restarting it with each song
    // would jolt the camera in the middle of a cross-fade.
    .task(id: reduceMotion) {
      guard !reduceMotion else { return }
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

  /// Keeps the cover that is on screen until the next one is fully in hand.
  ///
  /// A song's artwork reaches the cache a second or so after the song itself, so
  /// swapping to whatever is cached the instant the track changes would blink to
  /// black, or to a stretched list thumbnail, part way through a move.
  private func followTrack() async {
    guard let imageKey, imageKey != cover?.imageKey else { return }
    while !Task.isCancelled {
      if let image = heroCover(imageKey) {
        withAnimation(.easeInOut(duration: 1.2)) {
          cover = Cover(imageKey: imageKey, image: image)
        }
        return
      }
      // Asking is what starts the fetch when the store has not already.
      _ = store.imageData(for: imageKey, pixels: ArtworkCache.heroPixels)
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
    }
  }

  /// The cover at full size, or nothing. Unlike `imageData`, this never answers
  /// with the list thumbnail, which would be far too soft for a whole screen.
  private func heroCover(_ imageKey: String) -> UIImage? {
    guard let data = store.artwork.data(
      for: ArtworkCache.Key(imageKey: imageKey, pixels: ArtworkCache.heroPixels)
    ) else { return nil }
    return UIImage(data: data)
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
}
