import Intents
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    SiriMusicTrace.record("app.started", detail: "build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "")")
    NowPlayingBridge.registerLiveActivityActions()
    NowPlayingDiagnostics.record("app.started")
    RoonShortcuts.updateAppShortcutParameters()
    PhoneWatchSync.shared.activate()
    // Don't call INPreferences here: it requires com.apple.developer.siri, and
    // crashing at launch is worse than deferring Siri auth until the user uses it.
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
    }
    backgroundTask = application.beginBackgroundTask(withName: "roon-now-playing") {
      NowPlayingDiagnostics.record("background.timeExpired")
      application.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    NowPlayingDiagnostics.record("app.foreground")
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  /// The compact tab layout is portrait-only. A regular-width iPhone window,
  /// the unfolded iPhone Duo, turns with the device like an iPad.
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
    return window?.traitCollection.horizontalSizeClass == .regular ? .allButUpsideDown : .portrait
  }

  func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
    if intent is INPlayMediaIntent {
      return PlayMediaHandler()
    }
    return nil
  }

  func application(
    _ application: UIApplication,
    handle intent: INIntent,
    completionHandler: @escaping (INIntentResponse) -> Void
  ) {
    guard let play = intent as? INPlayMediaIntent else {
      completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
      return
    }
    Task {
      let response = await PlayMediaHandler().handle(intent: play)
      completionHandler(response)
    }
  }
}

final class PlayMediaHandler: NSObject, INPlayMediaIntentHandling {
  func resolveMediaItems(
    for intent: INPlayMediaIntent
  ) async -> [INPlayMediaMediaItemResolutionResult] {
    let phrase = Self.phrase(from: intent)
    SiriMusicTrace.record("sirikit.resolve", detail: phrase)
    let item = INMediaItem(
      identifier: phrase,
      title: phrase.isEmpty ? "House Remote" : phrase,
      type: .radioStation,
      artwork: nil,
      artist: intent.mediaSearch?.artistName
    )
    return [.success(with: item)]
  }

  func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
    let phrase = Self.phrase(from: intent)
    SiriMusicTrace.record("sirikit.play", detail: phrase)
    guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
    }
    do {
      _ = try await MockStore.shared.playSiriRequest(phrase)
      return INPlayMediaIntentResponse(code: .success, userActivity: nil)
    } catch {
      SiriMusicTrace.record("sirikit.error", detail: error.localizedDescription)
      return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
    }
  }

  private static func phrase(from intent: INPlayMediaIntent) -> String {
    PlayRequest.phrase(
      mediaName: intent.mediaSearch?.mediaName,
      artist: intent.mediaSearch?.artistName,
      album: intent.mediaSearch?.albumName,
      itemTitle: intent.mediaItems?.first?.title
    )
  }
}
