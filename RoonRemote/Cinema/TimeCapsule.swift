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
  var options: CapsuleOptions?
  var title: String?
  var sourceLabel: String?
  var clientRequestId: String?

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
  var entryId: String?
  var imageKey: String?
  var durationSeconds: Double?
  var roonPath: CinemaMusicPath?
  var matchPolicy: String?
}

struct TimeCapsule: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var contextLabel: String
  var request: CapsuleRequest
  var createdAt: String
  var scenes: [CapsuleScene]
  var contextImage: CapsuleImage?
  var notices: [String]?
  var periodStart: String?
  var periodEnd: String?
  var generation: String?
  var revision: Int?

  var isPersonal: Bool { request.options?.mode == .photos }
  var minimumPictures: Int { isPersonal || request.options?.topics == [.albumCovers] ? 1 : 3 }
  var canWatch: Bool { montageFrames.count >= minimumPictures }

  /// Only real photographs enter the montage. Empty story cards and repeated
  /// context backgrounds must not masquerade as a changing photo sequence.
  var montageFrames: [MontageFrame] {
    var seen = Set<String>()
    return scenes.flatMap { scene in
      let images = scene.images ?? scene.image.map { [$0] } ?? []
      return images.compactMap { image -> MontageFrame? in
        guard seen.insert(image.file).inserted else { return nil }
        return MontageFrame(scene: scene, image: image)
      }
    }
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
  var images: [CapsuleImage]?
}

struct CapsulePreparation {
  var placeholder: TimeCapsule
  let original: TimeCapsule?
  var result: TimeCapsule?
  var jobId: String?
  var expectedGeneration: String?

  init(request: CapsuleRequest, original: TimeCapsule? = nil) {
    self.original = original
    placeholder = TimeCapsule(id: UUID().uuidString, title: request.title ?? original?.title ?? request.query,
      contextLabel: original?.contextLabel ?? request.query, request: request,
      createdAt: ISO8601DateFormatter().string(from: Date()), scenes: [],
      contextImage: original?.montageFrames.first?.image ?? original?.contextImage)
  }

  func contains(_ capsule: TimeCapsule) -> Bool {
    capsule.id == placeholder.id || capsule.id == original?.id
  }

  func resolve(_ presented: TimeCapsule) -> TimeCapsule {
    presented.id == placeholder.id ? result ?? placeholder : presented
  }
}

enum CapsuleNowPlaying {
  static func select(preparing: Bool, current: Track?, queue: [QueueItem], associated: TimeCapsule?,
    saved: [TimeCapsule]) -> TimeCapsule? {
    guard !preparing, let current else { return nil }
    let upcoming = Array(QueueTimeline.upcoming(queue: queue, current: current).prefix(2))
    var candidates = saved
    if let associated, !saved.contains(where: { $0.id == associated.id }) { candidates.append(associated) }
    let matching = candidates.filter { capsule in
      capsule.request.tracks.contains {
        titlesMatch($0.track, current.title) && AISearchPlayback.artistsAlign($0.artist, current.artist)
      }
    }
    // The next tracks distinguish playlists that happen to share the current song.
    func score(_ capsule: TimeCapsule) -> Int {
      upcoming.filter { queued in
        capsule.request.tracks.contains {
          titlesMatch($0.track, queued.title) && AISearchPlayback.artistsAlign($0.artist, queued.artist)
        }
      }.count
    }
    return matching.filter { upcoming.isEmpty || score($0) > 0 }.sorted {
      if score($0) != score($1) { return score($0) > score($1) }
      if ($0.id == associated?.id) != ($1.id == associated?.id) { return $0.id == associated?.id }
      return $0.createdAt > $1.createdAt
    }.first
  }

  private static func titlesMatch(_ left: String, _ right: String) -> Bool {
    func title(_ value: String) -> String {
      RoonVoiceMatch.normalize(value).replacingOccurrences(
        of: #"\s+(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?$"#, with: "", options: .regularExpression)
    }
    return RoonVoiceMatch.titlesMatch(title(left), title(right))
  }
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
  var localFile: String?
}

struct CapsuleJob: Decodable {
  var id: String
  var status: String
  var error: String?
  var capsule: TimeCapsule?
  var generation: String?
  var message: String?
}


struct MontageFrame: Identifiable {
  let scene: CapsuleScene
  let image: CapsuleImage
  var id: String { image.file }
}

/// The montage has its own pace. Song changes and song-title formatting do not
/// reset it; image loading and source inspection hold the sequence.
struct MontagePlayback {
  private(set) var index = 0
  private(set) var elapsed: Double = 0
  static let secondsPerPhoto: Double = 8

  mutating func advance(seconds: Double, playing: Bool, count: Int, secondsPerPhoto: Double = Self.secondsPerPhoto) {
    guard playing, count > 1, seconds.isFinite, seconds > 0 else { return }
    guard secondsPerPhoto.isFinite, secondsPerPhoto > 0 else { return }
    elapsed += seconds
    if elapsed >= secondsPerPhoto {
      index = (index + Int(elapsed / secondsPerPhoto)) % count
      elapsed.formTruncatingRemainder(dividingBy: secondsPerPhoto)
    }
  }

  mutating func move(_ offset: Int, count: Int) {
    guard count > 0 else { return }
    index = ((index + offset) % count + count) % count
    elapsed = 0
  }
}

struct MontagePlaybackMemory {
  private var saved: [String: (revision: String, playback: MontagePlayback)] = [:]

  func resume(capsuleId: String, revision: String) -> MontagePlayback {
    guard let entry = saved[capsuleId], entry.revision == revision else { return MontagePlayback() }
    return entry.playback
  }

  mutating func remember(_ playback: MontagePlayback, capsuleId: String, revision: String) {
    if saved[capsuleId] == nil, saved.count >= 50, let oldest = saved.keys.first { saved.removeValue(forKey: oldest) }
    saved[capsuleId] = (revision, playback)
  }
}
