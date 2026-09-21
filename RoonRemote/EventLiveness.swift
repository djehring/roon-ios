import Foundation

/// Whether a half-open SSE stream should be torn down and started again.
///
/// Zone ticks arrive about once a second while something is playing. Ten
/// seconds of silence means the stream is dead. The phone being locked is
/// not a reason to skip this: that is when the lock-screen card needs a
/// live stream the most.
enum EventLiveness {
  static let quietInterval: TimeInterval = 10
  static let refreshCooldown: TimeInterval = 10
  // The bridge sends a ping every 45 seconds, including while rooms are paused.
  static let idleQuietInterval: TimeInterval = 65

  static func shouldRefresh(
    isPlaying: Bool,
    lastEventAt: Date?,
    lastZoneEventAt: Date? = nil,
    lastRefreshAt: Date?,
    now: Date = Date()
  ) -> Bool {
    let lastUpdate = (isPlaying ? lastZoneEventAt : nil) ?? lastEventAt ?? lastRefreshAt
    let timeout = isPlaying ? quietInterval : idleQuietInterval
    guard let lastUpdate, now.timeIntervalSince(lastUpdate) >= timeout else {
      return false
    }
    if let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) < refreshCooldown {
      return false
    }
    return true
  }
}
