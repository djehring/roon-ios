import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit
import Intents
import os.log

final class WatchSessionRelay: NSObject, WCSessionDelegate {
  static let shared = WatchSessionRelay()
  private static let log = Logger(subsystem: "com.djehring.roonremote.watchkitapp", category: "watch")

  // Snapshot persistence must work on background launch before a SwiftUI scene exists.
  private let storage = WatchSnapshotStorage(defaults: UserDefaults(suiteName: WatchShared.suiteName)!)
  private let background = WatchBackgroundUpdates()
  private var pendingObservation: NSKeyValueObservation?
  private var activationObservation: NSKeyValueObservation?
  var onSnapshot: ((WatchSnapshot) -> Void)?
  var onReachable: ((Bool) -> Void)?
  var latestSnapshot: WatchSnapshot? { storage.snapshot }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    if pendingObservation == nil {
      pendingObservation = session.observe(\.hasContentPending) { [weak self] _, _ in
        DispatchQueue.main.async { self?.completeBackgroundTasks() }
      }
      activationObservation = session.observe(\.activationState) { [weak self] _, _ in
        DispatchQueue.main.async { self?.completeBackgroundTasks() }
      }
    }
    if session.activationState != .activated { session.activate() }
  }

  func pull() {
    onReachable?(WCSession.default.isReachable)
    receive(WCSession.default.receivedApplicationContext)
    if let snapshot = storage.snapshot { onSnapshot?(snapshot) }
  }

  func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
    background.retain { task.setTaskCompletedWithSnapshot(false) }
    activate()
    pull()
    completeBackgroundTasks()
  }

  private func completeBackgroundTasks() {
    let session = WCSession.default
    background.completeIfReady(activated: session.activationState == .activated,
      hasContentPending: session.hasContentPending)
  }

  private func receive(_ message: [String: Any]) {
    guard let data = message[WatchMessageKey.snapshot] as? Data else { return }
    do {
      let next = try JSONDecoder().decode(WatchSnapshot.self, from: data)
      guard case let .saved(reloadWidget) = try storage.receive(next) else { return }
      if reloadWidget { WidgetCenter.shared.reloadAllTimelines() }
      Self.log.info("saved snapshot zone=\(next.zoneId, privacy: .public) updated=\(next.updatedAt?.timeIntervalSince1970 ?? 0) widgetReload=\(reloadWidget)")
    } catch {
      Self.log.error("snapshot could not be saved: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func enqueue(_ message: [String: Any], reply: (([String: Any]) -> Void)? = nil) {
    // Register work before returning to WCSession, which may now clear hasContentPending.
    background.beginDelivery()
    DispatchQueue.main.async {
      self.receive(message)
      if let saved = self.storage.snapshot { self.onSnapshot?(saved) }
      reply?(["ok": true])
      self.background.endDelivery()
      self.completeBackgroundTasks()
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Self.log.info("watch session \(activationState.rawValue) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "none", privacy: .public)")
    background.beginDelivery()
    DispatchQueue.main.async {
      self.onReachable?(session.isReachable)
      self.pull()
      self.background.endDelivery()
      if error != nil {
        // Activation failed; there is no delivery to wait for on this attempt.
        self.background.completeIfReady(activated: true, hasContentPending: false)
      } else {
        self.completeBackgroundTasks()
      }
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.onReachable?(session.isReachable) }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    enqueue(applicationContext)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    enqueue(userInfo)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    enqueue(message)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    enqueue(message, reply: replyHandler)
  }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  func applicationDidFinishLaunching() {
    WatchSessionRelay.shared.activate()
  }

  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      if let wc = task as? WKWatchConnectivityRefreshBackgroundTask {
        WatchSessionRelay.shared.handle(wc)
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
  var controlError: String?

  var showsFindingServer: Bool {
    FindingServerGate.isVisible(
      isAwaitingServer: isAwaitingServer,
      isDiscovering: false
    ) && !snapshot.sessionReady
  }

  @ObservationIgnored private var crownUntil: Date?
  @ObservationIgnored private var volumeTask: Task<Void, Never>?
  @ObservationIgnored private var pinnedTitle: String?
  @ObservationIgnored private var replacedTitle: String?

  init() {
    let relay = WatchSessionRelay.shared
    relay.onSnapshot = { [weak self] snapshot in
      MainActor.assumeIsolated { self?.apply(snapshot) }
    }
    if let saved = relay.latestSnapshot { apply(saved) }
    relay.onReachable = { [weak self] reachable in
      MainActor.assumeIsolated { self?.phoneReachable = reachable }
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

  private func apply(_ next: WatchSnapshot) {
    let resolved = resolve(next)
    snapshot = resolved
    if resolved.sessionReady { isAwaitingServer = false }
    cover = resolved.coverJPEG
    let ignoringCrown = crownUntil.map { Date() < $0 } ?? false
    if !ignoringCrown { volume = resolved.volume }
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
    guard session.activationState == .activated else {
      controlError = "Connecting to iPhone. Try again in a moment."
      WatchSessionRelay.shared.activate()
      return
    }
    // An active watch can wake its iPhone with sendMessage. Queuing user info
    // instead can delay a pause or volume change until long after the gesture.
    session.sendMessage(payload, replyHandler: { [weak self] reply in
      Task { @MainActor in
        self?.controlError = reply["ok"] as? Bool == true
          ? nil : (reply["error"] as? String ?? "Couldn't control playback.")
      }
    }, errorHandler: { [weak self] _ in
      Task { @MainActor in
        self?.controlError = "Couldn't reach iPhone. Open House Remote on your iPhone and try again."
      }
    })
  }
}
