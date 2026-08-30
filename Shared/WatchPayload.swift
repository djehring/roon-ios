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
  var zones: [WatchZoneRow]

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
    zones: []
  )
}

enum WatchCommand: Codable, Hashable {
  case playPause
  case skip
  case previous
  case setVolume(outputId: String, value: Double)
  case selectZone(id: String)
}
