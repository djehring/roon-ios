import Foundation

struct DiscoveredBridge: Identifiable, Hashable {
  var id: String { "\(host):\(port)" }
  var name: String
  var host: String
  var port: Int
  var version: String?
}

enum RoonSyncState: String, Decodable {
  case lost = "LOST"
  case starting = "STARTING"
  case stopped = "STOPPED"
  case sync = "SYNC"
  case syncing = "SYNCING"
}

struct ApiStatePayload: Decodable {
  var state: RoonSyncState
  var zones: [ZoneDescription]
  var outputs: [OutputDescription]
}

struct ZoneDescription: Decodable, Hashable {
  var zoneId: String
  var displayName: String
}

struct OutputDescription: Decodable, Hashable {
  var displayName: String
  var zoneId: String
  var outputId: String
}

struct ZoneNicePlaying: Decodable {
  var track: PlayingTrack
  var totalQueueRemainingTime: String?
  var nbItemsInQueue: Int?
  var state: String
}

struct PlayingTrack: Decodable {
  var title: String
  var artist: String?
  var length: String?
  var seekPosition: String?
  var seekPercentage: Double?
  var imageKey: String?
  var disk: PlayingDisk?
}

struct PlayingDisk: Decodable {
  var title: String
  var artist: String?
  var imageKey: String?
}

struct OutputVolume: Decodable {
  var type: String?
  var min: Double?
  var max: Double?
  var value: Double?
  var isMuted: Bool?
}

struct ZoneOutput: Decodable, Identifiable {
  var id: String { outputId }
  var outputId: String
  var zoneId: String
  var displayName: String
  var canGroupWithOutputIds: [String]?
  var volume: OutputVolume?
}

struct ZoneStatePayload: Decodable {
  var zoneId: String
  var displayName: String
  var outputs: [ZoneOutput]
  var state: String
  var nicePlaying: ZoneNicePlaying?
  var isPreviousAllowed: Bool?
  var isNextAllowed: Bool?
  var isPauseAllowed: Bool?
  var isPlayAllowed: Bool?
}

struct QueueTrackPayload: Decodable, Identifiable {
  var id: String { String(queueItemId) }
  var queueItemId: Int
  var title: String
  var artist: String?
  var imageKey: String?
  var length: String?
  var disk: PlayingDisk?
}

struct QueueStatePayload: Decodable {
  var zoneId: String
  var tracks: [QueueTrackPayload]
}

struct SharedConfigPayload: Decodable {
  var customActions: [CustomActionPayload]
}

struct CustomActionPayload: Decodable, Identifiable {
  var id: String
  var label: String
  var icon: String
  var roonPath: RoonPathPayload
  var actionIndex: Int?
}

struct RoonPathPayload: Decodable {
  var hierarchy: String
  var path: [String]
}

struct BrowseItem: Decodable, Identifiable {
  var id: String { itemKey ?? title }
  var title: String
  var subtitle: String?
  var imageKey: String?
  var itemKey: String?
  var hint: String?
  var inputPrompt: InputPrompt?
}

struct InputPrompt: Decodable {
  var prompt: String
  var action: String
  var value: String?
  var isPassword: Bool?
}

struct BrowseList: Decodable {
  var title: String
  var count: Int
  var subtitle: String?
  var imageKey: String?
  var level: Int
  var displayOffset: Int?
  var hint: String?
}

struct BrowseResponse: Decodable {
  var action: String
  var item: BrowseItem?
  var list: BrowseList?
  var message: String?
  var isError: Bool?
}

struct LoadResponse: Decodable {
  var items: [BrowseItem]
  var offset: Int
  var list: BrowseList
}

struct SuggestedTrackPayload: Decodable, Identifiable {
  var id: String { "\(artist)-\(track)-\(album)" }
  var artist: String
  var album: String
  var track: String
  var error: String?
  var wasAutoCorrected: Bool?
  var correctionMessage: String?
}

struct TrackStoryPayload: Decodable {
  var title: String
  var content: String
}

struct LibraryAlbumItem: Decodable, Identifiable {
  var id: String { itemKey }
  var title: String
  var subtitle: String?
  var itemKey: String
  var imageKey: String?
}

struct AlbumRecognition: Decodable {
  var albumTitle: String
  var artistName: String
  var confidence: String
}

struct RecognizeAlbumResponse: Decodable {
  var recognition: AlbumRecognition?
  var libraryResults: [LibraryAlbumItem]
}

struct PairingPinResponse: Decodable {
  var pin: String
}

struct APIErrorBody: Decodable {
  var error: String?
}

enum RoonAPIError: Error, LocalizedError {
  case invalidURL
  case httpStatus(Int, String?)
  case invalidPIN
  case missingLocation
  case decoding(Error)
  case unpaired
  case missingOpenAI

  var errorDescription: String? {
    switch self {
    case .invalidURL: "Invalid bridge address."
    case let .httpStatus(code, message):
      message ?? "The bridge returned HTTP \(code)."
    case .invalidPIN: "That pairing code is wrong."
    case .missingLocation: "The bridge did not return a client id."
    case let .decoding(error): "Unexpected data from the bridge (\(error.localizedDescription))."
    case .unpaired: "This phone is not paired."
    case .missingOpenAI: "OpenAI is not configured on the bridge."
    }
  }
}
