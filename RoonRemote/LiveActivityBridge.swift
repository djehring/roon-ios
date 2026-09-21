import ActivityKit
import Foundation
import UIKit
import os.log

/// Starts a Now Playing Live Activity so watchOS can show it in the Smart Stack
/// and open the Watch app from a tap. Apple does not let a music remote force
/// the Watch UI to the front; this is the supported path.
///
/// ActivityKit silently drops updates whose encoded ContentState is over 4 KB,
/// and it also stops applying updates once the hourly budget is gone. Zone
/// ticks arrive about once a second, so we coalesce to one in-flight publish,
/// skip when title / artist / zone / play state / art key have not changed,
/// and never alert on a track change — alerts spend the budget first.
@MainActor
final class LiveActivityBridge {
  static let shared = LiveActivityBridge()
  private static let log = Logger(subsystem: "com.djehring.roonremote", category: "live")
  private static let maxEncodedBytes = 3200
  private static let endDelay: Duration = .seconds(2)

  private var lastArtworkKey: String?
  private var lastArtworkJPEG: Data?
  private var wantsPublish = false
  private var worker: Task<Void, Never>?
  private var endTask: Task<Void, Never>?
  private var wantsEnd = false

  func publish() {
    wantsPublish = true
    if worker == nil {
      worker = Task { await self.drain() }
    }
  }

  /// Waits for the latest `publish()` so a lock-screen intent cannot return
  /// and let iOS suspend us before ActivityKit applies the new state.
  func flush() async {
    publish()
    await worker?.value
  }

  private func drain() async {
    while wantsPublish {
      wantsPublish = false
      await publishNow()
    }
    worker = nil
  }

  private func publishNow() async {
    let store = MockStore.shared
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    guard case .main = store.session, store.client.isPaired else {
      await endImmediately()
      return
    }
    guard let snapshot = NowPlayingSnapshot(zone: store.selectedZone, isPlaying: store.isPlaying) else {
      if wantsEnd {
        await endImmediately()
      } else {
        scheduleEnd()
      }
      return
    }
    endTask?.cancel()
    endTask = nil
    wantsEnd = false
    let track = snapshot.track
    var state = RoonNowPlayingAttributes.ContentState(
      zoneName: snapshot.zoneName,
      title: snapshot.title,
      artist: snapshot.artist,
      isPlaying: snapshot.isPlaying,
      zoneID: snapshot.zoneID
    )
    if let track {
      state.artworkJPEG = artworkJPEG(for: track, store: store, base: state)
    } else {
      lastArtworkKey = nil
      lastArtworkJPEG = nil
    }
    await upsert(zoneId: snapshot.zoneID, state: state.fittingBudget())
  }

  private func artworkJPEG(
    for track: Track,
    store: MockStore,
    base: RoonNowPlayingAttributes.ContentState
  ) -> Data? {
    guard let key = track.imageKey else {
      lastArtworkKey = nil
      lastArtworkJPEG = nil
      return nil
    }
    if lastArtworkKey == key, let cached = lastArtworkJPEG {
      return cached
    }
    guard let raw = Self.artworkData(for: track, store: store) else { return nil }
    for (dimension, quality) in [(72.0, 0.4), (56.0, 0.35), (40.0, 0.3)] {
      guard let jpeg = Self.compactJPEG(raw, dimension: dimension, quality: quality) else {
        continue
      }
      var candidate = base
      candidate.artworkJPEG = jpeg
      if let encoded = try? JSONEncoder().encode(candidate), encoded.count <= Self.maxEncodedBytes {
        lastArtworkKey = key
        lastArtworkJPEG = jpeg
        return jpeg
      }
    }
    return nil
  }

  private static func artworkData(for track: Track, store: MockStore) -> Data? {
    guard let key = track.imageKey else { return nil }
    let sizes = [ArtworkCache.thumbnailPixels, ArtworkCache.gridPixels, ArtworkCache.heroPixels]
    for pixels in sizes {
      if let data = store.artwork.data(for: ArtworkCache.Key(imageKey: key, pixels: pixels)) {
        return data
      }
    }
    return nil
  }

  private static func compactJPEG(_ data: Data, dimension: CGFloat, quality: CGFloat) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let size = CGSize(width: dimension, height: dimension)
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return scaled.jpegData(compressionQuality: quality)
  }

  private func upsert(
    zoneId: String,
    state: RoonNowPlayingAttributes.ContentState
  ) async {
    let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)
    let live = Activity<RoonNowPlayingAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
    if let activity = live.first {
      // Compare with ActivityKit, not a process-local fingerprint. The system
      // can end/reset an activity without the selected track changing.
      if activity.content.state != state || activity.activityState == .stale {
        await activity.update(content)
      }
      for duplicate in live.dropFirst() {
        await duplicate.end(nil, dismissalPolicy: .immediate)
      }
      return
    }
    // ActivityKit only permits starting an activity in the foreground. Retry
    // on activation rather than logging a failed request for every zone tick.
    guard UIApplication.shared.applicationState == .active else { return }
    do {
      let attributes = RoonNowPlayingAttributes(zoneId: zoneId)
      _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    } catch {
      Self.log.error("live activity failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func scheduleEnd() {
    guard endTask == nil else { return }
    endTask = Task {
      try? await Task.sleep(for: Self.endDelay)
      guard !Task.isCancelled else { return }
      // Serialize ending with updates. A separate async end can otherwise
      // finish after a new track has already been published.
      self.wantsEnd = true
      self.publish()
    }
  }

  private func endImmediately() async {
    endTask?.cancel()
    endTask = nil
    wantsEnd = false
    lastArtworkKey = nil
    lastArtworkJPEG = nil
    for activity in Activity<RoonNowPlayingAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
