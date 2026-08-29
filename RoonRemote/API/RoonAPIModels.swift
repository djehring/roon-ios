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

  private enum CodingKeys: String, CodingKey {
    case title, artist, length, seekPosition, seekPercentage, imageKey, disk
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    artist = try container.decodeIfPresent(String.self, forKey: .artist)
    length = try container.decodeIfPresent(String.self, forKey: .length)
    imageKey = try container.decodeIfPresent(String.self, forKey: .imageKey)
    disk = try container.decodeIfPresent(PlayingDisk.self, forKey: .disk)
    seekPercentage = try container.decodeIfPresent(Double.self, forKey: .seekPercentage)
    if let value = try? container.decode(String.self, forKey: .seekPosition) {
      seekPosition = value
    } else if let value = try? container.decode(Double.self, forKey: .seekPosition) {
      seekPosition = String(value)
    } else {
      seekPosition = nil
    }
  }
}

struct PlayingDisk: Decodable {
  var title: String
  var artist: String?
  var imageKey: String?

  private enum CodingKeys: String, CodingKey {
    case title, artist, imageKey
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    artist = try container.decodeIfPresent(String.self, forKey: .artist)
    imageKey = try container.decodeIfPresent(String.self, forKey: .imageKey)
  }
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

  private enum CodingKeys: String, CodingKey {
    case zoneId, displayName, outputs, state, nicePlaying
    case isPreviousAllowed, isNextAllowed, isPauseAllowed, isPlayAllowed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    zoneId = try container.decode(String.self, forKey: .zoneId)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    outputs = try container.decodeIfPresent([ZoneOutput].self, forKey: .outputs) ?? []
    state = try container.decodeIfPresent(String.self, forKey: .state) ?? "stopped"
    nicePlaying = try? container.decode(ZoneNicePlaying.self, forKey: .nicePlaying)
    isPreviousAllowed = try container.decodeIfPresent(Bool.self, forKey: .isPreviousAllowed)
    isNextAllowed = try container.decodeIfPresent(Bool.self, forKey: .isNextAllowed)
    isPauseAllowed = try container.decodeIfPresent(Bool.self, forKey: .isPauseAllowed)
    isPlayAllowed = try container.decodeIfPresent(Bool.self, forKey: .isPlayAllowed)
  }
}

struct QueueTrackPayload: Decodable, Identifiable {
  var id: String { String(queueItemId) }
  var queueItemId: Int
  var title: String
  var artist: String?
  var imageKey: String?
  var length: String?
  var disk: PlayingDisk?

  private enum CodingKeys: String, CodingKey {
    case queueItemId, title, artist, imageKey, length, disk
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try? container.decode(Int.self, forKey: .queueItemId) {
      queueItemId = value
    } else if let value = try? container.decode(Double.self, forKey: .queueItemId) {
      queueItemId = Int(value)
    } else if let value = try? container.decode(String.self, forKey: .queueItemId),
              let parsed = Int(value)
    {
      queueItemId = parsed
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .queueItemId,
        in: container,
        debugDescription: "queue_item_id"
      )
    }
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    artist = try container.decodeIfPresent(String.self, forKey: .artist)
    imageKey = try container.decodeIfPresent(String.self, forKey: .imageKey)
    disk = try container.decodeIfPresent(PlayingDisk.self, forKey: .disk)
    if let value = try? container.decode(String.self, forKey: .length) {
      length = value
    } else if let value = try? container.decode(Double.self, forKey: .length) {
      length = String(value)
    } else {
      length = nil
    }
  }
}

struct QueueStatePayload: Decodable {
  var zoneId: String
  var tracks: [QueueTrackPayload]

  private enum CodingKeys: String, CodingKey {
    case zoneId, tracks, items
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    zoneId = try container.decodeIfPresent(String.self, forKey: .zoneId) ?? ""
    if let tracks = try? container.decode([QueueTrackPayload].self, forKey: .tracks) {
      self.tracks = tracks
    } else {
      self.tracks = (try? container.decode([QueueTrackPayload].self, forKey: .items)) ?? []
    }
  }
}

struct SharedConfigPayload: Decodable {
  var customActions: [CustomActionPayload]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    customActions = try container.decodeIfPresent([CustomActionPayload].self, forKey: .customActions) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case customActions
  }
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
