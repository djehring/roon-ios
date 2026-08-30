import Testing

@Suite("Regular Search selection")
struct SearchSelectionTests {
  @Test("keeps the current result while it remains available")
  func preservesCurrent() {
    #expect(
      SearchSelection.resolved(current: "b", available: ["a", "b", "c"]) == "b"
    )
  }

  @Test("reordering results does not change the current result")
  func preservesCurrentAcrossReordering() {
    #expect(
      SearchSelection.resolved(current: 2, available: [3, 2, 1]) == 2
    )
  }

  @Test("selects the first result when the current one disappears")
  func fallsBackAfterRemoval() {
    #expect(
      SearchSelection.resolved(current: "gone", available: ["first", "second"]) == "first"
    )
  }

  @Test("selects the first result when there was no selection")
  func initialSelection() {
    #expect(
      SearchSelection.resolved(current: Optional<String>.none, available: ["first", "second"])
        == "first"
    )
  }

  @Test("an empty result set clears the selection")
  func emptyResults() {
    #expect(
      SearchSelection.resolved(current: "gone", available: [String]()) == nil
    )
  }
}
