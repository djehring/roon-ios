import CoreGraphics
import Foundation

/// Rules and motion for the full-screen cover art Apple TV drifts into when the
/// remote has been still on Now Playing.
///
/// The numbers live apart from the view so the drift can be proved to stay
/// inside the artwork: a pan that runs past the edge of the picture shows the
/// background through it, which on a 16:9 screen reads as a glitch rather than
/// as a camera move.
enum CoverScreensaver {
  /// Quiet remote time before the cover takes the screen. Long enough that
  /// stepping between the transport buttons never triggers it, short enough to
  /// still feel like the room settling into the music.
  static let idleSeconds: TimeInterval = 8

  /// Seconds to travel between two waypoints. One slow leg, so the move is felt
  /// rather than watched.
  static let legSeconds: Double = 16

  /// A point in the drift: how far the artwork is enlarged, and where it sits as
  /// a fraction of the screen.
  struct Waypoint: Equatable {
    let scale: CGFloat
    let unitOffset: CGSize
  }

  /// The drift is a closed loop, so it can run for as long as the music does
  /// without ever cutting back to the start.
  static let path: [Waypoint] = [
    Waypoint(scale: 1.05, unitOffset: CGSize(width: -0.015, height: -0.05)),
    Waypoint(scale: 1.16, unitOffset: CGSize(width: 0.03, height: 0.04)),
    Waypoint(scale: 1.08, unitOffset: CGSize(width: 0.025, height: -0.03)),
    Waypoint(scale: 1.18, unitOffset: CGSize(width: -0.035, height: 0.05)),
  ]

  /// The waypoint for a leg counter that only ever grows.
  static func waypoint(at step: Int) -> Waypoint {
    let index = ((step % path.count) + path.count) % path.count
    return path[index]
  }

  /// Apple TV draws in 16:9. Square art scaled to fill the width therefore
  /// overhangs the height by that ratio before the drift adds anything.
  static let screenAspect: CGFloat = 16 / 9

  /// How far the cover can move along one axis, as a fraction of the screen,
  /// before an edge of the picture comes into view.
  ///
  /// `coverFill` is how much of that axis the unscaled artwork already covers:
  /// 1 across the width it fills exactly, `screenAspect` down the height. What
  /// is left over is split between the two sides.
  static func safeUnitOffset(scale: CGFloat, coverFill: CGFloat = 1) -> CGFloat {
    max(0, (coverFill * scale - 1) / 2)
  }

  /// Whether the cover may take over the screen.
  ///
  /// Artwork is required because the placeholder gradient drifting across a
  /// television says nothing about what is playing. Anything already presented
  /// over Now Playing — volume, queue, Cinema, the first-paint overlay — keeps
  /// its place, and VoiceOver users are left with the controls they are reading.
  static func canShow(
    hasArtwork: Bool,
    isPlaying: Bool,
    isPresenting: Bool,
    isAwaitingServer: Bool,
    voiceOverEnabled: Bool
  ) -> Bool {
    guard hasArtwork, isPlaying else { return false }
    return !isPresenting && !isAwaitingServer && !voiceOverEnabled
  }
}
