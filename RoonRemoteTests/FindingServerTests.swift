import Testing

@Suite("Finding server overlay")
struct FindingServerTests {
  @Test("paired reconnect with no rooms yet stays covered")
  func awaitingKeepsOverlay() {
    #expect(FindingServerGate.isVisible(isAwaitingServer: true, isDiscovering: false))
    #expect(
      FindingServerGate.stillAwaitingServer(
        hasRooms: false,
        isSynced: false,
        reconnectFailed: false
      )
    )
  }

  @Test("Bonjour search covers the finding step")
  func discoveringKeepsOverlay() {
    #expect(FindingServerGate.isVisible(isAwaitingServer: false, isDiscovering: true))
  }

  @Test("rooms or SYNC dismiss the reconnect overlay")
  func usefulStateHidesOverlay() {
    #expect(
      !FindingServerGate.stillAwaitingServer(
        hasRooms: true,
        isSynced: false,
        reconnectFailed: false
      )
    )
    #expect(
      !FindingServerGate.stillAwaitingServer(
        hasRooms: false,
        isSynced: true,
        reconnectFailed: false
      )
    )
    #expect(!FindingServerGate.isVisible(isAwaitingServer: false, isDiscovering: false))
  }

  @Test("a failed reconnect uncovers onboarding")
  func failedReconnectHidesOverlay() {
    #expect(
      !FindingServerGate.stillAwaitingServer(
        hasRooms: false,
        isSynced: false,
        reconnectFailed: true
      )
    )
  }
}
