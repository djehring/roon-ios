import AppIntents
import Foundation

struct PlayInRoomIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Play in a room"
  static var description = IntentDescription("Play a radio station, album, or playlist on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(
    title: "What to play",
    requestValueDialog: "What should I play, and in which room?"
  )
  var request: PlayUtteranceEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Play \(\.$request)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let parsed = PlayRequest.parse(request.id)
    let spoken = try await MockStore.shared.playInRoom(
      query: parsed.what,
      roomName: parsed.room ?? "",
      zoneId: nil
    )
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct PlayUtteranceEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Station or album")
  static var defaultQuery = PlayUtteranceQuery()

  var id: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(id)")
  }
}

struct PlayUtteranceQuery: EntityStringQuery {
  func entities(for identifiers: [PlayUtteranceEntity.ID]) async throws -> [PlayUtteranceEntity] {
    identifiers.map { PlayUtteranceEntity(id: $0) }
  }

  func entities(matching string: String) async throws -> [PlayUtteranceEntity] {
    [PlayUtteranceEntity(id: string)]
  }

  func suggestedEntities() async throws -> [PlayUtteranceEntity] {
    let rooms = await RoonSiriSupport.roomNames()
    if rooms.isEmpty {
      return [
        PlayUtteranceEntity(id: "Radio 3 in the Kitchen"),
        PlayUtteranceEntity(id: "Radio 4 in the Kitchen"),
      ]
    }
    return rooms.prefix(6).map { PlayUtteranceEntity(id: "Radio 3 in \($0)") }
  }
}

enum PlayRequest {
  static func parse(_ raw: String) -> (what: String, room: String?) {
    let separators = [" in the ", " in ", " on the ", " on "]
    for separator in separators {
      if let range = raw.range(of: separator, options: [.backwards, .caseInsensitive]) {
        let what = raw[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let room = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !what.isEmpty && !room.isEmpty {
          return (what, room)
        }
      }
    }
    return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
  }
}

struct RoonShortcuts: AppShortcutsProvider {
  static var shortcutTileColor: ShortcutTileColor { .navy }

  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayInRoomIntent(),
      phrases: [
        "Play in a room with \(.applicationName)",
        "Play \(\.$request) with \(.applicationName)",
        "Play \(\.$request) on \(.applicationName)",
      ],
      shortTitle: "Play in a room",
      systemImageName: "hifispeaker.fill"
    )
  }
}

enum RoonSiriSupport {
  private static let roomsKey = "siriRooms"

  static func roomsUpdated(_ zones: [Zone]) {
    UserDefaults.standard.set(zones.map(\.name), forKey: roomsKey)
    RoonShortcuts.updateAppShortcutParameters()
  }

  static func roomNames() async -> [String] {
    let live = await MainActor.run { MockStore.shared.zones.map(\.name) }
    if !live.isEmpty { return live }
    return UserDefaults.standard.stringArray(forKey: roomsKey) ?? []
  }
}
