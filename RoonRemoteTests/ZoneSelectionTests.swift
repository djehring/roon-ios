import Testing

@Suite("Room selection recovery")
struct ZoneSelectionTests {
  private let kitchen = Zone(id: "kitchen", name: "Kitchen", track: nil, state: .paused)
  private let office = Zone(id: "office", name: "Office", track: nil, state: .stopped)

  private func state(_ rooms: [Zone], sync: RoonSyncState = .sync) -> ApiStatePayload {
    ApiStatePayload(
      state: sync,
      zones: rooms.map { ZoneDescription(zoneId: $0.id, displayName: $0.name) },
      outputs: []
    )
  }

  @Test("a saved ID absent from the first room list recovers to the displayed room")
  func staleSavedSelection() {
    let snapshot = ZoneSelection.reconcile(
      current: [], selectedZoneId: "removed-room", state: state([kitchen, office])
    )
    #expect(snapshot.selectedZoneId == "kitchen")
    #expect(snapshot.selectedZoneId == snapshot.zones.first?.id)
  }

  @Test("a valid saved selection survives reconnect regardless of room order")
  func validSelection() {
    let snapshot = ZoneSelection.reconcile(
      current: [], selectedZoneId: "office", state: state([kitchen, office])
    )
    #expect(snapshot.selectedZoneId == "office")
  }

  @Test("removing a selected room removes its stale state and selects a current room")
  func selectedRoomRemoved() {
    let snapshot = ZoneSelection.reconcile(
      current: [kitchen, office], selectedZoneId: "kitchen", state: state([office])
    )
    #expect(snapshot.zones.map(\.id) == ["office"])
    #expect(snapshot.selectedZoneId == "office")
  }

  @Test("remaining rooms retain playback details while their names refresh")
  func retainTrackAndRefreshName() {
    var playing = kitchen
    playing.state = .playing
    playing.track = Track(
      id: "track", title: "So What", artist: "Miles Davis", album: "Kind of Blue",
      position: "0:30", remaining: "8:52", progress: 0.05
    )
    var renamed = kitchen
    renamed.name = "Kitchen speakers"
    let snapshot = ZoneSelection.reconcile(
      current: [playing, office], selectedZoneId: "kitchen", state: state([renamed])
    )
    #expect(snapshot.zones.first?.name == "Kitchen speakers")
    #expect(snapshot.zones.first?.track == playing.track)
    #expect(snapshot.zones.first?.state == .playing)
    #expect(snapshot.selectedZoneId == "kitchen")
  }

  @Test("transient reconnect states preserve the saved selection and room state",
        arguments: [RoonSyncState.starting, .syncing, .lost, .stopped])
  func transientState(sync: RoonSyncState) {
    let snapshot = ZoneSelection.reconcile(
      current: [kitchen, office], selectedZoneId: "office", state: state([], sync: sync)
    )
    #expect(snapshot.zones == [kitchen, office])
    #expect(snapshot.selectedZoneId == "office")
  }

  @Test("an empty synced house clears the unavailable selection and recovers when rooms return")
  func allRoomsRemovedAndReturn() {
    let empty = ZoneSelection.reconcile(
      current: [kitchen], selectedZoneId: "kitchen", state: state([])
    )
    #expect(empty.zones.isEmpty)
    #expect(empty.selectedZoneId.isEmpty)
    let restored = ZoneSelection.reconcile(
      current: empty.zones, selectedZoneId: empty.selectedZoneId, state: state([office])
    )
    #expect(restored.selectedZoneId == "office")
  }
}
