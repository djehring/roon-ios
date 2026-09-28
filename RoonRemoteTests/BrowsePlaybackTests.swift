import Foundation
import Testing

@MainActor
@Suite("Play from a collection track")
struct BrowseTrackPlaybackTests {
  private func node(_ title: String, key: String, hint: String? = "action_list") -> BrowseNode {
    BrowseNode(id: key, title: title, symbol: "music.note", actions: [], isPrompt: false,
      children: [], itemKey: key, hint: hint)
  }

  @Test(arguments: ["playlists", "albums", "browse"])
  func suffixKeepsOrderAndDuplicateRecordings(hierarchy: String) {
    let tracks = [node("Same song", key: "1"), node("Other song", key: "2"), node("Same song", key: "3")]
    let play = node("Play Album", key: "play")
    let page = BrowsePage(title: "Collection", items: [play] + tracks)
    #expect(page.tracksFrom(tracks[1], hierarchy: hierarchy, parentKey: "collection").map(\.id) == ["2", "3"])
    #expect(page.tracksFrom(tracks[2], hierarchy: hierarchy, parentKey: "collection").map(\.id) == ["3"])
    #expect(page.tracksFrom(play, hierarchy: hierarchy, parentKey: "collection").isEmpty)
  }

  @Test func excludesRootSearchResultsAndActionRows() {
    let track = node("Song", key: "song")
    let action = node("Play Now", key: "play", hint: "action")
    let page = BrowsePage(title: "Tracks", items: [track, action])
    #expect(page.tracksFrom(track, hierarchy: "playlists", parentKey: nil).isEmpty)
    #expect(page.tracksFrom(track, hierarchy: "search", parentKey: "results").isEmpty)
    #expect(page.tracksFrom(action, hierarchy: "albums", parentKey: "album").isEmpty)
  }

  @Test func retainsLaterDiscGroupsAndSkipsHeaders() {
    let track = node("Last track on disc one", key: "track")
    let page = BrowsePage(title: "Album", items: [
      node("Play Album", key: "play"), track,
      node("Disc two", key: "header", hint: "header"),
      node("Disc two", key: "disc-two", hint: "list"),
    ])
    #expect(page.tracksFrom(track, hierarchy: "browse", parentKey: "album").map(\.id) == ["track", "disc-two"])
  }

  @Test func playsSelectedTrackThenQueuesEveryRemainingOccurrence() async throws {
    let tracks = [node("Song", key: "2"), node("Song", key: "3"), node("Last", key: "4")]
    var requests: [String] = []
    try await BrowseTrackPlayback.play(tracks) { track in
      requests.append("open:\(track.id)")
      return ["Play Now", "Queue"].map { node($0, key: "\(track.id):\($0)", hint: "action") }
    } execute: { action in
      requests.append(action.id)
    }
    #expect(requests == ["open:2", "2:Play Now", "open:3", "3:Queue", "open:4", "4:Queue"])
  }

  @Test func usesNativeFromHereWithoutQueueingDuplicates() async throws {
    var played: [String] = []
    try await BrowseTrackPlayback.play([node("Song", key: "1"), node("Next", key: "2")]) { track in
      #expect(track.id == "1")
      return [node("Play From Here", key: "native", hint: "action")]
    } execute: { action in played.append(action.id) }
    #expect(played == ["native"])
  }

  @Test func failureStopsWithoutRetryingOrSkippingTracks() async {
    var played: [String] = []
    do {
      try await BrowseTrackPlayback.play([node("One", key: "1"), node("Two", key: "2"), node("Three", key: "3")]) { track in
        ["Play Now", "Queue"].map { node($0, key: "\(track.id):\($0)", hint: "action") }
      } execute: { action in
        played.append(action.id)
        if action.id == "2:Queue" { throw RoonAPIError.browseAction("Room disconnected") }
      }
      Issue.record("Expected playback failure")
    } catch {
      #expect(error.localizedDescription == "Room disconnected")
    }
    #expect(played == ["1:Play Now", "2:Queue"])
  }

  @Test func missingQueueDoesNotPlayTheNextTrackImmediately() async {
    var played: [String] = []
    do {
      try await BrowseTrackPlayback.play([node("One", key: "1"), node("Two", key: "2")]) { track in
        [node("Play Now", key: track.id, hint: "action")]
      } execute: { action in played.append(action.id) }
      Issue.record("Expected unavailable queue action")
    } catch {
      #expect(error.localizedDescription.contains("Queue"))
    }
    #expect(played == ["1"])
  }

