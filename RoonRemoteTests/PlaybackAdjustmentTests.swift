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

@Suite("Time code parsing")
struct TimeCodeTests {
  @Test("parses mm:ss")
  func parsesMinutesSeconds() {
    #expect(TimeCode.seconds(from: "1:18") == 78)
    #expect(TimeCode.seconds(from: "4:39") == 279)
  }

  @Test("parses h:mm:ss")
  func parsesHours() {
    #expect(TimeCode.seconds(from: "1:02:03") == 3723)
  }

  @Test("formats seconds")
  func formats() {
    #expect(TimeCode.string(from: 78) == "1:18")
    #expect(TimeCode.string(from: 3723) == "1:02:03")
  }

  @Test("derives duration from percentage when length is missing")
  func durationFromPercentage() {
    #expect(
      TimeCode.durationSeconds(length: nil, seekPosition: "1:18", seekPercentage: 50) == 156
    )
  }
}
