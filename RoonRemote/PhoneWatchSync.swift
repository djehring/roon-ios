import Foundation
import UIKit
import WatchConnectivity

@MainActor
final class PhoneWatchSync: NSObject, WCSessionDelegate {
  static let shared = PhoneWatchSync()

  private weak var store: MockStore?
  private var lastEncoded: Data?

  func activate(store: MockStore) {
    self.store = store
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func publish() {
    guard let store else { return }
    let snapshot = Self.snapshot(from: store)
    guard let data = try? JSONEncoder().encode(snapshot), data != lastEncoded else { return }
    lastEncoded = data
    let payload = [WatchMessageKey.snapshot: data]
    let session = WCSession.default
    guard session.activationState == .activated else { return }
    if session.isPaired, session.isWatchAppInstalled, session.isReachable {
      session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
    try? session.updateApplicationContext(payload)
    if session.isComplicationEnabled {
      session.transferCurrentComplicationUserInfo(payload)
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
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
      case let .setVolume(outputId, value):
        let output = store.outputs.first { $0.id == outputId } ?? store.outputs.first
        if let output {
          store.setVolume(output, value: value)
        }
      case let .selectZone(id):
        store.selectZone(id)
      }
    }
  }

  private static func snapshot(from store: MockStore) -> WatchSnapshot {
    let track = store.currentTrack
    let output = store.outputs.first { !$0.isFixed } ?? store.outputs.first
    let cover: Data?
    if let key = track?.imageKey, let data = store.coverCache[key] {
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
      zones: store.zones.map {
        WatchZoneRow(id: $0.id, name: $0.name, subtitle: $0.track?.title)
      }
    )
  }

  private static func compactJPEG(_ data: Data, dimension: CGFloat = 96) -> Data? {
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
