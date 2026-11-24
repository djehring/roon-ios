import Foundation
import Testing

@Suite("Verified music discovery")
struct MusicDiscoveryTests {
  private let path = CinemaMusicPath(hierarchy: "search", query: "Enigma", steps: [
    CinemaMusicStep(title: "Enigma Variations", index: 0)
  ])

  private func album() -> MusicDiscoveryResult {
    let tracks = ["Theme", "Nimrod"].map {
      CapsuleTrack(artist: "Vasily Petrenko", track: $0, album: "Elgar", roonPath: path)
    }
    return MusicDiscoveryResult(id: "recording", kind: "album", title: "Elgar", artist: "Vasily Petrenko",
      album: "Elgar", available: true, tracks: tracks, workTracks: tracks, workTitle: "Enigma Variations")
  }

  @Test func keepsAlbumAndWorkSeparateAcrossDecoding() throws {
    let expected = album()
    let decoded = try JSONDecoder().decode(MusicDiscoveryResult.self, from: JSONEncoder().encode(expected))
    #expect(decoded.canPlay)
    #expect(decoded.canPlayWork)
    #expect(decoded.tracks.map(\.track) == ["Theme", "Nimrod"])
    #expect(decoded.tracks.first?.roonPath == path)
    #expect(decoded.dateLabel == nil)
  }

  @Test func unresolvedOrUnavailableMusicCannotBePlayed() {
    var result = album()
    result.tracks[0].roonPath = nil
    #expect(!result.canPlay)
    result = album()
    result.available = false
    #expect(!result.canPlayWork)
    result = album()
    result.workTracks = []
    #expect(result.canPlay)
    #expect(!result.canPlayWork)
  }

  @Test func releaseInformationIsLabelledAndLinksAreSafe() {
    var result = album()
    result.release = MusicReleaseEvidence(title: "Elgar", artist: "Vasily Petrenko",
      releaseDate: "2026-09-01", recordingDate: "", reissue: true, source: "https://label.example/album")
    #expect(result.dateLabel == "Reissue Sep 2026")
    result.release?.reissue = false
    result.release?.releaseDate = "2019"
    #expect(result.dateLabel == "Released 2019")
    #expect(result.release?.sourceURL != nil)
    result.release?.source = "javascript:alert(1)"
    #expect(result.release?.sourceURL == nil)
  }
}

@Suite("Music discovery connection recovery")
struct MusicDiscoveryConnectionTests {
  @Test func searchRecoversAfterLosingItsConnection() async throws {
    let expected = Data("Milos Karadaglic albums".utf8)
    var attempts = 0
    let result = try await MusicDiscoveryRequest.send(pathSuffix: "") {
      attempts += 1
      if attempts == 1 { throw URLError(.networkConnectionLost) }
      return expected
    }
    #expect(result == expected)
    #expect(attempts == 2)
  }

  @Test func aSecondConnectionLossIsReturnedToTheUser() async {
    var attempts = 0
    await #expect(throws: URLError(.networkConnectionLost)) {
      try await MusicDiscoveryRequest.send(pathSuffix: "") {
        attempts += 1
        throw URLError(.networkConnectionLost)
      }
    }
    #expect(attempts == 2)
  }

  @Test func playbackIsNeverRepeatedAfterLosingItsResponse() async {
    var attempts = 0
    await #expect(throws: URLError(.networkConnectionLost)) {
      try await MusicDiscoveryRequest.send(pathSuffix: "/play") {
        attempts += 1
        throw URLError(.networkConnectionLost)
      }
    }
    #expect(attempts == 1)
  }

  @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cancelled, .cannotConnectToHost])
  func otherNetworkFailuresAreNotRetried(_ code: URLError.Code) async {
    var attempts = 0
    await #expect(throws: URLError(code)) {
      try await MusicDiscoveryRequest.send(pathSuffix: "") {
        attempts += 1
        throw URLError(code)
      }
    }
    #expect(attempts == 1)
  }

  @Test func serverFailuresAreNotRetried() async {
    var attempts = 0
    await #expect(throws: RoonAPIError.self) {
      try await MusicDiscoveryRequest.send(pathSuffix: "") {
        attempts += 1
        throw RoonAPIError.httpStatus(502, "Music search failed.")
      }
    }
    #expect(attempts == 1)
  }

  @Test func cancellationAfterConnectionLossPreventsRetry() async {
    let task = Task {
      var attempts = 0
      await #expect(throws: CancellationError.self) {
        try await MusicDiscoveryRequest.send(pathSuffix: "") {
          attempts += 1
          withUnsafeCurrentTask { $0?.cancel() }
          throw URLError(.networkConnectionLost)
        }
      }
      return attempts
    }
    #expect(await task.value == 1)
  }
}
