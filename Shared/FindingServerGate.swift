/// When the first-paint overlay should stay up.
///
/// Paired launch paints `.main` before the bridge has spoken, and Bonjour
/// search can take several seconds. Both of those used to be a blank
/// background. The overlay covers that wait and drops the moment there is
/// something to show, or the attempt has given up.
enum FindingServerGate {
  static func isVisible(isAwaitingServer: Bool, isDiscovering: Bool) -> Bool {
    isAwaitingServer || isDiscovering
  }

  /// Still waiting for a useful house picture after a paired reconnect.
  static func stillAwaitingServer(
    hasRooms: Bool,
    isSynced: Bool,
    reconnectFailed: Bool
  ) -> Bool {
    if reconnectFailed { return false }
    if hasRooms || isSynced { return false }
    return true
  }
}
