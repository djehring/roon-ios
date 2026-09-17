import Foundation

struct CapsuleSearchContext: Codable, Equatable {
  var query: String
  var requestedAt: String
  var locale: String
  var timeZone: String

  init(query: String, date: Date = Date()) {
    self.query = query
    requestedAt = ISO8601DateFormatter().string(from: date)
    locale = Locale.current.identifier
    timeZone = TimeZone.current.identifier
  }
}

struct CapsuleRequest: Codable, Equatable {
  var query: String
  var requestedAt: String
  var locale: String
  var timeZone: String
  var tracks: [CapsuleTrack]

  init(context: CapsuleSearchContext, tracks: [SuggestedTrack]) {
    query = context.query
    requestedAt = context.requestedAt
    locale = context.locale
    timeZone = context.timeZone
    self.tracks = tracks.filter { $0.error == nil }.map {
      CapsuleTrack(artist: $0.artist, track: $0.title, album: $0.album)
    }
  }
}

struct CapsuleTrack: Codable, Equatable {
  var artist: String
  var track: String
  var album: String
}

struct TimeCapsule: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var contextLabel: String
  var request: CapsuleRequest
  var createdAt: String
  var scenes: [CapsuleScene]
  var contextImage: CapsuleImage?

  /// Refuse ambiguous recordings instead of attaching an unrelated artist story.
  func trackIndex(for track: Track?) -> Int? {
    guard let track else { return nil }
    let candidates = request.tracks.indices.filter {
      Self.normalized(request.tracks[$0].artist) == Self.normalized(track.artist)
        && Self.normalized(request.tracks[$0].track) == Self.normalized(track.title)
    }
    let exact = candidates.filter { Self.normalized(request.tracks[$0].album) == Self.normalized(track.album) }
    if exact.count == 1 { return exact.first }
    return candidates.count == 1 ? candidates.first : nil
  }

  func sceneIndex(for track: Track?) -> Int? {
    guard let track, let index = trackIndex(for: track), !scenes.isEmpty else { return nil }
    let eligible = scenes.indices.filter { scenes[$0].trackIndices.isEmpty || scenes[$0].trackIndices.contains(index) }
    guard !eligible.isEmpty else { return nil }
    let seconds = Self.seconds(track.position)
    let offset = Int(max(0, seconds) / 30)
    // A deterministic phase gives all receivers the same scene on late join or seek.
    return eligible[(index * 3 + offset) % eligible.count]
  }

  static func seconds(_ timecode: String) -> Double {
    let components = timecode.split(separator: ":", omittingEmptySubsequences: false)
    let parts = components.compactMap { Double($0) }
    guard parts.count == components.count, !parts.isEmpty, parts.count <= 3,
          parts.allSatisfy({ $0.isFinite && $0 >= 0 }),
          parts.dropFirst().allSatisfy({ $0 < 60 }) else { return 0 }
    return parts.reduce(0) { $0 * 60 + $1 }
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct CapsuleScene: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var body: String
  var dateLabel: String
  var scope: String
  var sources: [CapsuleSource]
  var trackIndices: [Int]
  var image: CapsuleImage?
}

struct CapsuleSource: Codable, Hashable {
  var title: String
  var url: URL
}

struct CapsuleImage: Codable, Equatable {
  var file: String
  var sourceUrl: URL
  var credit: String
  var license: String
  var licenseUrl: String
  var date: String
  var description: String
}

struct CapsuleJob: Decodable {
  var id: String
  var status: String
  var error: String?
  var capsule: TimeCapsule?
}
