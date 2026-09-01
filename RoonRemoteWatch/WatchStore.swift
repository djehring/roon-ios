import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit
import Intents
import os.log

final class WatchSessionRelay: NSObject, WCSessionDelegate {
  static let shared = WatchSessionRelay()
  private static let log = Logger(subsystem: "com.djehring.roonremote.watchkitapp", category: "watch")

  var onSnapshot: (([String: Any]) -> Void)?
  var onReachable: ((Bool) -> Void)?

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func pull() {
    let context = WCSession.default.receivedApplicationContext
    if context.isEmpty { return }
    NSLog("watch pull context count=%lu", context.count)
    onSnapshot?(context)
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Self.log.info(
      "watch session \(activationState.rawValue) reachable=\(session.isReachable) companion=\(session.isCompanionAppInstalled) error=\(error?.localizedDescription ?? "none", privacy: .public)"
    )
    DispatchQueue.main.async {
      self.onReachable?(session.isReachable)
      self.pull()
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.onReachable?(session.isReachable) }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    NSLog("watch didReceiveApplicationContext count=%lu", applicationContext.count)
    DispatchQueue.main.async { self.onSnapshot?(applicationContext) }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    DispatchQueue.main.async { self.onSnapshot?(userInfo) }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async { self.onSnapshot?(message) }
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    DispatchQueue.main.async { self.onSnapshot?(message) }
    replyHandler(["ok": true])
  }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      if let wc = task as? WKWatchConnectivityRefreshBackgroundTask {
        WatchSessionRelay.shared.pull()
        wc.setTaskCompletedWithSnapshot(false)
      } else {
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }

  func handle(_ intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
    guard let play = intent as? INPlayMediaIntent else {
      completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let phrase = PlayRequest.phrase(
      mediaName: play.mediaSearch?.mediaName,
      artist: play.mediaSearch?.artistName,
      album: play.mediaSearch?.albumName,
      itemTitle: play.mediaItems?.first?.title
    )
    let parsed = PlayRequest.parse(phrase)
    guard !parsed.what.isEmpty,
          let data = try? JSONEncoder().encode(
            WatchCommand.playInRoom(query: parsed.what, room: parsed.room ?? "")
          )
    else {
      completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
      return
    }
    let payload = [WatchMessageKey.command: data]
    let session = WCSession.default
    if session.activationState != .activated {
      WatchSessionRelay.shared.activate()
    }
    if session.isReachable {
      session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    } else {
      session.transferUserInfo(payload)
    }
    completionHandler(INPlayMediaIntentResponse(code: .success, userActivity: nil))
  }

  func handleIntent(_ intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
    handle(intent, completionHandler: completionHandler)
  }
}

@MainActor
@Observable
final class WatchStore {
  var snapshot = WatchSnapshot.empty
  var cover: Data?
  var volume: Double = 0
  var phoneReachable = false
  var isAwaitingServer = true

  var showsFindingServer: Bool {
    FindingServerGate.isVisible(
      isAwaitingServer: isAwaitingServer,
      isDiscovering: false
    ) && !snapshot.sessionReady
  }

  @ObservationIgnored private var lastImageKey: String?
  @ObservationIgnored private var crownUntil: Date?
  @ObservationIgnored private var volumeTask: Task<Void, Never>?
  @ObservationIgnored private var pinnedTitle: String?
  @ObservationIgnored private var replacedTitle: String?

  init() {
    let relay = WatchSessionRelay.shared
    relay.onSnapshot = { [weak self] message in
      Task { @MainActor in self?.apply(message) }
    }
    relay.onReachable = { [weak self] reachable in
      Task { @MainActor in self?.phoneReachable = reachable }
    }
  }

  var canControl: Bool { snapshot.sessionReady }

  var crownEnabled: Bool {
    canControl
      && !snapshot.volumeIsFixed
      && snapshot.volumeOutputId != nil
      && snapshot.volumeMax > snapshot.volumeMin
  }

  var volumeHUD: Double?

  func activate() {
    WatchSessionRelay.shared.activate()
    WatchSessionRelay.shared.pull()
    Task {
      for _ in 0..<25 {
        try? await Task.sleep(nanoseconds: 400_000_000)
        WatchSessionRelay.shared.pull()
        if snapshot.sessionReady {
          isAwaitingServer = false
          return
        }
      }
      isAwaitingServer = false
    }
  }

