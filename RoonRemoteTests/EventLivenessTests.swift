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

  @Test("paused rooms wait longer than the bridge's 45 second heartbeat")
  func recentlyPausedSkips() {
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

  @Test("a dead stream recovers even when the last known room state was paused")
  func pausedDeadStreamRefreshes() {
    let now = Date()
    #expect(EventLiveness.shouldRefresh(isPlaying: false,
      lastEventAt: now.addingTimeInterval(-70), lastRefreshAt: nil, now: now))
  }

  @Test("other rooms and heartbeats cannot hide stale selected-room playback")
  func unrelatedEventsDoNotMaskAStaleRoom() {
    let now = Date()
    #expect(EventLiveness.shouldRefresh(isPlaying: true,
      lastEventAt: now, lastZoneEventAt: now.addingTimeInterval(-12),
      lastRefreshAt: nil, now: now))
  }

  @Test("a stream that never delivers its first event is retried")
  func missingFirstEventRefreshes() {
    let now = Date()
    #expect(EventLiveness.shouldRefresh(isPlaying: false,
      lastEventAt: nil, lastRefreshAt: now.addingTimeInterval(-70), now: now))
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
