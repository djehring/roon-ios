import Foundation
import Testing

@Suite("Siri music requests")
struct SiriMusicRequestTests {
  @Test(arguments: ["Life on Mars", "jazz in the 1960s", "songs on the radio", "Live in the USA"])
  func preservesMusicPrepositions(_ phrase: String) {
    let request = PlayRequest.parse(phrase, roomNames: ["Kitchen", "Living Room"])
    #expect(request.what == phrase)
    #expect(request.room == nil)
  }

  @Test func removesOnlyKnownTrailingRoom() {
    let request = PlayRequest.parse("  jazz in the 1960s in the KITCHEN  ", roomNames: ["Kitchen"])
    #expect(request.what == "jazz in the 1960s")
    #expect(request.room == "Kitchen")
    let longest = PlayRequest.parse("Radio 3 on the Living Room", roomNames: ["Room", "Living Room"])
    #expect(longest.what == "Radio 3")
    #expect(longest.room == "Living Room")
  }

  @Test func preservesWholeQueryWithoutRooms() {
    #expect(PlayRequest.parse("music in the 1970s", roomNames: []).what == "music in the 1970s")
  }

  @Test func namesTheRoomSeparatelyFromTheMusic() {
    let request = PlayRequest.parse("British jazz from the 1960s in Office", roomNames: ["Kitchen", "Office"])
    #expect(request.what == "British jazz from the 1960s")
    #expect(request.room == "Office")
    #expect(PlayRequest.parse("British jazz from the 1960s", roomNames: ["Office"]).room == nil)
  }

  @Test func siriAIKeepsNamedRoomWhenItIncludesTheAppName() {
    let request = SiriMusicRequest.parse("British jazz from the 1960s in Office with House Remote", roomNames: ["Office"])
    #expect(request.query == "British jazz from the 1960s")
    #expect(request.roomName == "Office")
    #expect(!request.isFollowUp)
  }

  @Test(arguments: ["Play in Office with House Remote", "Play in the Office", "Play that in Office", "Office", "in Office"])
  func siriAIRoomReplyReusesMusic(_ phrase: String) {
    let request = SiriMusicRequest.parse(phrase, roomNames: ["Office"])
    #expect(request.isFollowUp)
    #expect(request.roomName == "Office")
  }

  @Test func siriAIKeepsRealSongTitlesAndRequiresRoomForBareFollowUp() {
    let title = SiriMusicRequest.parse("Play That Funky Music in Office", roomNames: ["Office"])
    #expect(title.query == "Play That Funky Music")
    #expect(!title.isFollowUp)
    let followUp = SiriMusicRequest.parse("play that", roomNames: ["Office"])
    #expect(followUp.isFollowUp)
    #expect(followUp.roomName == nil)
  }
}

@MainActor
@Suite("Siri AI search and playback")
struct SiriMusicTests {
  private func track(_ name: String, error: String? = nil) -> SuggestedTrack {
    SuggestedTrack(id: name, title: name, artist: "Artist", album: "Album", error: error, corrected: false)
  }

  @Test func sendsTheFullQueryAndPreservesResultOrder() async throws {
    var submitted = ""
    let result = try await AIMusicSearch.search("  British jazz from the 1960s  ") { query in
      submitted = query
      return [
        SuggestedTrackPayload(artist: "[[123|Artist]]", album: "Album", track: "First", wasAutoCorrected: true),
        SuggestedTrackPayload(artist: "Artist", album: "Album", track: "Second", error: "Unavailable"),
      ]
    }
    #expect(submitted == "British jazz from the 1960s")
    #expect(result.map(\.title) == ["First", "Second"])
    #expect(result.first?.artist == "Artist")
    #expect(result.first?.corrected == true)
    #expect(result.last?.error == "Unavailable")
  }