  func pull() {
    WatchSessionRelay.shared.pull()
  }

  func playPause() {
    send(.playPause)
  }

  func skip() {
    send(.skip)
  }

  func previous() {
    send(.previous)
  }

  func stop() {
    send(.stop)
  }

  func mute() {
    send(.mute)
  }

  func selectZone(_ id: String) {
    send(.selectZone(id: id))
  }

  func playFromHere(_ id: String) {
    if let item = snapshot.queue.first(where: { $0.id == id }) {
      if item.title != snapshot.title {
        replacedTitle = snapshot.title
        pinnedTitle = item.title
      }
      snapshot.title = item.title
      snapshot.artist = item.artist
      snapshot.isPlaying = true
    }
    send(.playFromHere(id: id))
  }

  func transfer(to id: String) {
    send(.transfer(toZoneId: id))
  }

  func crownMoved(_ value: Double) {
    volume = value
    volumeHUD = value
    crownUntil = Date().addingTimeInterval(0.8)
    volumeTask?.cancel()
    guard let outputId = snapshot.volumeOutputId else { return }
    volumeTask = Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      guard !Task.isCancelled else { return }
      send(.setVolume(outputId: outputId, value: value))
      try? await Task.sleep(nanoseconds: 720_000_000)
      guard !Task.isCancelled else { return }
      if Date() >= (crownUntil ?? .distantPast) {
        volumeHUD = nil
      }
    }
  }

  private func apply(_ message: [String: Any]) {
    guard let raw = message[WatchMessageKey.snapshot] else {
      NSLog("watch apply missing snapshot, keys=%@", Array(message.keys) as NSArray)
      return
    }
    let data: Data?
    if let value = raw as? Data {
      data = value
    } else if let value = raw as? NSData {
      data = value as Data
    } else {
      NSLog("watch apply snapshot type=%@", String(describing: type(of: raw)))
      return
    }
    guard let data else { return }
    do {
      let next = try JSONDecoder().decode(WatchSnapshot.self, from: data)
      let resolved = resolve(next)
      snapshot = resolved
      phoneReachable = true
      if resolved.sessionReady {
        isAwaitingServer = false
      }
      if let jpeg = resolved.coverJPEG {
        cover = jpeg
        lastImageKey = resolved.imageKey
      } else if resolved.imageKey != lastImageKey {
        cover = nil
        lastImageKey = resolved.imageKey
      }
      let ignoringCrown = crownUntil.map { Date() < $0 } ?? false
      if !ignoringCrown {
        volume = resolved.volume
      }
      persist(resolved)
      NSLog("watch snapshot ready=%d title=%@", resolved.sessionReady, resolved.title ?? "nil")
    } catch {
      NSLog("watch decode failed: %@", error.localizedDescription)
    }
  }

  private func resolve(_ next: WatchSnapshot) -> WatchSnapshot {
    guard let pinned = pinnedTitle else { return next }
    if next.title == pinned {
      pinnedTitle = nil
      replacedTitle = nil
      return next
    }
    if next.title == replacedTitle {
      var merged = next
      merged.title = pinned
      merged.artist = snapshot.artist
      merged.isPlaying = true
      return merged
    }
    pinnedTitle = nil
    replacedTitle = nil
    return next
  }

  private func send(_ command: WatchCommand) {
    guard let data = try? JSONEncoder().encode(command) else { return }
    let payload = [WatchMessageKey.command: data]
    let session = WCSession.default
    guard session.activationState == .activated else { return }
    if session.isReachable {
      session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    } else {
      session.transferUserInfo(payload)
    }
  }

  private func persist(_ snapshot: WatchSnapshot) {
    var stored = snapshot
    stored.coverJPEG = nil
    let defaults = UserDefaults(suiteName: WatchShared.suiteName)
    if let data = try? JSONEncoder().encode(stored) {
      defaults?.set(data, forKey: WatchShared.snapshotKey)
    }
    if let cover {
      defaults?.set(cover, forKey: WatchShared.coverKey)
    } else if snapshot.imageKey == nil {
      defaults?.removeObject(forKey: WatchShared.coverKey)
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
}
