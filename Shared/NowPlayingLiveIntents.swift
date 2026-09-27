#if os(iOS)
import AppIntents

/// Hooks the lock-screen Live Activity buttons into the app process.
/// `LiveActivityIntent.perform()` runs in the app, not the widget.
enum NowPlayingLiveActions {
  @MainActor
  static var playPause: ((String?) async throws -> Void)?

  enum ActionError: LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? {
      "Open House Remote on iPhone to reconnect playback controls."
    }
  }
}

struct NowPlayingPlayPauseIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Play or pause"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Room ID")
  var zoneID: String?

  init() {}

  init(zoneID: String?) {
    self.zoneID = zoneID
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let playPause = NowPlayingLiveActions.playPause else {
      throw NowPlayingLiveActions.ActionError.unavailable
    }
    try await playPause(zoneID)
    return .result()
  }
}
#endif
