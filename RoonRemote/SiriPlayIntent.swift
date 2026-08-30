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

struct RoonRoomEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Room")
  static var defaultQuery = RoonRoomQuery()

  var id: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(id)")
  }
}

struct RoonRoomQuery: EntityStringQuery {
  func entities(for identifiers: [RoonRoomEntity.ID]) async throws -> [RoonRoomEntity] {
    identifiers.map { RoonRoomEntity(id: $0) }
  }

  func entities(matching string: String) async throws -> [RoonRoomEntity] {
    let rooms = await RoonSiriSupport.roomNames()
    let matches = rooms.filter { RoonVoiceMatch.score($0, query: string) >= 50 }
    if matches.isEmpty { return [RoonRoomEntity(id: string)] }
    return matches.map { RoonRoomEntity(id: $0) }
  }

  func suggestedEntities() async throws -> [RoonRoomEntity] {
    await RoonSiriSupport.roomNames().map { RoonRoomEntity(id: $0) }
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
    AppShortcut(
      intent: IncreaseVolumeIntent(),
      phrases: [
        "Turn it up with \(.applicationName)",
        "Increase the volume with \(.applicationName)",
        "Turn it up in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Increase volume",
      systemImageName: "speaker.plus.fill"
    )
    AppShortcut(
      intent: DecreaseVolumeIntent(),
      phrases: [
        "Turn it down with \(.applicationName)",
        "Decrease the volume with \(.applicationName)",
        "Turn it down in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Decrease volume",
      systemImageName: "speaker.minus.fill"
    )
    AppShortcut(
      intent: StopPlaybackIntent(),
      phrases: [
        "Stop with \(.applicationName)",
        "Stop the track with \(.applicationName)",
        "Stop the music with \(.applicationName)",
        "Stop in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Stop",
      systemImageName: "stop.fill"
    )
    AppShortcut(
      intent: PlayPauseIntent(),
      phrases: [
        "Pause with \(.applicationName)",
        "Play or pause with \(.applicationName)",
        "Pause in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Play or pause",
      systemImageName: "playpause.fill"
    )
    AppShortcut(
      intent: SkipTrackIntent(),
      phrases: [
        "Skip with \(.applicationName)",
        "Next track with \(.applicationName)",
        "Skip in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Next track",
      systemImageName: "forward.fill"
    )
    AppShortcut(
      intent: PreviousTrackIntent(),
      phrases: [
        "Previous track with \(.applicationName)",
        "Go back with \(.applicationName)",
        "Previous track in \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Previous track",
      systemImageName: "backward.fill"
    )
    AppShortcut(
      intent: MuteIntent(),
      phrases: [
        "Mute with \(.applicationName)",
        "Mute \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Mute",
      systemImageName: "speaker.slash.fill"
    )
    AppShortcut(
      intent: UnmuteIntent(),
      phrases: [
        "Unmute with \(.applicationName)",
        "Unmute \(\.$room) with \(.applicationName)",
      ],
      shortTitle: "Unmute",
      systemImageName: "speaker.wave.2.fill"
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
