#if !os(tvOS)
import Foundation

/// Stable timestamps make context, messages and queued transfers comparable.
/// Repeated publications reuse their timestamp; a restart preserves the clock.
struct WatchSnapshotPublication {
  private var previous: WatchSnapshot?
  private(set) var lastDate: Date

  init(lastDate: Date = .distantPast) { self.lastDate = lastDate }

  mutating func stamp(_ snapshot: WatchSnapshot, now: Date = Date()) -> WatchSnapshot {
    var content = snapshot
    content.updatedAt = nil
    if content != previous {
      lastDate = max(now, lastDate.addingTimeInterval(0.001))
      previous = content
    }
    content.updatedAt = lastDate
    return content
  }
}

/// Owned by the receiver, independent of whether the Watch screen exists.
/// Persist the cover with its metadata so the widget reads one coherent value.
final class WatchSnapshotStorage {
  enum Receipt: Equatable {
    case ignored
    case saved(reloadWidget: Bool)
  }

  private let defaults: UserDefaults
  private(set) var snapshot: WatchSnapshot?

  init(defaults: UserDefaults) {
    self.defaults = defaults
    if let data = defaults.data(forKey: WatchShared.snapshotKey),
       var saved = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
      // Read installations that previously stored the cover separately.
      if saved.coverJPEG == nil, saved.imageKey != nil {
        saved.coverJPEG = defaults.data(forKey: WatchShared.coverKey)
      }
      snapshot = saved
    }
  }

  func receive(_ incoming: WatchSnapshot) throws -> Receipt {
    if let currentDate = snapshot?.updatedAt {
      guard let incomingDate = incoming.updatedAt, incomingDate >= currentDate else { return .ignored }
    }
    var next = incoming
    if next.coverJPEG == nil, next.imageKey != nil, next.imageKey == snapshot?.imageKey {
      next.coverJPEG = snapshot?.coverJPEG
    }
    guard next != snapshot else { return .ignored }
    let reload = snapshot.map { current in
      current.sessionReady != next.sessionReady || current.zoneId != next.zoneId
        || current.zoneName != next.zoneName || current.title != next.title
        || current.artist != next.artist || current.isPlaying != next.isPlaying
        || current.imageKey != next.imageKey || current.coverJPEG != next.coverJPEG
    } ?? true
    let data = try JSONEncoder().encode(next)
    defaults.set(data, forKey: WatchShared.snapshotKey)
    defaults.removeObject(forKey: WatchShared.coverKey)
    snapshot = next
    return .saved(reloadWidget: reload)
  }
}

/// WCSession can mark its content delivered before our main-queue work runs.
/// Retain background tasks until both the framework and our persistence finish.
final class WatchBackgroundUpdates: @unchecked Sendable {
  private let lock = NSLock()
  private var deliveries = 0
  private var completions: [() -> Void] = []

  func beginDelivery() { lock.withLock { deliveries += 1 } }
  func endDelivery() { lock.withLock { deliveries -= 1 } }
  func retain(_ completion: @escaping () -> Void) { lock.withLock { completions.append(completion) } }

  /// Called on the main queue, after requesting any required widget reload.
  func completeIfReady(activated: Bool, hasContentPending: Bool) {
    let ready: [() -> Void] = lock.withLock {
      guard activated, !hasContentPending, deliveries == 0 else { return [] }
      let result = completions
      completions.removeAll()
      return result
    }
    ready.forEach { $0() }
  }
}
#endif
