import Testing

@Suite("Cover screensaver")
struct CoverScreensaverTests {
  @Test("a playing track with cached artwork earns the screen")
  func playingWithArtworkShows() {
    #expect(
      CoverScreensaver.canShow(
        hasArtwork: true,
        isPlaying: true,
        isPresenting: false,
        isAwaitingServer: false,
        voiceOverEnabled: false
      )
    )
  }

  @Test("nothing takes the screen without full-size cover art")
  func placeholderNeverShows() {
    #expect(
      !CoverScreensaver.canShow(
        hasArtwork: false,
        isPlaying: true,
        isPresenting: false,
        isAwaitingServer: false,
        voiceOverEnabled: false
      )
    )
  }

  @Test("paused music keeps the transport on screen")
  func pausedHidesScreensaver() {
    #expect(
      !CoverScreensaver.canShow(
        hasArtwork: true,
        isPlaying: false,
        isPresenting: false,
        isAwaitingServer: false,
        voiceOverEnabled: false
      )
    )
  }

  @Test("volume, queue, Cinema, and the first-paint overlay keep their place")
  func presentationsBlockScreensaver() {
    #expect(
      !CoverScreensaver.canShow(
        hasArtwork: true,
        isPlaying: true,
        isPresenting: true,
        isAwaitingServer: false,
        voiceOverEnabled: false
      )
    )
    #expect(
      !CoverScreensaver.canShow(
        hasArtwork: true,
        isPlaying: true,
        isPresenting: false,
        isAwaitingServer: true,
        voiceOverEnabled: false
      )
    )
  }

  @Test("VoiceOver users keep the controls they are reading")
  func voiceOverBlocksScreensaver() {
    #expect(
      !CoverScreensaver.canShow(
        hasArtwork: true,
        isPlaying: true,
        isPresenting: false,
        isAwaitingServer: false,
        voiceOverEnabled: true
      )
    )
  }

  @Test("the drift never pans past the edge of the artwork")
  func driftStaysInsideTheCover() {
    for waypoint in CoverScreensaver.path {
      #expect(waypoint.scale > 1, "a pan needs something to pan across")
      // Width is the tight axis: square art fills it exactly before the zoom,
      // where the same art overhangs a 16:9 height by half a screen.
      #expect(abs(waypoint.unitOffset.width) <= CoverScreensaver.safeUnitOffset(scale: waypoint.scale))
      #expect(
        abs(waypoint.unitOffset.height) <= CoverScreensaver.safeUnitOffset(
          scale: waypoint.scale,
          coverFill: CoverScreensaver.screenAspect
        )
      )
    }
  }

  @Test("every leg moves the camera")
  func consecutiveWaypointsDiffer() {
    for index in 0..<CoverScreensaver.path.count {
      #expect(CoverScreensaver.waypoint(at: index) != CoverScreensaver.waypoint(at: index + 1))
    }
  }

  @Test("the drift loops instead of ending")
  func waypointsWrap() {
    let count = CoverScreensaver.path.count
    #expect(CoverScreensaver.waypoint(at: count) == CoverScreensaver.waypoint(at: 0))
    #expect(CoverScreensaver.waypoint(at: count * 7 + 2) == CoverScreensaver.waypoint(at: 2))
    #expect(CoverScreensaver.waypoint(at: -1) == CoverScreensaver.waypoint(at: count - 1))
  }

  @Test("an unzoomed cover has nowhere to travel, and a zoom opens room on both sides")
  func safeOffsetAtRest() {
    #expect(CoverScreensaver.safeUnitOffset(scale: 1) == 0)
    #expect(CoverScreensaver.safeUnitOffset(scale: 0.5) == 0)
    #expect(abs(CoverScreensaver.safeUnitOffset(scale: 1.2) - 0.1) < 0.0001)
    // A square cover already overhangs a 16:9 screen by more than a third of its
    // height, so it can travel vertically without being zoomed at all.
    #expect(
      CoverScreensaver.safeUnitOffset(scale: 1, coverFill: CoverScreensaver.screenAspect) > 0.35
    )
  }

  @Test("the wait is a few seconds, and each move is slower than the wait")
  func timings() {
    #expect(CoverScreensaver.idleSeconds >= 5)
    #expect(CoverScreensaver.idleSeconds <= 15)
    #expect(CoverScreensaver.legSeconds > CoverScreensaver.idleSeconds)
  }
}
