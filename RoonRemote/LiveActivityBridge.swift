import ActivityKit
import Foundation
import UIKit
import os.log

/// Starts a Now Playing Live Activity so watchOS can show it in the Smart Stack
/// and open the Watch app from a tap. Apple does not let a music remote force
/// the Watch UI to the front; this is the supported path.
///
/// ActivityKit limits encoded ContentState to 4 KB. Local updates require the
/// app to be running; the hourly push budget does not apply to this local path.
/// Zone ticks arrive about once a second, so we coalesce to one in-flight publish,
/// skip when title / artist / zone / play state / art key have not changed,
/// and never alert on a track change.
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
  private var publicationGate = LiveActivityPublicationGate()
  private var observedActivityID: String?
  private var pushToken: Data?
  private var observationTasks: [Task<Void, Never>] = []
  private let pushRegistrar = LiveActivityPushRegistrar(
    register: LiveActivityPushHTTP.register, remove: LiveActivityPushHTTP.remove)

  func resume() {
    publicationGate.reset()
    pushRegistrar.retryNow()
    publish()
  }

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
    guard let observedAt = store.selectedZoneUpdatedAt else { return }
    await upsert(zoneId: snapshot.zoneID, state: state.fittingBudget(),
      staleDate: snapshot.staleDate(observedAt: observedAt),
      observedAt: observedAt,
      fresh: store.syncState == .sync && Date().timeIntervalSince(observedAt) < (snapshot.isPlaying ? 15 : 600))
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
    state: RoonNowPlayingAttributes.ContentState,
    staleDate: Date,
    observedAt: Date,
    fresh: Bool
  ) async {
    let foreground = UIApplication.shared.applicationState == .active
    let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)
    var live = Activity<RoonNowPlayingAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
    // Existing installations can have a local-only card. Replace it once in
    // the foreground, where requesting a push-enabled activity is permitted.
    if foreground, fresh {
      for activity in live where activity.attributes.pushEnabled != true {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      live.removeAll { $0.attributes.pushEnabled != true }
    }
    if let activity = live.first {
      observe(activity)
      registerPush(activity: activity, zoneID: zoneId)
      // Keep a bounded local fallback when the bridge cannot reach APNs. Use
      // the observation time so a delayed snapshot cannot supersede newer data.
      if fresh,
        publicationGate.shouldPublish(id: activity.id, content: state, staleDate: staleDate) {
        await activity.update(content, alertConfiguration: nil, timestamp: observedAt)
        NowPlayingDiagnostics.record("activity.submitted", detail: "\(state.zoneName) | \(state.title) | playing=\(state.isPlaying)")
      }
      for duplicate in live.dropFirst() {
        await duplicate.end(nil, dismissalPolicy: .immediate)
      }
      return
    }
    // ActivityKit only permits starting an activity in the foreground. Retry
    // on activation rather than logging a failed request for every zone tick.
    guard foreground, fresh else { return }
    do {
      let attributes = RoonNowPlayingAttributes(zoneId: zoneId, pushEnabled: true)
      let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
      _ = publicationGate.shouldPublish(id: activity.id, content: state, staleDate: staleDate)
      observe(activity)
      registerPush(activity: activity, zoneID: zoneId)
      NowPlayingDiagnostics.record("activity.started", detail: "\(state.zoneName) | \(state.title)")
    } catch {
      NowPlayingDiagnostics.record("activity.failed", detail: error.localizedDescription)
      Self.log.error("live activity failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func observe(_ activity: Activity<RoonNowPlayingAttributes>) {
    guard observedActivityID != activity.id else { return }
    observationTasks.forEach { $0.cancel() }
    observedActivityID = activity.id
    pushToken = activity.pushToken
    observationTasks = [
      Task { [weak self] in
        for await token in activity.pushTokenUpdates {
          guard !Task.isCancelled, let self, self.observedActivityID == activity.id else { return }
          self.pushToken = token
          self.publish()
        }
      },
      Task { [weak self] in
        for await status in activity.activityStateUpdates {
          guard !Task.isCancelled, let self, self.observedActivityID == activity.id else { return }
          if status == .dismissed || status == .ended {
            self.pushRegistrar.update(nil)
            return
          }
        }
      },
      Task {
        for await observed in activity.contentUpdates {
          guard !Task.isCancelled else { return }
          NowPlayingDiagnostics.record("activity.observed", detail: "\(observed.state.zoneName) | \(observed.state.title)")
        }
      },
    ]
  }

  private func registerPush(activity: Activity<RoonNowPlayingAttributes>, zoneID: String) {
    guard let token = pushToken, let baseURL = MockStore.shared.client.liveActivityPushBaseURL,
      let environment = Bundle.main.object(forInfoDictionaryKey: "RoonPushEnvironment") as? String,
      ["sandbox", "production"].contains(environment) else { return }
    pushRegistrar.update(LiveActivityPushTarget(baseURL: baseURL, activityID: activity.id,
      pushToken: token.map { String(format: "%02x", $0) }.joined(), zoneID: zoneID, environment: environment))
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
    publicationGate.reset()
    observationTasks.forEach { $0.cancel() }
    observationTasks.removeAll()
    observedActivityID = nil
    pushToken = nil
    pushRegistrar.update(nil)
    for activity in Activity<RoonNowPlayingAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
