import Foundation
import Testing

@Suite("Live Activity publication")
struct LiveActivityPublicationTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var content: RoonNowPlayingAttributes.ContentState {
    .init(zoneName: "Office", title: "Young Americans", artist: "David Bowie", isPlaying: true, zoneID: "office")
  }
  @Test func unchangedTicksDoNotRetryWhenActivityKitStillReportsThePreviousTrack() {
    var gate = LiveActivityPublicationGate()
    let publication1 = gate.shouldPublish(id: "activity", content: content, staleDate: now.addingTimeInterval(400), now: now)
    #expect(publication1)
    for second in 1...180 {
      let publication2 = gate.shouldPublish(id: "activity", content: content, staleDate: now.addingTimeInterval(400), now: now.addingTimeInterval(Double(second)))
      #expect(!publication2)
    }
    var changed = content; changed.title = "Win"
    let publication3 = gate.shouldPublish(id: "activity", content: changed, staleDate: now.addingTimeInterval(600), now: now.addingTimeInterval(181))
    #expect(publication3)
  }
  @Test func replacedActivitiesAndForegroundRecoveryCanPublishTheSameTrack() {
    var gate = LiveActivityPublicationGate()
    _ = gate.shouldPublish(id: "old", content: content, staleDate: now.addingTimeInterval(600), now: now)
    let publication4 = gate.shouldPublish(id: "new", content: content, staleDate: now.addingTimeInterval(600), now: now)
    #expect(publication4)
    gate.reset()
    let publication5 = gate.shouldPublish(id: "new", content: content, staleDate: now.addingTimeInterval(600), now: now)
    #expect(publication5)
  }
  @Test func longTracksRenewFreshnessWithoutPerSecondUpdates() {
    var gate = LiveActivityPublicationGate()
    _ = gate.shouldPublish(id: "a", content: content, staleDate: now.addingTimeInterval(600), now: now)
    let publication6 = gate.shouldPublish(id: "a", content: content, staleDate: now.addingTimeInterval(700), now: now.addingTimeInterval(100))
    #expect(!publication6)
    let publication7 = gate.shouldPublish(id: "a", content: content, staleDate: now.addingTimeInterval(900), now: now.addingTimeInterval(300))
    #expect(publication7)
  }
  @Test func staleDeadlineUsesTrackBoundaryAndDoesNotSlideWithoutNewRoomData() throws {
    let track = Track(id: "song", title: "Song", artist: "Artist", album: "Album", position: "1:00", remaining: "3:00", progress: 0.25, durationSeconds: 240)
    let snapshot = try #require(NowPlayingSnapshot(zone: .init(id: "office", name: "Office", track: track, state: .playing), isPlaying: true))
    #expect(snapshot.staleDate(observedAt: now) == now.addingTimeInterval(225))
    let radio = try #require(NowPlayingSnapshot(zone: .init(id: "office", name: "Office", track: nil, state: .playing), isPlaying: true))
    #expect(radio.staleDate(observedAt: now) == now.addingTimeInterval(600))
    var gate = LiveActivityPublicationGate()
    _ = gate.shouldPublish(id: "a", content: content, staleDate: now.addingTimeInterval(600), now: now)
    let afterSeek = gate.shouldPublish(id: "a", content: content, staleDate: now.addingTimeInterval(60), now: now.addingTimeInterval(10))
    #expect(afterSeek)
  }
  @Test func olderLocalOnlyActivitiesAreIdentifiableForMigration() throws {
    let attributes = try JSONDecoder().decode(RoonNowPlayingAttributes.self, from: Data(#"{"zoneId":"office"}"#.utf8))
    #expect(attributes.pushEnabled == nil)
    #expect(RoonNowPlayingAttributes(zoneId: "office", pushEnabled: true).pushEnabled == true)
  }
}

@MainActor
@Suite("Live Activity push registration", .serialized)
struct LiveActivityPushRegistrationTests {
  private var target: LiveActivityPushTarget {
    .init(baseURL: URL(string: "http://bridge.local:3000/api/paired/live-activities")!, activityID: "activity", pushToken: "token", zoneID: "office", environment: "sandbox")
  }
  @Test func failedRegistrationBacksOffAndForegroundCanRetry() async {
    var attempts = 0
    var clock = Date(timeIntervalSince1970: 1000)
    let registrar = LiveActivityPushRegistrar(register: { _ in attempts += 1; throw URLError(.notConnectedToInternet) }, remove: { _ in }, now: { clock })
    registrar.update(target); await registrar.flush()
    for _ in 0..<100 { registrar.update(target); await registrar.flush() }
    #expect(attempts == 1)
    clock = clock.addingTimeInterval(30)
    registrar.update(target); await registrar.flush()
    #expect(attempts == 2)
    registrar.retryNow(); await registrar.flush()
    #expect(attempts == 3)
    #expect(registrar.registered == nil)
  }
  @Test func roomAndTokenChangesRegisterImmediatelyButIdenticalTicksDoNot() async {
    var registrations: [LiveActivityPushTarget] = []
    let registrar = LiveActivityPushRegistrar(register: { registrations.append($0) }, remove: { _ in })
    registrar.update(target); await registrar.flush()
    registrar.update(target); await registrar.flush()
    let next = LiveActivityPushTarget(baseURL: target.baseURL, activityID: target.activityID, pushToken: "new-token", zoneID: "kitchen", environment: "sandbox")
    registrar.update(next); await registrar.flush()
    #expect(registrations == [target, next])
    #expect(registrar.registered == next)
  }
  @Test func endingWhileRegistrationIsInFlightDeletesAfterItCompletes() async {
    var continuation: CheckedContinuation<Void, Never>?
    var removed: [LiveActivityPushTarget] = []
    let registrar = LiveActivityPushRegistrar(register: { _ in
      await withCheckedContinuation { continuation = $0 }
    }, remove: { removed.append($0) })
    registrar.update(target)
    while continuation == nil { await Task.yield() }
    registrar.update(nil)
    continuation?.resume()
    await registrar.flush()
    #expect(removed == [target])
    #expect(registrar.registered == nil)
  }
  @Test func changingBridgeRemovesTheOldSubscriptionBeforeRegisteringTheNewOne() async {
    var steps: [String] = []
    let registrar = LiveActivityPushRegistrar(register: { steps.append("register \($0.baseURL.host!)") }, remove: { steps.append("remove \($0.baseURL.host!)") })
    registrar.update(target); await registrar.flush()
    let next = LiveActivityPushTarget(baseURL: URL(string: "http://other.local/api/paired/live-activities")!, activityID: target.activityID, pushToken: target.pushToken, zoneID: target.zoneID, environment: "sandbox")
    registrar.update(next); await registrar.flush()
    #expect(steps == ["register bridge.local", "remove bridge.local", "register other.local"])
  }
}
