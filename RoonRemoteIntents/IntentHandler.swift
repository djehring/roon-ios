import Intents

@objc(IntentHandler)
final class IntentHandler: INExtension, INPlayMediaIntentHandling {
  override func handler(for intent: INIntent) -> Any {
    self
  }

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
    let phrase = Self.phrase(from: intent)
    let activity = NSUserActivity(activityType: "com.djehring.roonremote.playMedia")
    activity.title = phrase
    activity.userInfo = ["phrase": phrase]
    return INPlayMediaIntentResponse(code: .handleInApp, userActivity: activity)
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
