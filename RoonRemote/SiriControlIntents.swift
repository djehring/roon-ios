import AppIntents
import Foundation

struct IncreaseVolumeIntent: AppIntent {
  static var title: LocalizedStringResource = "Increase volume"
  static var description = IntentDescription("Turn the volume up on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Turn it up in \(\.$room)")
    } otherwise: {
      Summary("Turn it up")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriAdjustVolume(steps: 1, roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct DecreaseVolumeIntent: AppIntent {
  static var title: LocalizedStringResource = "Decrease volume"
  static var description = IntentDescription("Turn the volume down on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Turn it down in \(\.$room)")
    } otherwise: {
      Summary("Turn it down")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriAdjustVolume(steps: -1, roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct StopPlaybackIntent: AppIntent {
  static var title: LocalizedStringResource = "Stop"
  static var description = IntentDescription("Stop playback on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Stop in \(\.$room)")
    } otherwise: {
      Summary("Stop")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriStop(roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct PlayPauseIntent: AppIntent {
  static var title: LocalizedStringResource = "Play or pause"
  static var description = IntentDescription("Play or pause the current Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Play or pause in \(\.$room)")
    } otherwise: {
      Summary("Play or pause")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriPlayPause(roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct SkipTrackIntent: AppIntent {
  static var title: LocalizedStringResource = "Next track"
  static var description = IntentDescription("Skip to the next track on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Skip in \(\.$room)")
    } otherwise: {
      Summary("Skip")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriSkip(roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct PreviousTrackIntent: AppIntent {
  static var title: LocalizedStringResource = "Previous track"
  static var description = IntentDescription("Go back to the previous track on a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Previous track in \(\.$room)")
    } otherwise: {
      Summary("Previous track")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriPrevious(roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct MuteIntent: AppIntent {
  static var title: LocalizedStringResource = "Mute"
  static var description = IntentDescription("Mute a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Mute \(\.$room)")
    } otherwise: {
      Summary("Mute")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriSetMute(true, roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}

struct UnmuteIntent: AppIntent {
  static var title: LocalizedStringResource = "Unmute"
  static var description = IntentDescription("Unmute a Roon zone.")
  static var openAppWhenRun = false

  @Parameter(title: "Room")
  var room: RoonRoomEntity?

  static var parameterSummary: some ParameterSummary {
    When(\.$room, .hasAnyValue) {
      Summary("Unmute \(\.$room)")
    } otherwise: {
      Summary("Unmute")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let spoken = try await MockStore.shared.siriSetMute(false, roomName: room?.id ?? "")
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}
