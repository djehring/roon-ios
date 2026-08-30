import Testing

@Suite("Keyboard playback adjustments")
struct PlaybackAdjustmentTests {
  @Test("raises volume by the requested delta")
  func raisesVolume() {
    #expect(
      PlaybackAdjustment.volume(current: 40, minimum: 0, maximum: 100, delta: 2) == 42
    )
  }

  @Test("lowers volume by the requested delta")
  func lowersVolume() {
    #expect(
      PlaybackAdjustment.volume(current: 40, minimum: 0, maximum: 100, delta: -2) == 38
    )
  }

  @Test("clamps at the output maximum")
  func clampsAtMaximum() {
    #expect(
      PlaybackAdjustment.volume(current: 99, minimum: 0, maximum: 100, delta: 2) == 100
    )
  }

  @Test("clamps at the output minimum")
  func clampsAtMinimum() {
    #expect(
      PlaybackAdjustment.volume(current: 1, minimum: 0, maximum: 100, delta: -2) == 0
    )
  }

  @Test("respects outputs with a nonzero range")
  func nonzeroRange() {
    #expect(
      PlaybackAdjustment.volume(current: -29, minimum: -30, maximum: 0, delta: -2) == -30
    )
  }
}
