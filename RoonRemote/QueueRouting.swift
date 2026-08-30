import Foundation

enum QueueRouting {
  /// Which zone a queue event belongs to, or `nil` when it cannot be placed.
  ///
  /// The bridge leaves `zone_id` off some queue events, and unlabelled SSE
  /// payloads are recovered without one at all. Those describe the zone this
  /// client is already watching, so they are attributed to the displayed zone.
  /// Comparing the empty string against the selection instead silently discarded
  /// them, which left Up Next and the queue showing whatever room had last sent
  /// a labelled event — the previous room's tracks, long after a playlist had
  /// replaced them.
  static func zoneId(payloadZoneId: String, displayedZoneId: String) -> String? {
    let resolved = payloadZoneId.isEmpty ? displayedZoneId : payloadZoneId
    return resolved.isEmpty ? nil : resolved
  }
}
