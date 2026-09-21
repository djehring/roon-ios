import Foundation
import Testing

@Suite("Cinema music editing") @MainActor
struct CinemaMusicTests {
  private func track(_ title: String = "Song") -> CapsuleTrack {
    CapsuleTrack(artist: "Artist", track: title, album: "Album", imageKey: "cover", durationSeconds: 180,
      roonPath: CinemaMusicPath(hierarchy: "albums", steps: [CinemaMusicStep(title: "Album", index: 0)]), matchPolicy: "exact")
  }

  @Test func repeatedTracksHaveIndependentIdentityAndUndoRestoresTheExactOrder() throws {
    let source = [track(), track(), track("Finale")]
    let draft = CinemaMusicDraft(tracks: source)
    let original = draft.tracks
    #expect(Set(original.compactMap(\.entryId)).count == 3)
    draft.move(try #require(original[1].entryId), to: 0)
    #expect(draft.tracks.map(\.entryId) == [original[1].entryId, original[0].entryId, original[2].entryId])
    draft.remove(try #require(original[0].entryId))
    #expect(draft.tracks.count == 2)
    draft.undo(); draft.undo()
    #expect(draft.tracks == original)
    #expect(source.allSatisfy { $0.entryId == nil })
    #expect(draft.summary == "3 tracks · 9 min")
  }

  @Test func multiTrackDragAndAppendPreserveOrderAndRecordingIdentity() throws {
    let draft = CinemaMusicDraft(tracks: [track("A"), track("B"), track("C"), track("D")])
    draft.move(from: IndexSet([0, 2]), to: 4)
    #expect(draft.tracks.map(\.track) == ["B", "D", "A", "C"])
    let imported = draft.tracks[0]
    try draft.append([imported, imported])
    #expect(draft.tracks.suffix(2).map(\.track) == ["B", "B"])
    #expect(Set(draft.tracks.compactMap(\.entryId)).count == 6)
    #expect(draft.tracks.last?.roonPath == imported.roonPath)
    #expect(draft.tracks.last?.matchPolicy == "exact")
    draft.undo()
    #expect(draft.tracks.count == 4)
  }

  @Test func trackLimitFailsWithoutPartialImportAndCurrentTrackCanBeRestored() throws {
    let draft = CinemaMusicDraft(tracks: Array(repeating: track(), count: 1000))
    #expect(throws: PersonalCinemaError.self) { try draft.append([track()]) }
    #expect(draft.tracks.count == 1000)
    #expect(!draft.canUndo)
    let current = draft.tracks[0]
    draft.remove(try #require(current.entryId))
    draft.restoreCurrent(current)
    #expect(draft.tracks[0] == current)
  }

  @Test func musicRequestRoundTripsAndDoesNotDefaultToResearch() throws {
    let request = CapsuleRequest(title: "Evening", tracks: [track()], sourceLabel: "From playlist")
    let decoded = try JSONDecoder().decode(CapsuleRequest.self, from: JSONEncoder().encode(request))
    #expect(decoded == request)
    #expect(decoded.options?.mode == .artwork)
    #expect(decoded.options?.topics == [.albumCovers])
    #expect(decoded.clientRequestId != nil)
  }
}
