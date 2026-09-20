import Foundation
import Testing

@Suite("Event liveness")
struct EventLivenessTests {
  @Test("a quiet playing stream is refreshed even when the phone is locked")
  func quietPlayingRefreshes() {
    let now = Date()
    #expect(
      EventLiveness.shouldRefresh(
        isPlaying: true,
        lastEventAt: now.addingTimeInterval(-12),
        lastRefreshAt: now.addingTimeInterval(-12),
        now: now
      )
    )
  }

  @Test("fresh ticks are left alone")
  func recentEventSkips() {
    let now = Date()
    #expect(
      !EventLiveness.shouldRefresh(
        isPlaying: true,
        lastEventAt: now.addingTimeInterval(-2),
        lastRefreshAt: nil,
        now: now
      )
    )
  }

  @Test("paused rooms do not reconnect")
  func pausedSkips() {
    let now = Date()
    #expect(
      !EventLiveness.shouldRefresh(
        isPlaying: false,
        lastEventAt: now.addingTimeInterval(-30),
        lastRefreshAt: nil,
        now: now
      )
    )
  }

  @Test("a refresh is not repeated until the cooldown passes")
  func cooldownSkips() {
    let now = Date()
    #expect(
      !EventLiveness.shouldRefresh(
        isPlaying: true,
        lastEventAt: now.addingTimeInterval(-20),
        lastRefreshAt: now.addingTimeInterval(-4),
        now: now
      )
    )
  }
}
