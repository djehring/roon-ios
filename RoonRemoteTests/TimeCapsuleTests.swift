import Foundation
import Testing

@Suite("Time Capsule request and playback")
struct TimeCapsuleTests {
  @Test func preparationViewerSwitchesToItsResultWithoutChangingAnotherOpenCapsule() {
    let request = sample().request
    var preparation = CapsulePreparation(request: request)
    let waiting = preparation.placeholder
    #expect(waiting.scenes.isEmpty)
    #expect(waiting.request == request)
    #expect(preparation.resolve(waiting).id == waiting.id)
    var ready = sample()
    ready.id = "ready"
    preparation.result = ready
    #expect(preparation.resolve(waiting).id == ready.id)
    #expect(preparation.resolve(sample()).id == "test")
  }

  @Test func preparingNeverOpensAnOldCapsule() {
    #expect(CapsuleNowPlaying.select(preparing: true, current: playing, queue: [],
      associated: sample(), saved: [sample()]) == nil)
  }

  @Test func anotherPlaylistDoesNotReuseTheRoomCapsule() {
    var current = playing
    current.title = "Karma Chameleon"
    current.artist = "Culture Club"
    #expect(CapsuleNowPlaying.select(preparing: false, current: current, queue: [],
      associated: sample(), saved: [sample()]) == nil)
    #expect(CapsuleNowPlaying.select(preparing: false, current: nil, queue: [],
      associated: sample(), saved: [sample()]) == nil)
  }

  @Test func newlyCompletedCapsuleCanOpenWithoutRestartingMusic() {
    var old = sample()
    old.id = "old"
    old.request.tracks = []
    #expect(CapsuleNowPlaying.select(preparing: false, current: playing, queue: [],
      associated: old, saved: [sample()])?.id == "test")
  }

  @Test func upcomingMusicDistinguishesPlaylistsSharingASong() {
    let next = QueueItem(id: "next", title: "Modern Love", artist: "David Bowie", album: "", imageKey: nil)
    var new = sample()
    new.id = "new"
    new.request.tracks.append(.init(artist: next.artist, track: next.title, album: next.album))
    #expect(CapsuleNowPlaying.select(preparing: false, current: playing, queue: [next],
      associated: sample(), saved: [sample(), new])?.id == "new")
    #expect(CapsuleNowPlaying.select(preparing: false, current: playing, queue: [next],
      associated: sample(), saved: [sample()]) == nil)
  }

  @Test func matchingAssociationResumesAndSavedRebuildWins() {
    var rebuilt = sample()
    rebuilt.createdAt = "2026-09-18T00:00:00Z"
    var current = playing
    current.title = "Test track (Remastered)"
    #expect(CapsuleNowPlaying.select(preparing: false, current: current, queue: [],
      associated: sample(), saved: [rebuilt])?.createdAt == rebuilt.createdAt)
  }

  @Test func reopeningCapsuleResumesPhotoAndHoldButRebuildStartsFresh() {
    var memory = MontagePlaybackMemory()
    var playback = MontagePlayback()
    playback.advance(seconds: 19, playing: true, count: 5)
    memory.remember(playback, capsuleId: "capsule", revision: "original")
    let resumed = memory.resume(capsuleId: "capsule", revision: "original")
    #expect(resumed.index == 2)
    #expect(resumed.elapsed == 3)
    #expect(memory.resume(capsuleId: "capsule", revision: "rebuilt").index == 0)
    #expect(memory.resume(capsuleId: "another", revision: "original").index == 0)
  }
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