  @Test func emptyRequestDoesNotCallBridge() async {
    var called = false
    await #expect(throws: SiriMusicError.self) {
      _ = try await AIMusicSearch.search(" \n ") { _ in called = true; return [] }
    }
    #expect(!called)
  }

  @Test func missingKeyIsReported() async {
    await #expect(throws: RoonAPIError.self) {
      _ = try await AIMusicSearch.search("quiet jazz") { _ in throw RoonAPIError.missingOpenAI }
    }
  }

  @Test func playsEntireOrderedSelectionInCapturedRoom() async throws {
    var room = ""
    var titles: [String] = []
    let result = try await AIMusicSearch.play(
      [track("First"), track("Unavailable", error: "Not found"), track("Last"), track("First")],
      zoneId: "kitchen-id"
    ) { zone, tracks in
      room = zone
      titles = tracks.compactMap { $0["track"] }
      return []
    }
    #expect(room == "kitchen-id")
    #expect(titles == ["First", "Last", "First"])
    #expect(result.dialog(room: "Kitchen") == "Playing 3 tracks in Kitchen. Some tracks could not be played.")
  }

  @Test func partialPlaybackReportsMissingTracks() async throws {
    let result = try await AIMusicSearch.play([track("First"), track("Last")], zoneId: "room") { _, _ in
      [SuggestedTrackPayload(artist: "Artist", album: "Corrected album", track: "Last", error: "Not found")]
    }
    #expect(result.tracks.last?.error == "Not found")
    #expect(result.dialog(room: "Kitchen") == "Playing 1 track in Kitchen. Some tracks could not be played.")
  }

  @Test func allMissingNeverReportsSuccess() async {
    await #expect(throws: SiriMusicError.self) {
      _ = try await AIMusicSearch.play([track("First")], zoneId: "room") { _, _ in
        [SuggestedTrackPayload(artist: "Artist", album: "Other album", track: "First", error: "Missing")]
      }
    }
  }

  @Test func emptySelectionDoesNotReplaceQueue() async {
    var called = false
    await #expect(throws: SiriMusicError.self) {
      _ = try await AIMusicSearch.play([track("Failed", error: "Missing")], zoneId: "room") { _, _ in
        called = true
        return []
      }
    }
    #expect(!called)
  }

  @Test func bridgeFailurePropagates() async {
    await #expect(throws: URLError.self) {
      _ = try await AIMusicSearch.play([track("First")], zoneId: "room") { _, _ in
        throw URLError(.notConnectedToInternet)
      }
    }
  }

  @Test func cancelledPlaybackDoesNotSendCommand() async {
    var called = false
    let task = Task {
      try await AIMusicSearch.play([track("First")], zoneId: "room") { _, _ in
        called = true
        return []
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(!called)
  }

  @Test func resolvesSameSelectionAfterRelaunchWithoutResearch() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "selections.json")
    let original = SiriMusicSelection(context: CapsuleSearchContext(query: "this week in 1975"),
      tracks: [track("First"), track("Last")], zoneId: "room-id", roomName: "Kitchen", bridgeScope: "bridge:3000")
    try SiriMusicSelections(fileURL: file).save(original)
    let restored = SiriMusicSelections(fileURL: file).selection(id: original.id, bridgeScope: "bridge:3000")
    #expect(restored?.tracks == original.tracks)
    #expect(restored?.context == original.context)
    #expect(restored?.zoneId == "room-id")
    #expect(SiriMusicSelections(fileURL: file).selection(id: original.id, bridgeScope: "other:3000") == nil)
    #expect(SiriMusicSelections(fileURL: file).selection(id: "missing", bridgeScope: "bridge:3000") == nil)
  }

  @Test func selectionCacheIsBounded() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SiriMusicSelections(fileURL: directory.appending(path: "selections.json"))
    for index in 0..<21 {
      let selection = SiriMusicSelection(id: "\(index)", context: CapsuleSearchContext(query: "Music \(index)"),
        tracks: [track("Track")], zoneId: "room", roomName: "Room", bridgeScope: "bridge")
      try cache.save(selection)
    }
    #expect(cache.selection(id: "0", bridgeScope: "bridge") == nil)
    #expect(cache.selection(id: "20", bridgeScope: "bridge") != nil)
  }

  @Test func onlyExplicitRoomsCanBeUsedForPlayback() throws {
    let unresolved = SiriMusicSelection(context: CapsuleSearchContext(query: "British jazz"),
      tracks: [track("First")], zoneId: "", roomName: "", bridgeScope: "bridge")
    #expect(!unresolved.hasRoom)
    let office = Zone(id: "office", name: "Office", track: nil, state: .stopped)
    let resolved = unresolved.inRoom(office)
    #expect(resolved.hasRoom)
    #expect(resolved.zoneId == "office")
    #expect(resolved.roomName == "Office")
    #expect(resolved.tracks == unresolved.tracks)
    #expect(resolved.context == unresolved.context)
    #expect(resolved.bridgeScope == unresolved.bridgeScope)
    let restored = try JSONDecoder().decode(SiriMusicSelection.self, from: JSONEncoder().encode(resolved))
    #expect(restored.hasRoom)

    // A cache created before mandatory room selection must not silently play
    // in the previously selected room, even though its ID and name are present.
    let legacy = SiriMusicSelection(context: unresolved.context, tracks: unresolved.tracks,
      zoneId: "kitchen", roomName: "Kitchen", bridgeScope: "bridge")
    let oldCache = try JSONEncoder().encode(legacy)
    let restoredLegacy = try JSONDecoder().decode(SiriMusicSelection.self, from: oldCache)
    #expect(!restoredLegacy.hasRoom)
  }

  @Test func repeatedResolutionReusesOnlyRecentResultsForSameRequestAndRoom() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SiriMusicSelections(fileURL: directory.appending(path: "selections.json"))
    let selection = SiriMusicSelection(context: CapsuleSearchContext(query: "British jazz"),
      tracks: [track("First")], zoneId: "office", roomName: "Office", bridgeScope: "bridge")
    try cache.save(selection)
    let created = try #require(ISO8601DateFormatter().date(from: selection.context.requestedAt))
    let now = created.addingTimeInterval(60)
    #expect(cache.recentSelection(query: "BRITISH JAZZ", zoneId: "office", bridgeScope: "bridge", now: now)?.id == selection.id)
    #expect(cache.recentSelection(query: "British jazz", zoneId: "kitchen", bridgeScope: "bridge", now: now) == nil)
    #expect(cache.recentSelection(query: "British jazz", zoneId: "office", bridgeScope: "other", now: now) == nil)
    #expect(cache.recentSelection(query: "French jazz", zoneId: "office", bridgeScope: "bridge", now: now) == nil)
    #expect(cache.recentSelection(query: "British jazz", zoneId: "office", bridgeScope: "bridge", now: created.addingTimeInterval(121)) == nil)
    #expect(cache.recentSelection(query: "British jazz", zoneId: "office", bridgeScope: "bridge", now: created.addingTimeInterval(-1)) == nil)
  }

  @Test func roomFollowUpUsesOnlyRecentMusicFromThisBridge() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SiriMusicSelections(fileURL: directory.appending(path: "selections.json"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let music = SiriMusicSelection(context: CapsuleSearchContext(query: "British jazz from the 1960s", date: now),
      tracks: [track("First"), track("Second")], zoneId: "", roomName: "", bridgeScope: "bridge")
    try cache.save(music)
    let badOldSearch = SiriMusicSelection(context: CapsuleSearchContext(query: "Play", date: now),
      tracks: [track("Wrong")], zoneId: "office", roomName: "Office", bridgeScope: "bridge")
    try cache.save(badOldSearch)
    let restored = cache.recentMusicSelection(bridgeScope: "bridge", roomNames: ["Office"], now: now.addingTimeInterval(60))
    #expect(restored?.id == music.id)
    #expect(restored?.tracks == music.tracks)
    #expect(restored?.context == music.context)
    #expect(cache.recentMusicSelection(bridgeScope: "other", roomNames: ["Office"], now: now) == nil)
    #expect(cache.recentMusicSelection(bridgeScope: "bridge", roomNames: ["Office"], now: now.addingTimeInterval(301)) == nil)
    #expect(cache.recentMusicSelection(bridgeScope: "bridge", roomNames: ["Office"], now: now.addingTimeInterval(-1)) == nil)
  }

  @Test func playbackRequiresFreshPlayingEventForRequestedMusic() {
    let requestedAt = Date()
    var zone = Zone(id: "office", name: "Office", track: Track(id: "current", title: "First",
      artist: "Artist", album: "Album", position: "0:01", remaining: "3:00", progress: 0, imageKey: nil), state: .playing)
    let tracks = [track("First")]
    #expect(SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: requestedAt, requestedAt: requestedAt))
    #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: requestedAt.addingTimeInterval(-1), requestedAt: requestedAt))
    #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: nil, requestedAt: requestedAt))
    for state: PlaybackState in [.paused, .stopped, .loading] {
      zone.state = state
      #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: requestedAt, requestedAt: requestedAt))
    }
    zone.state = .playing
    zone.track?.title = "Unrelated music"
    #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: requestedAt, requestedAt: requestedAt))
    zone.track?.title = "First"
    zone.track?.artist = "Miles Davis"
    #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: tracks, eventAt: requestedAt, requestedAt: requestedAt))
    zone.track?.artist = "Artist"
    #expect(!SiriPlaybackConfirmation.isPlaying(zone, tracks: [track("First", error: "Unavailable")], eventAt: requestedAt, requestedAt: requestedAt))
  }
}
