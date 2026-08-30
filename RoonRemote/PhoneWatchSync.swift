import Foundation
import UIKit
import WatchConnectivity
import HealthKit
import os.log

final class PhoneWatchSync: NSObject, WCSessionDelegate {
  static let shared = PhoneWatchSync()
  private static let log = Logger(subsystem: "com.djehring.roonremote", category: "watch")

  private weak var store: MockStore?
  private var lastEncoded: Data?
  private var lastWakeKey: String?
  private var watchLaunchArmed = true

  func activate(store: MockStore) {
    self.store = store
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  @MainActor
  func publish() {
    guard let store else { return }
    let snapshot = Self.snapshot(from: store)
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    let payload = [WatchMessageKey.snapshot: data]
    let session = WCSession.default
    guard session.activationState == .activated else { return }

    let dataChanged = data != lastEncoded
    if dataChanged {
      do {
        try session.updateApplicationContext(payload)
        lastEncoded = data
      } catch {
        Self.log.error("applicationContext failed: \(error.localizedDescription, privacy: .public)")
      }
    }
    if session.isReachable {
      if dataChanged {
        session.sendMessage(payload, replyHandler: nil) { error in
          Self.log.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
        }
      }
      lastWakeKey = nil
      watchLaunchArmed = !snapshot.isPlaying
    } else {
      _ = wakeWatchIfPlaying(session, snapshot: snapshot, payload: payload)
      openWatchAppIfPlaying(session, snapshot: snapshot)
    }
  }

  /// `transferUserInfo` launches the Watch app in the background when it is not
  /// already in the foreground. Only fire on play / track changes so volume ticks
  /// do not queue a pile of transfers.
  private func wakeWatchIfPlaying(
    _ session: WCSession,
    snapshot: WatchSnapshot,
    payload: [String: Any]
  ) -> Bool {
    guard session.isPaired, session.isWatchAppInstalled else { return false }
    guard snapshot.isPlaying else {
      lastWakeKey = nil
      return false
    }
    let wakeKey = "\(snapshot.zoneId)|\(snapshot.title ?? "")|\(snapshot.imageKey ?? "")"
    guard wakeKey != lastWakeKey else { return false }
    lastWakeKey = wakeKey
    session.outstandingUserInfoTransfers.forEach { $0.cancel() }
    session.transferUserInfo(payload)
    Self.log.info("waking watch for \(snapshot.title ?? "now playing", privacy: .public)")
    return true
  }

  /// Same path Pocket Trainer uses: HealthKit `startWatchApp` is the API that
  /// actually brings the companion on-wrist from the iPhone.
  private func openWatchAppIfPlaying(_ session: WCSession, snapshot: WatchSnapshot) {
    guard session.isPaired, session.isWatchAppInstalled else { return }
    guard snapshot.isPlaying else {
      watchLaunchArmed = true
      return
    }
    guard watchLaunchArmed else { return }
    watchLaunchArmed = false
    Task { @MainActor in
      let opened = await Self.openWatchApp()
      if !opened {
        self.watchLaunchArmed = true
      }
    }
  }

  private static func openWatchApp() async -> Bool {
    guard HKHealthStore.isHealthDataAvailable() else {
      log.error("HealthKit unavailable, cannot open Watch app")
      return false
    }
    let store = HKHealthStore()
    do {
      try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
      let status = store.authorizationStatus(for: HKObjectType.workoutType())
      guard status == .sharingAuthorized else {
        log.error("HealthKit not authorized, cannot open Watch app")
        return false
      }
      let config = HKWorkoutConfiguration()
      config.activityType = .other
      config.locationType = .indoor
      try await store.startWatchApp(toHandle: config)
      log.info("startWatchApp succeeded")
      return true
    } catch {
      log.error("startWatchApp failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Self.log.info(
      "phone session \(String(describing: activationState.rawValue), privacy: .public) paired=\(session.isPaired) watchApp=\(session.isWatchAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "none", privacy: .public)"
    )
    Task { @MainActor in self.publish() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor in self.publish() }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    Self.log.info("phone reachable=\(session.isReachable)")
    Task { @MainActor in self.publish() }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    handle(message)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handle(message)
    replyHandler(["ok": true])
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    handle(userInfo)
  }

  private func handle(_ message: [String: Any]) {
    guard let data = message[WatchMessageKey.command] as? Data,
          let command = try? JSONDecoder().decode(WatchCommand.self, from: data)
    else { return }
    Task { @MainActor in
      guard let store else { return }
      switch command {
      case .playPause:
        store.togglePlay()
      case .skip:
        store.skip()
      case .previous:
        store.previous()
      case .stop:
        store.stop()
      case .mute:
        let output = store.outputs.first { !$0.isFixed } ?? store.outputs.first
        if let output {
          store.toggleMute(output)
        }
      case let .setVolume(outputId, value):
        let output = store.outputs.first { $0.id == outputId } ?? store.outputs.first
        if let output {
          store.setVolume(output, value: value)
        }
      case let .selectZone(id):
        store.selectZone(id)
      case let .playFromHere(id):
        if let item = store.queue.first(where: { $0.id == id }) {
          store.playFromHere(item)
        }
      case let .transfer(toZoneId):
        store.transfer(to: toZoneId)
      case let .playInRoom(query, room):
        Task {
          _ = try? await store.playInRoom(query: query, roomName: room, zoneId: nil)
        }
      }
    }
  }

  @MainActor
  private static func snapshot(from store: MockStore) -> WatchSnapshot {
    let track = store.currentTrack
    let output = store.outputs.first { !$0.isFixed } ?? store.outputs.first
    let cover: Data?
    if let key = track?.imageKey,
       let data = store.artwork.data(
         for: ArtworkCache.Key(imageKey: key, pixels: ArtworkCache.thumbnailPixels)
       )
    {
      cover = compactJPEG(data)
    } else {
      cover = nil
    }
    return WatchSnapshot(
      sessionReady: store.session == .main && store.client.isPaired,
      zoneId: store.selectedZoneId,
      zoneName: store.selectedZone.name,
      isPlaying: store.isPlaying,
      isLoading: store.selectedZone.state == .loading,
      title: track?.title,
      artist: track?.artist,
      album: track?.album,
      imageKey: track?.imageKey,
      coverJPEG: cover,
      volume: output?.volume ?? 0,
      volumeMin: output?.min ?? 0,
      volumeMax: max(output?.max ?? 100, (output?.min ?? 0) + 1),
      volumeOutputId: output?.id,
      volumeIsFixed: output?.isFixed ?? true,
      muted: output?.muted ?? false,
      zones: store.zones.map {
        WatchZoneRow(id: $0.id, name: $0.name, subtitle: $0.track?.title)
      },
      queue: Array(store.upcomingQueue.prefix(50)).map {
        WatchQueueRow(id: $0.id, title: $0.title, artist: $0.artist)
      }
    )
  }

  private static func compactJPEG(_ data: Data, dimension: CGFloat = 180) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let size = CGSize(width: dimension, height: dimension)
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return scaled.jpegData(compressionQuality: 0.55)
  }
}
