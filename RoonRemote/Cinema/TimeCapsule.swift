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


struct MontageFrame: Identifiable {
  let scene: CapsuleScene
  let image: CapsuleImage
  var id: String { image.file }
}

/// The montage has its own pace. Song changes and song-title formatting do not
/// reset it; only music pause or an explicit picture pause holds the sequence.
struct MontagePlayback {
  private(set) var index = 0
  private(set) var elapsed: Double = 0
  static let secondsPerPhoto: Double = 8

  mutating func advance(seconds: Double, playing: Bool, count: Int) {
    guard playing, count > 1, seconds.isFinite, seconds > 0 else { return }
    elapsed += seconds
    if elapsed >= Self.secondsPerPhoto {
      index = (index + Int(elapsed / Self.secondsPerPhoto)) % count
      elapsed.formTruncatingRemainder(dividingBy: Self.secondsPerPhoto)
    }
  }

  mutating func move(_ offset: Int, count: Int) {
    guard count > 0 else { return }
    index = ((index + offset) % count + count) % count
    elapsed = 0
  }
}
