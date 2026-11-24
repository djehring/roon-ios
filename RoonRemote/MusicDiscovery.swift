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
  /// "Released Aug 2019", whatever precision the date has, or nil when no date
  /// is known. A date known only to the year shows the year alone.
  var dateLabel: String? {
    guard let release else { return nil }
    let parts = release.releaseDate.split(separator: "-").map { Int($0) }
    guard let year = parts.first ?? nil else { return nil }
    let months = Calendar.current.shortMonthSymbols
    let month = parts.count > 1 ? parts[1].flatMap { (1...months.count).contains($0) ? months[$0 - 1] : nil } : nil
    return [release.reissue ? "Reissue" : "Released", month, String(year)].compactMap { $0 }.joined(separator: " ")
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
