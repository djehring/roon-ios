import Foundation

#if DEBUG
extension MockStore {
  /// True when the app was launched with `-roon-demo-store`.
  static var wantsDemoContent: Bool {
    ProcessInfo.processInfo.arguments.contains("-roon-demo-store")
  }

  /// Fills the store with stand-in content and skips straight to the main
  /// session.
  ///
  /// Layout work is otherwise invisible on a machine with no bridge on the
  /// network: with nothing to pair against, the app never leaves onboarding.
  /// Nothing here talks to the bridge, so browse and artwork stay empty --
  /// enough to check shells, spacing, and adaptivity, not content.
  func applyDemoContent() {
    let track = Track(
      id: "demo-track",
      title: "So What",
      artist: "Miles Davis",
      album: "Kind of Blue",
      position: "3:12",
      remaining: "5:48",
      progress: 0.35,
      imageKey: nil
    )
    zones = [
      Zone(id: "living", name: "Living Room", track: track, state: .playing),
      Zone(id: "kitchen", name: "Kitchen", track: nil, state: .stopped),
      Zone(id: "study", name: "Study", track: nil, state: .paused),
    ]
    selectedZoneId = "living"
    isPlaying = true
    outputs = [
      Output(
        id: "living-main",
        zoneId: "living",
        name: "Living Room",
        volume: 42,
        min: 0,
        max: 100,
        muted: false,
        isFixed: false,
        canGroupWith: []
      ),
    ]
    queue = [
      QueueItem(
        id: "q1",
        title: "Freddie Freeloader",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
      QueueItem(
        id: "q2",
        title: "Blue in Green",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
      QueueItem(
        id: "q3",
        title: "All Blues",
        artist: "Miles Davis",
        album: "Kind of Blue",
        imageKey: nil
      ),
    ]
    bridgeVersion = "demo"
    session = .main
  }
}
#endif
