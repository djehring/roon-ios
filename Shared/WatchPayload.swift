import Foundation

enum WatchMessageKey {
  static let snapshot = "snapshot"
  static let command = "command"
}

enum WatchShared {
  static let suiteName = "group.com.djehring.roonremote"
  static let snapshotKey = "watchSnapshot"
  static let coverKey = "watchCover"
}

struct WatchZoneRow: Codable, Hashable, Identifiable {
  var id: String
  var name: String
  var subtitle: String?
}

struct WatchQueueRow: Codable, Hashable, Identifiable {
  var id: String
  var title: String
  var artist: String
}

struct WatchSnapshot: Codable, Hashable {
  var sessionReady: Bool
  var zoneId: String
  var zoneName: String
  var isPlaying: Bool
  var isLoading: Bool
  var title: String?
  var artist: String?
  var album: String?
  var imageKey: String?
  var coverJPEG: Data?
  var volume: Double
  var volumeMin: Double
  var volumeMax: Double
  var volumeOutputId: String?
  var volumeIsFixed: Bool
  var muted: Bool
  var zones: [WatchZoneRow]
  var queue: [WatchQueueRow]

  init(
    sessionReady: Bool,
    zoneId: String,
    zoneName: String,
    isPlaying: Bool,
    isLoading: Bool,
    title: String?,
    artist: String?,
    album: String?,
    imageKey: String?,
    coverJPEG: Data?,
    volume: Double,
    volumeMin: Double,
    volumeMax: Double,
    volumeOutputId: String?,
    volumeIsFixed: Bool,
    muted: Bool,
    zones: [WatchZoneRow],
    queue: [WatchQueueRow]
  ) {
    self.sessionReady = sessionReady
    self.zoneId = zoneId
    self.zoneName = zoneName
    self.isPlaying = isPlaying
    self.isLoading = isLoading
    self.title = title
    self.artist = artist
    self.album = album
    self.imageKey = imageKey
    self.coverJPEG = coverJPEG
    self.volume = volume
    self.volumeMin = volumeMin
    self.volumeMax = volumeMax
    self.volumeOutputId = volumeOutputId
    self.volumeIsFixed = volumeIsFixed
    self.muted = muted
    self.zones = zones
    self.queue = queue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionReady = try container.decode(Bool.self, forKey: .sessionReady)
    zoneId = try container.decode(String.self, forKey: .zoneId)
    zoneName = try container.decode(String.self, forKey: .zoneName)
    isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
    isLoading = try container.decode(Bool.self, forKey: .isLoading)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    artist = try container.decodeIfPresent(String.self, forKey: .artist)
    album = try container.decodeIfPresent(String.self, forKey: .album)
    imageKey = try container.decodeIfPresent(String.self, forKey: .imageKey)
    coverJPEG = try container.decodeIfPresent(Data.self, forKey: .coverJPEG)
    volume = try container.decode(Double.self, forKey: .volume)
    volumeMin = try container.decode(Double.self, forKey: .volumeMin)
    volumeMax = try container.decode(Double.self, forKey: .volumeMax)
    volumeOutputId = try container.decodeIfPresent(String.self, forKey: .volumeOutputId)
    volumeIsFixed = try container.decode(Bool.self, forKey: .volumeIsFixed)
    muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    zones = try container.decode([WatchZoneRow].self, forKey: .zones)
    queue = try container.decodeIfPresent([WatchQueueRow].self, forKey: .queue) ?? []
  }

  static let empty = WatchSnapshot(
    sessionReady: false,
    zoneId: "",
    zoneName: "Roon",
    isPlaying: false,
    isLoading: false,
    title: nil,
    artist: nil,
    album: nil,
    imageKey: nil,
    coverJPEG: nil,
    volume: 0,
    volumeMin: 0,
    volumeMax: 100,
    volumeOutputId: nil,
    volumeIsFixed: true,
    muted: false,
    zones: [],
    queue: []
  )
}

enum WatchCommand: Codable, Hashable {
  case playPause
  case skip
  case previous
  case stop
  case mute
  case setVolume(outputId: String, value: Double)
  case selectZone(id: String)
  case playFromHere(id: String)
  case transfer(toZoneId: String)
  case playInRoom(query: String, room: String)
}
