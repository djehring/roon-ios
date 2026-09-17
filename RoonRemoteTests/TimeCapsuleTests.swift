import Foundation
import Testing

@Suite("Time Capsule request and playback")
struct TimeCapsuleTests {
  @Test func preservesArbitrarySearchAndAnchor() throws {
    let context = CapsuleSearchContext(query: "Brazilian jazz from the sixties", date: Date(timeIntervalSince1970: 1234567890))
    let request = CapsuleRequest(context: context, tracks: [suggestion])
    let restored = try JSONDecoder().decode(CapsuleRequest.self, from: JSONEncoder().encode(request))
    #expect(restored.query == context.query)
    #expect(restored.requestedAt == context.requestedAt)
    #expect(restored.tracks.first?.track == "Test track")
  }

  @Test func photographsAdvanceEveryEightSecondsAndContinueAcrossSongs() {
    var playback = MontagePlayback()
    playback.advance(seconds: 7, playing: true, count: 5)
    #expect(playback.index == 0)
    playback.advance(seconds: 1, playing: true, count: 5)
    #expect(playback.index == 1)
    // No title/artist/track ID enters this clock: a skip cannot reset it.
    playback.advance(seconds: 8, playing: true, count: 5)
    #expect(playback.index == 2)
  }

  @Test func pauseFreezesAndResumeKeepsTheRemainingHoldTime() {
    var playback = MontagePlayback()
    playback.advance(seconds: 5, playing: true, count: 3)
    playback.advance(seconds: 60, playing: false, count: 3)
    #expect(playback.index == 0)
    #expect(playback.elapsed == 5)
    playback.advance(seconds: 3, playing: true, count: 3)
    #expect(playback.index == 1)
    playback.advance(seconds: 16, playing: true, count: 3)
    #expect(playback.index == 0)
  }

  @Test func manualNavigationRestartsPhotoHoldAndWrapsBothWays() {
    var playback = MontagePlayback()
    playback.advance(seconds: 6, playing: true, count: 4)
    playback.move(-1, count: 4)
    #expect(playback.index == 3)
    #expect(playback.elapsed == 0)
    playback.move(1, count: 4)
    #expect(playback.index == 0)
    playback.advance(seconds: .infinity, playing: true, count: 4)
    #expect(playback.index == 0)
  }

  @Test func montageContainsDistinctActualPhotographsAndOmitsEmptyHeadlines() {
    var capsule = sample()
    capsule.contextImage = photograph("background")
    capsule.scenes[0].images = [photograph("one"), photograph("two")]
    capsule.scenes[1].images = [photograph("one"), photograph("three")]
    #expect(capsule.montageFrames.map(\.id) == ["one", "two", "three"])
    #expect(capsule.montageFrames.last?.scene.title == "Story 1")
  }

  @Test func legacyCapsulesCannotRepeatOneContextImageAsAnEntireMontage() {
    var capsule = sample()
    capsule.contextImage = photograph("background")
    #expect(capsule.montageFrames.isEmpty)
    capsule.scenes[0].image = photograph("one")
    capsule.scenes[1].image = photograph("one")
    #expect(capsule.montageFrames.count == 1)
    // An explicit empty replacement gallery must not revive an old image.
    capsule.scenes[0].images = []
    capsule.scenes[1].images = []
    #expect(capsule.montageFrames.isEmpty)
  }

  private func photograph(_ file: String) -> CapsuleImage {
    CapsuleImage(file: file, sourceUrl: URL(string: "https://example.org/photo")!,
      credit: "Archive", license: "Public domain", licenseUrl: "", date: "Photograph date", description: "Archive photograph")
  }

  private var suggestion: SuggestedTrack {
    .init(id: "test", title: "Test track", artist: "Test artist", album: "Test album", corrected: false)
  }
  private var playing: Track {
    .init(id: "test", title: "Test track", artist: "Test artist", album: "Test album", position: "0:00", remaining: "3:00", progress: 0)
  }
  private func sample() -> TimeCapsule {
    TimeCapsule(id: "test", title: "Request-specific programme", contextLabel: "Subject from the request",
      request: CapsuleRequest(context: CapsuleSearchContext(query: "Any request"), tracks: [suggestion]),
      createdAt: "2026-09-17T00:00:00Z",
      scenes: (0..<3).map { index in
        CapsuleScene(id: "\(index)", title: "Story \(index)", body: "A sourced summary.", dateLabel: "", scope: "Context", sources: [], trackIndices: [])
      })
  }
}
