import Foundation

enum ZoneSelection {
  struct Snapshot {
    var zones: [Zone]
    var selectedZoneId: String
  }

  /// SYNC contains the complete room list. Retain track details for rooms that
  /// still exist, but never keep sending commands to a room Roon has removed.
  static func reconcile(
    current: [Zone],
    selectedZoneId: String,
    state: ApiStatePayload
  ) -> Snapshot {
    let incoming = state.zones.map { description in
      var zone = current.first { $0.id == description.zoneId } ?? Zone(
        id: description.zoneId, name: description.displayName, track: nil, state: .stopped
      )
      zone.name = description.displayName
      return zone
    }
    guard state.state == .sync else {
      // A reconnect can briefly report no rooms. Wait for a complete snapshot
      // before replacing the saved selection or discarding the last room state.
      let newZones = incoming.filter { candidate in !current.contains { $0.id == candidate.id } }
      return Snapshot(zones: current + newZones, selectedZoneId: selectedZoneId)
    }
    let selection = incoming.contains { $0.id == selectedZoneId }
      ? selectedZoneId : incoming.first?.id ?? ""
    return Snapshot(zones: incoming, selectedZoneId: selection)
  }
}
