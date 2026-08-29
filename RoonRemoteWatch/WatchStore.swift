import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
  var snapshot = WatchSnapshot.empty
  var cover: Data?
  var volume: Double = 0
  var phoneReachable = false

  @ObservationIgnored private var lastImageKey: String?
  @ObservationIgnored private var crownUntil: Date?
  @ObservationIgnored private var volumeTask: Task<Void, Never>?

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  var canControl: Bool { snapshot.sessionReady }

  var crownEnabled: Bool {
    canControl
      && !snapshot.volumeIsFixed
      && snapshot.volumeOutputId != nil
      && snapshot.volumeMax > snapshot.volumeMin
  }

  func playPause() {
    send(.playPause)
  }

  func skip() {
    send(.skip)
  }

  func selectZone(_ id: String) {
    send(.selectZone(id: id))
  }

  func crownMoved(_ value: Double) {
    volume = value
    crownUntil = Date().addingTimeInterval(0.45)
    volumeTask?.cancel()
    guard let outputId = snapshot.volumeOutputId else { return }
    volumeTask = Task {
      try? await Task.sleep(nanoseconds: 80_000_000)
      guard !Task.isCancelled else { return }
      send(.setVolume(outputId: outputId, value: value))
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Task { @MainActor in
      phoneReachable = session.isReachable
      apply(session.receivedApplicationContext)
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in phoneReachable = session.isReachable }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in apply(applicationContext) }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    Task { @MainActor in apply(userInfo) }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in apply(message) }
  }

  private func apply(_ message: [String: Any]) {
    guard let data = message[WatchMessageKey.snapshot] as? Data,
          let next = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    else { return }
    snapshot = next
    if let jpeg = next.coverJPEG {
      cover = jpeg
      lastImageKey = next.imageKey
    } else if next.imageKey != lastImageKey {
      cover = nil
      lastImageKey = next.imageKey
    }
    let ignoringCrown = crownUntil.map { Date() < $0 } ?? false
    if !ignoringCrown {
      volume = next.volume
    }
    persist(next)
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
