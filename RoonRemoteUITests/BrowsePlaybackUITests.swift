import XCTest

final class BrowsePlaybackUITests: XCTestCase {
  @MainActor func testFirstPerformerHasItsOwnDiscographyLink() {
    checkPerformerLink("Alina Ibragimova")
  }

  @MainActor func testSecondPerformerHasItsOwnDiscographyLink() {
    checkPerformerLink("Cédric Tiberghien")
  }

  @MainActor private func checkPerformerLink(_ name: String) {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_ARTIST_PREVIEW_CLASSICAL"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["Alina Ibragimova"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons["Cédric Tiberghien"].exists)
    XCTAssertFalse(app.buttons["Ludwig van Beethoven"].exists)
    capture("Separate performer links")
    app.buttons[name].tap()
    XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Beethoven: Violin Sonatas Op. 12 & Op. 24"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Alina Ibragimova, Cédric Tiberghien"].firstMatch.exists)
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "[[")).firstMatch.exists)
    XCTAssertFalse(app.descendants(matching: .any)["browse-playback-feedback"].firstMatch.exists)
    capture("Discography for \(name)")
  }

  @MainActor func testNowPlayingArtistOpensDiscography() {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launch()
    let artist = app.buttons["now-playing-artist-link"]
    XCTAssertTrue(artist.waitForExistence(timeout: 5))
    artist.tap()
    XCTAssertTrue(app.navigationBars["Miles Davis"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["1958 Miles"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["A Love Supreme"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["now-playing-screen"].firstMatch.exists)
    if app.tabBars.buttons["Library"].exists {
      XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
    }
    capture("Artist discography in Library")
    open("1958 Miles", in: app)
    XCTAssertTrue(app.staticTexts["Play Album"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["browse-playback-feedback"].firstMatch.exists)
  }

  @MainActor func testArtistLinkReplacesPreviousLibraryNavigation() {
    let app = launch(hierarchy: "playlists")
    open("A Love Supreme", in: app)
    open("Freddie Freeloader", in: app)
    let artist = app.buttons["now-playing-artist-link"]
    XCTAssertTrue(artist.waitForExistence(timeout: 8))
    artist.tap()
    XCTAssertTrue(app.navigationBars["Miles Davis"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["1958 Miles"].firstMatch.waitForExistence(timeout: 5))
    // Returning from an album should retain the artist destination.
    open("1958 Miles", in: app)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["Miles Davis"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["1958 Miles"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor func testPlaylistTrackOpensNowPlaying() {
    let app = launch(hierarchy: "playlists")
    open("A Love Supreme", in: app)
    open("Freddie Freeloader", in: app)
    XCTAssertTrue(app.descendants(matching: .any)["browse-playback-feedback"].firstMatch.waitForExistence(timeout: 3))
    capture("Browse playback feedback")
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].exists)
    capture("Now Playing after browse")
  }

  @MainActor func testAlbumPlayNowOpensNowPlaying() {
    let app = launch(hierarchy: "albums")
    open("1958 Miles", in: app)
    open("Play Album", in: app)
    XCTAssertTrue(app.descendants(matching: .any)["now-playing-screen"].firstMatch.waitForExistence(timeout: 8))
  }

  @MainActor func testPlayNextKeepsBrowseOpen() {
    let app = launch(hierarchy: "albums")
    open("1958 Miles", in: app)
    open("So What", in: app)
    open("Play Next", in: app)
    let feedback = app.descendants(matching: .any)["browse-playback-feedback"].firstMatch
    XCTAssertTrue(feedback.waitForExistence(timeout: 3))
    XCTAssertTrue(feedback.waitForNonExistence(timeout: 6))
    XCTAssertTrue(app.staticTexts["Play Next"].firstMatch.exists)
    XCTAssertFalse(app.descendants(matching: .any)["now-playing-screen"].firstMatch.exists)
  }

  @MainActor func testFailureKeepsBrowseOpen() {
    let app = launch(hierarchy: "playlists", fail: true)
    open("A Love Supreme", in: app)
    open("Freddie Freeloader", in: app)
    XCTAssertTrue(app.alerts["Unable to complete playback action"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.staticTexts["Freddie Freeloader"].firstMatch.exists)
    XCTAssertFalse(app.descendants(matching: .any)["now-playing-screen"].firstMatch.exists)
  }

  @MainActor private func launch(hierarchy: String, fail: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_BROWSE_PREVIEW_HIERARCHY"] = hierarchy
    app.launchEnvironment["ROON_BROWSE_PREVIEW_FAIL"] = fail ? "1" : "0"
    app.launch()
    return app
  }

  @MainActor private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func open(_ title: String, in app: XCUIApplication) {
    let item = app.staticTexts[title].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    item.tap()
  }
}
