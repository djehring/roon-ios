import Foundation
import Testing

@Suite("Zone track selection")
struct ZoneTrackSelectionTests {
  private func track(_ title: String, artist: String = "BBC") -> Track {
    Track(
      id: title,
      title: title,
      artist: artist,
      album: title,
      position: "0:00",
      remaining: "",
      progress: 0
    )
  }

  @Test("a decoded radio station replaces last night's album")
  func incomingWins() {
    let radio = track("BBC Radio 3")
    let lastNight = track("Kind of Blue", artist: "Miles Davis")
    let choice = ZoneTrackSelection.choose(
      incoming: radio,
      previous: lastNight,
      playback: .playing,
      pinned: nil,
      replaced: nil,
      presence: .available
    )

    #expect(choice.track == radio)
    #expect(choice.clearPin == false)
  }

  @Test("an unreadable now-playing object does not keep yesterday's track")
  func emptyNowPlayingClearsStaleTrack() {
    let lastNight = track("Kind of Blue", artist: "Miles Davis")
    let choice = ZoneTrackSelection.choose(
      incoming: nil,
      previous: lastNight,
      playback: .playing,
      pinned: nil,
      replaced: nil,
      presence: .available
    )

    #expect(choice.track == nil)
  }

  @Test("a missing now-playing key keeps the current track across a brief gap")
  func omittedKeepsPreviousWhilePlaying() {
    let current = track("So What", artist: "Miles Davis")
    let choice = ZoneTrackSelection.choose(
      incoming: nil,
      previous: current,
      playback: .playing,
      pinned: nil,
      replaced: nil,
      presence: .omitted
    )

    #expect(choice.track == current)
  }

  @Test("stopped with no incoming clears the track")
  func stoppedClears() {
    let lastNight = track("Kind of Blue", artist: "Miles Davis")
    let choice = ZoneTrackSelection.choose(
      incoming: nil,
      previous: lastNight,
      playback: .stopped,
      pinned: nil,
      replaced: nil,
      presence: .omitted
    )

    #expect(choice.track == nil)
  }

  @Test("a pin holds until the core reports the same song")
  func pinHoldsThenClears() {
    let next = track("Freddie Freeloader", artist: "Miles Davis")
    let held = ZoneTrackSelection.choose(
      incoming: nil,
      previous: track("So What"),
      playback: .playing,
      pinned: next,
      replaced: track("So What"),
      presence: .omitted
    )
    #expect(held.track == next)
    #expect(held.clearPin == false)

    let arrived = ZoneTrackSelection.choose(
      incoming: next,
      previous: next,
      playback: .playing,
      pinned: next,
      replaced: track("So What"),
      presence: .available
    )
    #expect(arrived.track == next)
    #expect(arrived.clearPin == true)
  }

  @Test("a pin yields when a different song arrives")
  func pinYieldsToNewSong() {
    let radio = track("BBC Radio 3")
    let choice = ZoneTrackSelection.choose(
      incoming: radio,
      previous: track("So What"),
      playback: .playing,
      pinned: track("Freddie Freeloader"),
      replaced: track("So What"),
      presence: .available
    )

    #expect(choice.track == radio)
    #expect(choice.clearPin == true)
  }
}

@Suite("Zone now-playing decode")
struct ZoneNowPlayingDecodeTests {
  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  private func payload(_ json: String) throws -> ZoneStatePayload {
    try decoder.decode(ZoneStatePayload.self, from: Data(json.utf8))
  }

  @Test("radio now-playing without a nested state still decodes")
  func radioWithoutState() throws {
    let zone = try payload(
      """
      {
        "zone_id": "kitchen",
        "display_name": "Kitchen",
        "state": "playing",
        "nice_playing": {
          "track": { "title": "BBC Radio 3", "artist": "BBC" }
        }
      }
      """
    )

    guard case let .present(playing) = zone.nowPlaying else {
      Issue.record("expected present now-playing")
      return
    }
    #expect(playing.track.title == "BBC Radio 3")
    #expect(playing.track.artist == "BBC")
    #expect(playing.state == nil)
  }

  @Test("a missing nice_playing key is omitted, not empty")
  func missingKeyIsOmitted() throws {
    let zone = try payload(
      """
      { "zone_id": "kitchen", "state": "playing" }
      """
    )

    #expect(zone.nowPlaying == .omitted)
  }

  @Test("a null nice_playing object is empty so yesterday is not kept")
  func nullIsEmpty() throws {
    let zone = try payload(
      """
      { "zone_id": "kitchen", "state": "playing", "nice_playing": null }
      """
    )

    #expect(zone.nowPlaying == .empty)
  }

  @Test("an empty track is empty now-playing")
  func emptyTrackIsEmpty() throws {
    let zone = try payload(
      """
      {
        "zone_id": "kitchen",
        "state": "playing",
        "nice_playing": { "track": {} }
      }
      """
    )

    #expect(zone.nowPlaying == .empty)
  }

  @Test("numeric length does not drop the now-playing object")
  func numericLengthStillDecodes() throws {
    let zone = try payload(
      """
      {
        "zone_id": "kitchen",
        "state": "playing",
        "nice_playing": {
          "track": {
            "title": "So What",
            "artist": "Miles Davis",
            "length": 564,
            "seek_position": 78
          },
          "total_queue_remaining_time": 1200
        }
      }
      """
    )

    guard case let .present(playing) = zone.nowPlaying else {
      Issue.record("expected present now-playing")
      return
    }
    #expect(playing.track.title == "So What")
    #expect(playing.track.length == "564")
    #expect(playing.track.seekPosition == "78")
    #expect(playing.totalQueueRemainingTime == "1200")
  }
}
