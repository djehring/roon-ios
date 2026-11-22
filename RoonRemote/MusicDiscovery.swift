import Foundation

enum MusicDiscoveryRequest {
  /// Search is read-only, so a dropped connection can be retried once. Playback
  /// may already have changed the room's queue when its response is lost.
  static func send(
    pathSuffix: String,
    operation: () async throws -> Data
  ) async throws -> Data {
    try Task.checkCancellation()
    do {
      return try await operation()
    } catch let error as URLError where pathSuffix.isEmpty && error.code == .networkConnectionLost {
      try await Task.sleep(for: .milliseconds(300))
      try Task.checkCancellation()
      return try await operation()
    }
  }
}

enum MusicSearchMode: String, Codable, CaseIterable, Identifiable {
  case auto, tracks, albums
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct MusicReleaseEvidence: Codable, Hashable {
  var title: String
  var artist: String
  var releaseDate: String
  var recordingDate: String
  var reissue: Bool
  var source: String

  var sourceURL: URL? {
    guard let url = URL(string: source), ["https", "http"].contains(url.scheme) else { return nil }
    return url
  }
}

struct MusicDiscoveryResult: Codable, Identifiable, Equatable {
  var id: String
  var kind: String
  var title: String
  var artist: String
  var album: String
  var imageKey: String?
  var available: Bool
  var reason: String?
  var tracks: [CapsuleTrack]
  var workTracks: [CapsuleTrack]
  var workTitle: String?
  var release: MusicReleaseEvidence?

  var isAlbum: Bool { kind == "album" }
  var canPlay: Bool { available && !tracks.isEmpty && tracks.allSatisfy { $0.roonPath != nil } }
  var canPlayWork: Bool { canPlay && workTracks.count > 1 && workTracks.allSatisfy { $0.roonPath != nil } }
  var dateLabel: String {
    guard let release else { return "Release date unverified" }
    return "\(release.reissue ? "Reissue" : "Released") \(release.releaseDate)"
  }
}

struct MusicDiscoveryResponse: Codable {
  var mode: String
  var query: String
  var message: String
  var results: [MusicDiscoveryResult]
}

struct MusicDiscoveryPlayback: Decodable {
  var tracks: [CapsuleTrack]
}

extension CapsuleTrack {
  var suggestedTrack: SuggestedTrack {
    SuggestedTrack(id: entryId ?? "\(artist)|\(album)|\(track)",
      title: RoonDisplayText.format(track), artist: RoonDisplayText.format(artist),
      album: RoonDisplayText.format(album), corrected: false)
  }
}
