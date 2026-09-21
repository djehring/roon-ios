import Foundation
import Testing

@Suite("Now Playing synchronization")
struct NowPlayingSyncTests {
  private var track: Track {
    Track(id: "song", title: "Song", artist: "Artist", album: "Album",
      position: "0:12", remaining: "2:48", progress: 0.067,
      imageKey: "cover", durationSeconds: 180)
  }

  @Test func radioWithoutMetadataKeepsBothPublishersPlaying() throws {
    let zone = Zone(id: "office", name: "Office", track: nil, state: .playing)
    let snapshot = try #require(NowPlayingSnapshot(zone: zone, isPlaying: true))
    #expect(snapshot.title == "Office")
    #expect(snapshot.artist.isEmpty)
    #expect(snapshot.isPlaying)
    #expect(snapshot.track == nil)
  }

  @Test func loadingWithoutMetadataKeepsTheBackgroundConnection() {
    let zone = Zone(id: "office", name: "Office", track: nil, state: .loading)
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: true)?.isPlaying == true)
  }

  @Test func pausedTrackKeepsControlsButStoppedTrackClearsThem() {
    var zone = Zone(id: "office", name: "Office", track: track, state: .paused)
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: false)?.title == track.title)
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: false)?.isPlaying == false)
    zone.state = .stopped
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: false) == nil)
    zone.track = nil
    zone.state = .paused
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: false) == nil)
  }

  @Test func metadataCorrectionsAndRoomChangesInvalidateThePublication() throws {
    var zone = Zone(id: "office", name: "Office", track: track, state: .playing)
    let original = try #require(NowPlayingSnapshot(zone: zone, isPlaying: true))
    zone.track?.album = "Corrected album"
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: true) != original)
    zone.track = track
    zone.track?.durationSeconds = 240
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: true) != original)
    zone.track = track
    zone = Zone(id: "kitchen", name: "Office", track: track, state: .playing)
    #expect(NowPlayingSnapshot(zone: zone, isPlaying: true) != original)
  }

  @Test func cachedArtworkIsRebudgetedForALongerTitleOnTheSameAlbum() throws {
    let short = RoonNowPlayingAttributes.ContentState(zoneName: "Office", title: "Song",
      artist: "Artist", isPlaying: true, artworkJPEG: Data(repeating: 7, count: 2100), zoneID: "office")
    #expect(short.fittingBudget() == short)
    var longer = short
    longer.title = String(repeating: "A longer movement title ", count: 30)
    #expect(try JSONEncoder().encode(longer).count > 3200)
    let fitted = longer.fittingBudget()
    #expect(fitted.artworkJPEG == nil)
    #expect(fitted.title == longer.title)
    #expect(fitted.isPlaying)
    #expect(try JSONEncoder().encode(fitted).count <= 3200)
  }

  @Test func oversizedEscapedMetadataStillProducesADeliverableActivity() throws {
    let state = RoonNowPlayingAttributes.ContentState(zoneName: "Office",
      title: String(repeating: "\u{0001}🎵", count: 2000), artist: "Artist", isPlaying: false)
    let fitted = state.fittingBudget()
    #expect(try JSONEncoder().encode(fitted).count <= 3200)
    #expect(!fitted.title.isEmpty)
    #expect(fitted.artist == state.artist)
    #expect(!fitted.isPlaying)
  }

  @Test func activitiesFromThePreviousBuildRemainDecodable() throws {
    let data = Data(#"{"zoneName":"Office","title":"Song","artist":"Artist","isPlaying":true}"#.utf8)
    let state = try JSONDecoder().decode(RoonNowPlayingAttributes.ContentState.self, from: data)
    #expect(state.zoneID == nil)
    #expect(state.title == "Song")
  }
}
