import XCTest

final class CinemaMusicUITests: XCTestCase {
  @MainActor private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-roon-demo-store"]
    app.launchEnvironment["ROON_CINEMA_PREVIEW_JSON"] = CinemaPlaylistFixture.json
    app.launchEnvironment["ROON_CINEMA_PREVIEW_LIBRARY"] = "1"
    app.launchEnvironment["ROON_CINEMA_MUSIC_JSON"] = """
      {"tracks":[{"artist":"Miles Davis","track":"So What","album":"Kind of Blue"},
      {"artist":"Miles Davis","track":"Freddie Freeloader","album":"Kind of Blue"}]}
      """
    app.launch()
    return app
  }

  @MainActor func testAddAlbumReorderUndoSaveAndReopen() {
    let app = launch()
    XCTAssertTrue(app.buttons["cinema-edit"].waitForExistence(timeout: 10))
    app.buttons["cinema-edit"].tap()
    openMusic(app)
    XCTAssertTrue(app.navigationBars["Music"].waitForExistence(timeout: 5))
    app.buttons["cinema-add-music"].tap()
    app.buttons["cinema-browse-albums"].tap()
    app.buttons["Kind of Blue"].tap()
    app.buttons["cinema-add-collection"].tap()
    let add = app.buttons["cinema-confirm-add"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    XCTAssertEqual(add.label, "Add 2 tracks")
    add.tap()
    XCTAssertTrue(app.staticTexts["3 tracks"].waitForExistence(timeout: 5))
    app.buttons["cinema-track-actions-2"].tap()
    app.buttons["Move to start"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["cinema-track-0"].firstMatch.label.contains("Freddie Freeloader"))
    app.buttons["cinema-track-actions-1"].tap()
    app.buttons["Remove"].tap()
    XCTAssertTrue(app.staticTexts["2 tracks"].exists)
    app.buttons["cinema-music-undo"].tap()
    XCTAssertTrue(app.staticTexts["3 tracks"].exists)
    capture("Cinema music after reordering")
    app.navigationBars["Music"].buttons.element(boundBy: 0).tap()
    app.buttons["cinema-save"].tap()
    XCTAssertTrue(app.buttons["cinema-edit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Updating pictures…"].exists)
    app.buttons["cinema-edit"].tap()
    XCTAssertTrue(app.staticTexts["Edit Cinema"].waitForExistence(timeout: 5))
    openMusic(app)
    XCTAssertTrue(app.navigationBars["Music"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["cinema-track-0"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["3 tracks"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["cinema-track-0"].firstMatch.label.contains("Freddie Freeloader"))
    capture("Saved Cinema music")
  }

  @MainActor func testNewCinemaStartsWithMusicAndSavesWithoutResearch() {
    let app = launch()
    XCTAssertTrue(app.buttons["cinema-new"].waitForExistence(timeout: 10))
    app.buttons["cinema-new"].tap()
    XCTAssertTrue(app.navigationBars["Create Cinema"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Album artwork"].exists || app.buttons["cinema-mode"].label.contains("Album artwork"))
    openMusic(app)
    app.buttons["cinema-add-music"].tap()
    app.buttons["cinema-browse-playlists"].tap()
    app.buttons["Kind of Blue"].tap()
    app.buttons["cinema-add-collection"].tap()
    app.buttons["cinema-confirm-add"].tap()
    XCTAssertTrue(app.staticTexts["2 tracks"].waitForExistence(timeout: 5))
    app.navigationBars["Music"].buttons.element(boundBy: 0).tap()
    for _ in 0..<5 where !app.buttons["cinema-save"].isHittable { app.swipeUp() }
    app.buttons["cinema-save"].tap()
    XCTAssertTrue(app.staticTexts["Cinema saved."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["cinema-edit"].isEnabled)
    capture("New Cinema saved from a playlist")
  }

  @MainActor private func openMusic(_ app: XCUIApplication) {
    let button = app.buttons["cinema-edit-music"]
    var previousFrame: CGRect?
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard button.exists, button.isHittable else { return false }
      let frame = button.frame
      defer { previousFrame = frame }
      return previousFrame == frame
    }, object: nil)
    // Full-screen presentation can expose accessibility before its slide finishes.
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    button.tap()
  }

  @MainActor private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
}
