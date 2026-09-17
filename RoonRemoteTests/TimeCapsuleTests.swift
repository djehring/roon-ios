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

  @Test func followsSeekWithoutAdvancingMusic() {
    let capsule = sample()
    var track = playing
    track.position = "0:29"
    #expect(capsule.sceneIndex(for: track) == 0)
    track.position = "0:30"
    #expect(capsule.sceneIndex(for: track) == 1)
    track.position = "0:05"
    #expect(capsule.sceneIndex(for: track) == 0)
  }

  @Test func rejectsUnrelatedMusicAndAmbiguousRecordings() {
    var track = playing
    track.artist = "Another artist"
    #expect(sample().sceneIndex(for: track) == nil)
    var duplicate = sample()
    duplicate.request.tracks.append(duplicate.request.tracks[0])
    #expect(duplicate.sceneIndex(for: playing) == nil)
  }

  @Test func filtersScenesForCurrentArtistAndHandlesEmptyProgramme() {
    var capsule = sample()
    capsule.scenes[0].trackIndices = [1]
    #expect(capsule.sceneIndex(for: playing) == 1)
    capsule.scenes = []
    #expect(capsule.sceneIndex(for: playing) == nil)
    #expect(TimeCapsule.seconds("1:02:03") == 3723)
    #expect(TimeCapsule.seconds("invalid") == 0)
    #expect(TimeCapsule.seconds("invalid:30") == 0)
    #expect(TimeCapsule.seconds("1::30") == 0)
    #expect(TimeCapsule.seconds("1:90") == 0)
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