  private func response(offset: Int, count: Int, total: Int = 613) -> LoadResponse {
    LoadResponse(items: (offset..<(offset + count)).map {
      BrowseItem(title: "Track \($0)", itemKey: "track-\($0)", hint: "action_list")
    }, offset: offset, list: BrowseList(title: "Long playlist", count: total, level: 1))
  }

  @Test func loadsTracksPastTheFirstFiveHundred() async throws {
    var offsets: [Int] = []
    let items = try await BrowseTrackPlayback.loadCollection(first: response(offset: 0, count: 500)) { offset, count in
      offsets.append(offset)
      return response(offset: offset, count: count)
    }
    #expect(offsets == [500])
    #expect(items.count == 613)
    #expect(items.last?.itemKey == "track-612")
  }

  @Test(arguments: ["empty", "offset", "count"])
  func rejectsIncompleteOrChangedCollections(_ failure: String) async {
    do {
      _ = try await BrowseTrackPlayback.loadCollection(first: response(offset: 0, count: 500)) { offset, count in
        response(offset: failure == "offset" ? 0 : offset,
          count: failure == "empty" ? 0 : count, total: failure == "count" ? 614 : 613)
      }
      Issue.record("Expected changed collection error")
    } catch {
      #expect(error.localizedDescription.contains("collection changed"))
    }
  }
}

@MainActor
@Suite("Browse playback feedback")
struct BrowsePlaybackTests {
  @Test(arguments: ["Play", "Play Now", "Play Album", "Play Playlist", "Play From Here", "Shuffle", "Shuffle All", "Start Radio", "  PLAY NOW  "])
  func immediatePlaybackActions(_ title: String) {
    #expect(BrowsePlayback.startsPlayback(title))
  }

  @Test(arguments: ["Queue", "Add to Queue", "Play Next", "Queue Next", "Add to Playlist", "Search"])
  func deferredActions(_ title: String) {
    #expect(!BrowsePlayback.startsPlayback(title))
  }

  @Test func acknowledgesBeforeOpeningNowPlaying() async {
    let playback = BrowsePlayback()
    var opened = false
    await playback.run(actionTitle: "Play Album", room: "Kitchen", feedbackDuration: .zero) {
      #expect(playback.isRunning)
      #expect(playback.feedback?.title == "Starting playback…")
      #expect(playback.feedback?.room == "Kitchen")
      #expect(playback.feedback?.isLoading == true)
      #expect(!opened)
    } showNowPlaying: {
      #expect(playback.feedback?.title == "Playback started")
      #expect(playback.feedback?.isLoading == false)
      opened = true
    }
    #expect(opened)
    #expect(!playback.isRunning)
    #expect(playback.feedback == nil)
    #expect(playback.error == nil)
  }

  @Test(arguments: ["Queue", "Play Next"])
  func queueDoesNotNavigate(_ action: String) async {
    let playback = BrowsePlayback()
    var performed = false
    await playback.run(actionTitle: action, room: "Kitchen", feedbackDuration: .zero) {
      performed = true
    } showNowPlaying: {
      Issue.record("Queue actions should keep the browse screen open")
    }
    #expect(performed)
  }

  @Test func failureStaysInBrowseAndAllowsRetry() async {
    let playback = BrowsePlayback()
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      throw RoonAPIError.browseAction("Room unavailable")
    } showNowPlaying: {
      Issue.record("Failed playback should not navigate")
    }
    #expect(playback.error == "Room unavailable")
    #expect(playback.feedback == nil)
    #expect(!playback.isRunning)

    var opened = false
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      #expect(playback.error == nil)
    } showNowPlaying: {
      opened = true
    }
    #expect(opened)
  }

  @Test func duplicateTapsDoNotRepeatTheCommand() async {
    let playback = BrowsePlayback()
    var commands = 0
    var navigation = 0
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      commands += 1
      await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
        commands += 1
      } showNowPlaying: {
        navigation += 1
      }
    } showNowPlaying: {
      navigation += 1
    }
    #expect(commands == 1)
    #expect(navigation == 1)
  }

  @Test func cancellationClearsFeedback() async {
    let playback = BrowsePlayback()
    await playback.run(actionTitle: "Play", room: "Kitchen", feedbackDuration: .zero) {
      throw CancellationError()
    } showNowPlaying: {
      Issue.record("Cancelled playback should not navigate")
    }
    #expect(playback.feedback == nil)
    #expect(playback.error == nil)
    #expect(!playback.isRunning)
  }
}
