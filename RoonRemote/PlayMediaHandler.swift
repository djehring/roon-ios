import Intents
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Don't call INPreferences here: it requires com.apple.developer.siri, and
    // crashing at launch is worse than deferring Siri auth until the user uses it.
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
    }
    backgroundTask = application.beginBackgroundTask(withName: "roon-now-playing") {
      application.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
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
    let parsed = PlayRequest.parse(Self.phrase(from: intent))
    guard !parsed.what.isEmpty else {
      return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
    }
    do {
      _ = try await MockStore.shared.playInRoom(
        query: parsed.what,
        roomName: parsed.room ?? "",
        zoneId: nil
      )
      return INPlayMediaIntentResponse(code: .success, userActivity: nil)
    } catch {
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
