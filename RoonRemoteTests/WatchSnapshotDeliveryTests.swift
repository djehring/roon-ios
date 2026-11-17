import Foundation
import Testing

@Suite("Watch background updates")
struct WatchSnapshotDeliveryTests {
  private func snapshot(_ title: String, date: TimeInterval? = nil, image: String? = nil, cover: Data? = nil) -> WatchSnapshot {
    var value = WatchSnapshot.empty
    value.sessionReady = true
    value.zoneId = "kitchen"
    value.zoneName = "Kitchen"
    value.title = title
    value.isPlaying = true
    value.imageKey = image
    value.coverJPEG = cover
    value.updatedAt = date.map { Date(timeIntervalSince1970: $0) }
    return value
  }

  private func withStorage(_ body: (WatchSnapshotStorage, UserDefaults) throws -> Void) rethrows {
    let name = "WatchSnapshotTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(WatchSnapshotStorage(defaults: defaults), defaults)
  }

  @Test func backgroundReceiptPersistsWithoutAScreenAndRestoresArtworkWithItsTrack() throws {
    try withStorage { storage, defaults in
      let current = snapshot("New track", date: 2, image: "new-cover", cover: Data([2, 3]))
      let receipt = try storage.receive(current)
      #expect(receipt == .saved(reloadWidget: true))
      let reopened = WatchSnapshotStorage(defaults: defaults)
      #expect(reopened.snapshot == current)
      #expect(defaults.data(forKey: WatchShared.coverKey) == nil)
    }
  }

  @Test func lateTransfersAndOldApplicationContextCannotReplaceANewerTrack() throws {
    try withStorage { storage, _ in
      let current = snapshot("New", date: 20)
      _ = try storage.receive(current)
      #expect(try storage.receive(snapshot("Old", date: 10)) == .ignored)
      #expect(try storage.receive(snapshot("Legacy context")) == .ignored)
      #expect(storage.snapshot == current)
    }
  }

  @Test func olderPhonePayloadsStillWorkBeforeTheFirstTimestampedPublication() throws {
    try withStorage { storage, _ in
      let data = try JSONEncoder().encode(snapshot("Legacy"))
      let old = try JSONDecoder().decode(WatchSnapshot.self, from: data)
      #expect(old.updatedAt == nil)
      #expect(try storage.receive(old) == .saved(reloadWidget: true))
      #expect(try storage.receive(snapshot("Next legacy")) == .saved(reloadWidget: true))
    }
  }

  @Test func aNewTrackNeverKeepsThePreviousAlbumsArtwork() throws {
    try withStorage { storage, defaults in
      _ = try storage.receive(snapshot("Old", date: 1, image: "old", cover: Data([1])))
      _ = try storage.receive(snapshot("New", date: 2, image: "new"))
      #expect(storage.snapshot?.coverJPEG == nil)
      #expect(WatchSnapshotStorage(defaults: defaults).snapshot?.coverJPEG == nil)
      #expect(try storage.receive(snapshot("New", date: 3, image: "new", cover: Data([3])))
        == .saved(reloadWidget: true))
    }
  }

  @Test func sameAlbumKeepsArrivedArtworkButDuplicateAndVolumeUpdatesDoNotReloadWidgets() throws {
    try withStorage { storage, _ in
      let current = snapshot("Track", date: 1, image: "album", cover: Data([1]))
      _ = try storage.receive(current)
      #expect(try storage.receive(current) == .ignored)
      var changed = snapshot("Track", date: 2, image: "album")
      changed.volume = 55
      #expect(try storage.receive(changed) == .saved(reloadWidget: false))
      #expect(storage.snapshot?.volume == 55)
      #expect(storage.snapshot?.coverJPEG == Data([1]))
      changed.updatedAt = Date(timeIntervalSince1970: 3)
      changed.isPlaying = false
      #expect(try storage.receive(changed) == .saved(reloadWidget: true))
    }
  }

  @Test func publicationIsStableAcrossDeliveryChannelsAndMonotonicAfterRestartOrClockChange() {
    var publisher = WatchSnapshotPublication()
    let original = snapshot("First")
    let first = publisher.stamp(original, now: Date(timeIntervalSince1970: 20))
    #expect(publisher.stamp(original, now: Date(timeIntervalSince1970: 30)) == first)
    let next = publisher.stamp(snapshot("Next"), now: Date(timeIntervalSince1970: 10))
    #expect(next.updatedAt! > first.updatedAt!)
    var restarted = WatchSnapshotPublication(lastDate: publisher.lastDate)
    #expect(restarted.stamp(snapshot("Restarted"), now: Date(timeIntervalSince1970: 10)).updatedAt! > next.updatedAt!)
  }

  @Test func backgroundTimeIsRetainedThroughActivationDeliveryPersistenceAndWidgetReload() {
    let work = WatchBackgroundUpdates()
    var steps: [String] = []
    work.retain { steps.append("completed") }
    work.completeIfReady(activated: false, hasContentPending: false)
    work.completeIfReady(activated: true, hasContentPending: true)
    #expect(steps.isEmpty)
    work.beginDelivery()
    // WCSession has delivered the callback, but its queued persistence has not run.
    work.completeIfReady(activated: true, hasContentPending: false)
    #expect(steps.isEmpty)
    steps.append("saved")
    steps.append("reload requested")
    work.endDelivery()
    work.completeIfReady(activated: true, hasContentPending: false)
    #expect(steps == ["saved", "reload requested", "completed"])
    work.completeIfReady(activated: true, hasContentPending: false)
    #expect(steps.count == 3)
  }

  @Test func allQueuedDeliveriesMustFinishBeforeMultipleBackgroundTasksComplete() {
    let work = WatchBackgroundUpdates()
    var completed = 0
    work.retain { completed += 1 }
    work.retain { completed += 1 }
    work.beginDelivery()
    work.beginDelivery()
    work.endDelivery()
    work.completeIfReady(activated: true, hasContentPending: false)
    #expect(completed == 0)
    work.endDelivery()
    work.completeIfReady(activated: true, hasContentPending: false)
    #expect(completed == 2)
  }
}
