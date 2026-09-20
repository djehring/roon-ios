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

@Suite("AI search playback")
struct AISearchPlaybackTests {
  private func result(
    title: String = "Mah Na Mah Na",
    artist: String = "The Muppets",
    album: String = "The Muppets: The Green Album"
  ) -> SuggestedTrack {
    SuggestedTrack(id: title, title: title, artist: artist, album: album, corrected: false)
  }

  private func payload(
    track: String = "Mah Na Mah Na",
    artist: String = "The Muppets",
    album: String = "A different album",
    error: String? = "Track not found on album"
  ) -> SuggestedTrackPayload {
    SuggestedTrackPayload(
      artist: artist,
      album: album,
      track: track,
      error: error
    )
  }

  @Test("a play failure still marks the row when the album was rewritten")
  func marksRowWhenAlbumChanged() {
    var results = [result()]
    let message = AISearchPlayback.applyUnfound([payload()], to: &results)

    #expect(results[0].error == "Track not found on album")
    #expect(message == "Track not found on album")
  }

  @Test("an empty unfound list leaves results alone")
  func emptyUnfound() {
    var results = [result()]
    #expect(AISearchPlayback.applyUnfound([], to: &results) == nil)
    #expect(results[0].error == nil)
  }

  @Test("all playable tracks failed when each one is returned unfound")
  func allFailed() {
    #expect(
      AISearchPlayback.allFailed(playable: [result()], unfound: [payload()])
    )
  }

  @Test("Mah Na Mah Na matches Mahna Mahna")
  func compactTitleMatch() {
    #expect(RoonVoiceMatch.titlesMatch("Mah Na Mah Na", "Mahna Mahna"))
    #expect(RoonVoiceMatch.titlesMatch("Mah-Na-Mah-Na", "Mah Na Mah Na"))
    #expect(!RoonVoiceMatch.titlesMatch("Mah Na Mah Na", "Rainbow Connection"))
  }

  @Test("The Muppets still matches a Muppet Show album subtitle")
  func artistAlignsWithAlbumSubtitle() {
    #expect(AISearchPlayback.artistsAlign("The Muppets", "The Muppet Show: Music, Mayhem, and More!"))
    #expect(AISearchPlayback.artistsAlign("The Muppets", "The Muppets"))
    #expect(!AISearchPlayback.artistsAlign("The Muppets", "The Beatles"))
  }
}

@Suite("Roon display text")
struct RoonDisplayTextTests {
  @Test func stripsLinkedCreditsAndLeavesPlainNames() {
    #expect(
      RoonDisplayText.format("[[44398900|Alexei Watkin]] / [[44598650|Michael Magee]]")
        == "Alexei Watkin / Michael Magee"
    )
    #expect(
      RoonDisplayText.format("[[25460090|Peter Fisher]] / Chamber Orchestra of London")
        == "Peter Fisher / Chamber Orchestra of London"
    )
    #expect(RoonDisplayText.format("[[Eclogue]]") == "Eclogue")
    #expect(RoonDisplayText.format("English Music for Strings") == "English Music for Strings")
  }

  @Test func matchingIgnoresRoonCreditIds() {
    #expect(
      RoonVoiceMatch.titlesMatch(
        "[[25460090|Peter Fisher]]",
        "Peter Fisher"
      )
    )
  }
}
