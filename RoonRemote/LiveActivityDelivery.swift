#if os(iOS)
import Foundation

/// ActivityKit may keep reporting old content after accepting an update request.
/// Track our submissions by activity ID instead of retrying on every zone tick.
struct LiveActivityPublicationGate {
  private var activityID: String?
  private var state: RoonNowPlayingAttributes.ContentState?
  private var refreshAfter = Date.distantPast
  private var submittedStaleDate = Date.distantPast

  mutating func shouldPublish(id: String, content: RoonNowPlayingAttributes.ContentState,
    staleDate: Date, now: Date = Date()) -> Bool {
    // Seeking towards the end must shorten freshness immediately. A later
    // deadline can wait for renewal, avoiding a flood from sliding radio leases.
    let expiresEarlier = staleDate < submittedStaleDate.addingTimeInterval(-15)
    guard activityID != id || state != content || now >= refreshAfter || expiresEarlier else { return false }
    activityID = id
    state = content
    submittedStaleDate = staleDate
    refreshAfter = max(now.addingTimeInterval(15), min(now.addingTimeInterval(300), staleDate.addingTimeInterval(-15)))
    return true
  }
  mutating func reset() { activityID = nil; state = nil; refreshAfter = .distantPast; submittedStaleDate = .distantPast }
}

struct LiveActivityPushTarget: Equatable, Sendable {
  let baseURL: URL
  let activityID: String
  let pushToken: String
  let zoneID: String
  let environment: String

  var url: URL { baseURL.appendingPathComponent(activityID) }
  func sameActivity(as other: Self) -> Bool { baseURL == other.baseURL && activityID == other.activityID }
}

/// A single worker orders token/room changes and deletion, including changes
/// that arrive while registration is in flight. Failed registration is backed off.
@MainActor
final class LiveActivityPushRegistrar {
  typealias Register = (LiveActivityPushTarget) async throws -> Void
  typealias Remove = (LiveActivityPushTarget) async throws -> Void
  private let register: Register
  private let remove: Remove
  private let now: () -> Date
  private(set) var registered: LiveActivityPushTarget?
  private var desired: LiveActivityPushTarget?
  private var retryAfter = Date.distantPast
  private var refreshAfter = Date.distantPast
  private var failures = 0
  private var worker: Task<Void, Never>?

  init(register: @escaping Register, remove: @escaping Remove, now: @escaping () -> Date = Date.init) {
    self.register = register; self.remove = remove; self.now = now
  }
  func update(_ target: LiveActivityPushTarget?) {
    if target != desired { retryAfter = .distantPast; failures = 0 }
    desired = target
    guard worker == nil, now() >= retryAfter,
      desired != registered || (desired != nil && now() >= refreshAfter) else { return }
    worker = Task { await self.drain() }
  }
  func retryNow() { retryAfter = .distantPast; refreshAfter = .distantPast; update(desired) }
  func flush() async { await worker?.value }

  private func drain() async {
    defer { worker = nil }
    while now() >= retryAfter {
      let target = desired
      do {
        if let previous = registered, target.map({ !$0.sameActivity(as: previous) }) ?? true {
          try await remove(previous)
          registered = nil
          // Re-read desired after the suspension point.
          continue
        }
        guard let target else { return }
        if target == registered, now() < refreshAfter { return }
        try await register(target)
        registered = target
        refreshAfter = now().addingTimeInterval(300)
        failures = 0
        NowPlayingDiagnostics.record("push.registered")
      } catch {
        if target != desired { continue }
        failures += 1
        retryAfter = now().addingTimeInterval(min(300, 30 * pow(2, Double(min(failures - 1, 4)))))
        // Avoid logging URLSession errors: URLs contain the paired client identifier.
        NowPlayingDiagnostics.record("push.registrationFailed", detail: "retry in \(Int(retryAfter.timeIntervalSince(now())))s")
        return
      }
    }
  }
}
#endif
