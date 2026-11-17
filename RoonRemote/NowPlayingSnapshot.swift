import Foundation

/// The same selected-room state feeds both system Now Playing and ActivityKit.
/// Radio/loading events can legitimately have no track metadata.
struct NowPlayingSnapshot: Equatable {
  var zoneID: String
  var zoneName: String
  var track: Track?
  var isPlaying: Bool

  init?(zone: Zone, isPlaying: Bool) {
    guard zone.state != .stopped, zone.track != nil || isPlaying else { return nil }
    zoneID = zone.id
    zoneName = zone.name
    track = zone.track
    self.isPlaying = isPlaying
  }

  var title: String {
    guard let track, !track.title.isEmpty else { return zoneName }
    return track.title
  }

  var artist: String { track?.artist ?? "" }

  /// Expect a replacement around the track boundary. Unknown-length streams
  /// and paused rooms use a ten-minute freshness lease instead.
  func staleDate(observedAt: Date) -> Date {
    guard isPlaying, let track, let duration = track.durationSeconds, duration > 0 else {
      return observedAt.addingTimeInterval(600)
    }
    let remaining = duration * (1 - min(1, max(0, track.progress)))
    return observedAt.addingTimeInterval(min(600, max(30, remaining + 45)))
  }
}
