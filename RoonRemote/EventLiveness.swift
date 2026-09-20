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

  static func shouldRefresh(
    isPlaying: Bool,
    lastEventAt: Date?,
    lastRefreshAt: Date?,
    now: Date = Date()
  ) -> Bool {
    guard isPlaying else { return false }
    guard let lastEventAt, now.timeIntervalSince(lastEventAt) >= quietInterval else {
      return false
    }
    if let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) < refreshCooldown {
      return false
    }
    return true
  }
}
