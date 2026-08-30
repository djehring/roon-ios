import Testing

@Suite("Queue routing")
struct QueueRoutingTests {
  @Test("a labelled event keeps its own zone")
  func labelledEvent() {
    #expect(
      QueueRouting.zoneId(payloadZoneId: "kitchen", displayedZoneId: "sitting") == "kitchen"
    )
  }

  @Test("an unlabelled event is attributed to the displayed zone")
  func unlabelledEvent() {
    // The regression behind a queue that kept showing another room's tracks: the
    // bridge omits zone_id on some events, and comparing "" to the selection
    // discarded them.
    #expect(
      QueueRouting.zoneId(payloadZoneId: "", displayedZoneId: "kitchen") == "kitchen"
    )
  }

  @Test("an unplaceable event is dropped rather than mis-attributed")
  func unplaceableEvent() {
    #expect(QueueRouting.zoneId(payloadZoneId: "", displayedZoneId: "") == nil)
  }

  @Test("a labelled event survives having no zone selected yet")
  func labelledEventWithoutSelection() {
    #expect(
      QueueRouting.zoneId(payloadZoneId: "kitchen", displayedZoneId: "") == "kitchen"
    )
  }

  @Test("a labelled event for the displayed zone resolves to it")
  func labelledEventForDisplayedZone() {
    #expect(
      QueueRouting.zoneId(payloadZoneId: "kitchen", displayedZoneId: "kitchen") == "kitchen"
    )
  }
}
