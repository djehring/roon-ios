#if os(iOS)
import AppIntents

/// Hooks the lock-screen Live Activity buttons into the app process.
/// `LiveActivityIntent.perform()` runs in the app, not the widget.
enum NowPlayingLiveActions {
  @MainActor
  static var playPause: (() async -> Void)?
}

struct NowPlayingPlayPauseIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Play or pause"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await NowPlayingLiveActions.playPause?()
    return .result()
  }
}
#endif
